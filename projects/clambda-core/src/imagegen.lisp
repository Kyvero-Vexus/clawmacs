;;;; src/imagegen.lisp — OpenRouter free image generation for Clawmacs
;;;;
;;;; Translates the openrouter-imagegen shell skill into idiomatic Common Lisp.
;;;; Uses OpenRouter's /api/v1/chat/completions endpoint with modalities:["image"].
;;;;
;;;; API key resolution order:
;;;;   1. *openrouter-api-key* (setf from init.lisp)
;;;;   2. OPENROUTER_API_KEY environment variable
;;;;   3. ~/.openclaw/openclaw.json env.OPENROUTER_API_KEY
;;;;
;;;; Usage:
;;;;   (clawmacs/imagegen:generate-image
;;;;     :prompt "a cat wearing a hat"
;;;;     :output #P"/tmp/cat.png")
;;;;
;;;;   ;; With a different model:
;;;;   (clawmacs/imagegen:generate-image
;;;;     :prompt "sunset over the ocean"
;;;;     :output #P"/tmp/sunset.png"
;;;;     :model "sourceful/riverflow-v2-fast")

(in-package #:clawmacs/imagegen)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 1. Configuration
;;;; ─────────────────────────────────────────────────────────────────────────────

(defvar *openrouter-api-key* nil
  "OpenRouter API key for image generation.
If NIL, resolved from OPENROUTER_API_KEY env or ~/.openclaw/openclaw.json.")

(defvar *imagegen-default-model* "black-forest-labs/flux.2-pro"
  "Default image generation model.")

(defparameter *available-models*
  '("black-forest-labs/flux.2-pro"
    "black-forest-labs/flux.2-max"
    "black-forest-labs/flux.2-flex"
    "black-forest-labs/flux.2-klein-4b"
    "sourceful/riverflow-v2-pro"
    "sourceful/riverflow-v2-fast"
    "sourceful/riverflow-v2-fast-preview"
    "sourceful/riverflow-v2-standard-preview"
    "sourceful/riverflow-v2-max-preview"
    "bytedance-seed/seedream-4.5")
  "All free OpenRouter image generation models.")

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 2. API Key Resolution
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun read-openclaw-json-key (key-path)
  "Read a nested key from ~/.openclaw/openclaw.json.
KEY-PATH is a list of string keys to traverse.
Returns the value string or NIL."
  (let ((config-path (merge-pathnames ".openclaw/openclaw.json"
                                      (user-homedir-pathname))))
    (when (probe-file config-path)
      (handler-case
          (let* ((json-str (uiop:read-file-string config-path))
                 (parsed   (com.inuoe.jzon:parse json-str)))
            (reduce (lambda (obj k)
                      (when (hash-table-p obj)
                        (gethash k obj)))
                    key-path
                    :initial-value parsed))
        (error () nil)))))

(defun resolve-api-key ()
  "Resolve the OpenRouter API key from config, environment, or openclaw.json.
Signals an error if no key is found."
  (or *openrouter-api-key*
      (let ((env-key (uiop:getenv "OPENROUTER_API_KEY")))
        (when (and env-key (not (string= env-key "")))
          env-key))
      (read-openclaw-json-key '("env" "OPENROUTER_API_KEY"))
      (error (make-condition 'simple-error :format-control "OPENROUTER_API_KEY not found. Set clawmacs/imagegen:*openrouter-api-key*, the OPENROUTER_API_KEY environment variable, or add it to ~~/.openclaw/openclaw.json under env.OPENROUTER_API_KEY."))))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 3. Core API Call
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun call-openrouter-imagegen (prompt model api-key)
  "Call OpenRouter image generation API. Returns parsed JSON response hash table."
  (let* ((payload (com.inuoe.jzon:stringify
                   (alexandria:alist-hash-table
                    `(("model"      . ,model)
                      ("messages"   . ,(vector
                                        (alexandria:alist-hash-table
                                         `(("role"    . "user")
                                           ("content" . ,prompt))
                                         :test #'equal)))
                      ("modalities" . ,(vector "image")))
                    :test #'equal)))
         (response (dexador:post
                    "https://openrouter.ai/api/v1/chat/completions"
                    :headers `(("Authorization" . ,(concatenate 'string "Bearer " api-key))
                               ("Content-Type"  . "application/json"))
                    :content payload
                    :connect-timeout 30
                    :read-timeout 120)))
    (com.inuoe.jzon:parse response :max-string-length (* 64 1024 1024))))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 4. Response Parsing & Image Extraction
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun extract-image-data-url (response)
  "Extract the base64 data URL from an OpenRouter image response.
Returns the data URL string (data:image/png;base64,...) or signals an error."
  (let ((error-obj (gethash "error" response)))
    (when error-obj
      (let ((msg (or (and (hash-table-p error-obj)
                          (gethash "message" error-obj))
                     (format nil "~a" error-obj))))
        (error "OpenRouter API error: ~a" msg))))

  (let* ((choices (gethash "choices" response))
         (_ (unless (and choices (> (length choices) 0))
              (error "No choices in OpenRouter response")))
         (message (gethash "message" (aref choices 0)))
         (images  (gethash "images" message)))
    (declare (ignore _))
    (unless (and images (> (length images) 0))
      (error "No images in response. Content: ~a"
             (subseq (or (gethash "content" message) "") 0
                     (min 200 (length (or (gethash "content" message) ""))))))
    (let ((url (gethash "url" (gethash "image_url" (aref images 0)))))
      (unless (and url (search "data:" url))
        (error "Unexpected image URL format: ~a" (subseq url 0 (min 100 (length url)))))
      url)))

(defun decode-data-url-to-bytes (data-url)
  "Decode a base64 data URL (data:...;base64,<b64>) to a byte vector."
  (let* ((comma-pos (position #\, data-url))
         (b64-str   (subseq data-url (1+ comma-pos)))
         ;; Use cl-base64 if available, else fallback to SBCL internal
         (bytes     (handler-case
                        (progn
                          (ql:quickload "cl-base64" :silent t)
                          (funcall (find-symbol "BASE64-STRING-TO-USECONDARY-VECTOR"
                                                "CL-BASE64")
                                   b64-str))
                      (error ()
                        ;; Fallback: use SBCL's sb-ext
                        nil))))
    (or bytes
        ;; Pure CL base64 decode
        (let* ((b64-chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
               (result    (make-array (ceiling (* (length b64-str) 3) 4)
                                      :element-type '(unsigned-byte 8)
                                      :fill-pointer 0)))
          (loop for i from 0 below (length b64-str) by 4
                for a = (position (char b64-str i)       b64-chars)
                for b = (position (char b64-str (+ i 1)) b64-chars)
                for c = (when (< (+ i 2) (length b64-str))
                          (let ((ch (char b64-str (+ i 2))))
                            (unless (char= ch #\=)
                              (position ch b64-chars))))
                for d = (when (< (+ i 3) (length b64-str))
                          (let ((ch (char b64-str (+ i 3))))
                            (unless (char= ch #\=)
                              (position ch b64-chars))))
                when (and a b)
                  do (vector-push (logior (ash a 2) (ash b -4)) result)
                when (and c)
                  do (vector-push (logior (ash (logand b 15) 4) (ash c -2)) result)
                when (and d)
                  do (vector-push (logior (ash (logand c 3) 6) d) result))
          result))))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 5. Public API
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun generate-image (&key prompt output (model *imagegen-default-model*))
  "Generate an image using OpenRouter's free image models.

Arguments:
  PROMPT  — (required) image description string
  OUTPUT  — (required) output file path (pathname or string)
  MODEL   — model to use (default: *imagegen-default-model*)

Returns the output pathname on success.
Signals an error on failure.

Example:
  (generate-image :prompt \"a cyberpunk city at night\"
                  :output #P\"/tmp/city.png\")"
  (check-type prompt string)
  (let* ((output-path (etypecase output
                        (pathname output)
                        (string   (pathname output))))
         (api-key     (resolve-api-key)))

    (format t "~&[clawmacs/imagegen] Generating image with ~a...~%" model)
    (finish-output)

    (let* ((response  (call-openrouter-imagegen prompt model api-key))
           (data-url  (extract-image-data-url response))
           (bytes     (decode-data-url-to-bytes data-url)))

      ;; Ensure output directory exists
      (let ((dir (directory-namestring output-path)))
        (when (and dir (not (string= dir "")))
          (ensure-directories-exist output-path)))

      ;; Write the image file
      (with-open-file (out output-path
                           :direction         :output
                           :element-type      '(unsigned-byte 8)
                           :if-exists         :supersede
                           :if-does-not-exist :create)
        (write-sequence bytes out))

      (format t "~&[clawmacs/imagegen] Saved ~a bytes to ~a~%"
              (length bytes) (namestring output-path))
      (finish-output)

      ;; Print MEDIA: line for OpenClaw auto-attach
      (format t "~&MEDIA:~a~%" (namestring (truename output-path)))
      (finish-output)

      output-path)))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 6. Tool Registration (for use with Clawmacs agents)
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun register-imagegen-tool! (registry)
  "Register the generate-image tool into REGISTRY (a clawmacs/tools:tool-registry).
Call this from init.lisp to give agents image generation capability.

Example:
  (register-imagegen-tool! (agent-tool-registry my-agent))"
  (clawmacs/tools:define-tool
   registry
   "generate_image"
   "Generate an image using free OpenRouter image models (FLUX, Riverflow, Seedream). Returns the output file path."
   (("prompt" "string"
     "Description of the image to generate" t)
    ("output" "string"
     "Output file path (e.g. /tmp/image.png)" t)
    ("model" "string"
     "Model to use. Options: black-forest-labs/flux.2-pro (default), black-forest-labs/flux.2-max, black-forest-labs/flux.2-flex, black-forest-labs/flux.2-klein-4b, sourceful/riverflow-v2-pro, sourceful/riverflow-v2-fast, sourceful/riverflow-v2-fast-preview, sourceful/riverflow-v2-standard-preview, sourceful/riverflow-v2-max-preview, bytedance-seed/seedream-4.5"
     nil))
   (let ((result (generate-image
                  :prompt prompt
                  :output output
                  :model  (or model *imagegen-default-model*))))
     (format nil "Image generated: ~a" (namestring result)))))
