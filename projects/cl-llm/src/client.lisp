;;;; src/client.lisp — Main client and chat functions

(in-package #:cl-llm/client)

;;; ── Client struct ────────────────────────────────────────────────────────────

(defstruct (client (:constructor %make-client))
  "An LLM API client."
  (base-url        nil :type string)
  (api-key         "not-needed" :type string)
  (model           nil :type (or null string))
  (default-options nil))  ; instance of request-options or nil

(defun make-client (&key base-url api-key model default-options)
  "Create a new LLM client.

BASE-URL is the endpoint root, e.g. \"http://localhost:11434/v1\".
API-KEY defaults to \"not-needed\" (suitable for local models).
MODEL is the default model name.
DEFAULT-OPTIONS is an optional REQUEST-OPTIONS struct."
  (assert base-url () "BASE-URL is required")
  (%make-client
   :base-url        (string-right-trim "/" base-url)
   :api-key         (or api-key "not-needed")
   :model           model
   :default-options default-options))

;;; Predefined providers
(defun make-ollama-client (&key (host "http://localhost:11434") model)
  (make-client :base-url (format nil "~a/v1" host)
               :api-key "ollama-local"
               :model model))

(defun make-openrouter-client (api-key &key model)
  (make-client :base-url "https://openrouter.ai/api/v1"
               :api-key api-key
               :model model))

(defun make-lm-studio-client (&key (host "http://localhost:1234") model)
  (make-client :base-url (format nil "~a/v1" host)
               :api-key "lm-studio"
               :model model))

;;; ── Helpers ──────────────────────────────────────────────────────────────────

(defun chat-url (client)
  (format nil "~a/chat/completions" (client-base-url client)))

(defun effective-options (client options)
  "Merge client defaults with per-request options."
  ;; Per-request wins; client default fills in.
  ;; Simple approach: prefer options when provided, else client defaults.
  (or options (client-default-options client)))

;;; ── Main chat function ────────────────────────────────────────────────────────

(defun chat (client messages
             &key model options tools)
  "Send a chat completion request.

CLIENT — a CLIENT struct.
MESSAGES — list of MESSAGE structs (use SYSTEM-MESSAGE, USER-MESSAGE, etc.).
MODEL — override client's default model.
OPTIONS — a REQUEST-OPTIONS struct (optional).
TOOLS — list of TOOL-DEFINITION structs (optional).

Returns a COMPLETION-RESPONSE."
  (let* ((effective-model (or model (client-model client)))
         (effective-opts  (effective-options client options))
         (request-ht      (cl-llm/protocol::build-request-ht
                           effective-model messages effective-opts tools))
         (body-str        (com.inuoe.jzon:stringify request-ht))
         (response-str    (cl-llm/http:post-json
                           (chat-url client)
                           (client-api-key client)
                           body-str)))
    (cl-llm/protocol::parse-response response-str)))

;;; ── Streaming chat ───────────────────────────────────────────────────────────

(defun chat-stream (client messages callback
                    &key model options tools)
  "Send a streaming chat completion request.

CALLBACK is called with each TEXT-DELTA string as it arrives.
Returns the full accumulated text string when done."
  (let* ((effective-model (or model (client-model client)))
         (effective-opts  (effective-options client options))
         (request-ht      (cl-llm/protocol::build-request-ht
                           effective-model messages effective-opts tools))
         ;; Add stream:true
         (_ (setf (gethash "stream" request-ht) t))
         (body-str        (com.inuoe.jzon:stringify request-ht))
         (accumulated     (make-string-output-stream)))
    (declare (ignore _))
    (cl-llm/http:post-json-stream
     (chat-url client)
     (client-api-key client)
     body-str
     (lambda (line)
       (cl-llm/streaming:parse-sse-line
        line
        (lambda (delta)
          (when delta
            (write-string delta accumulated)
            (when callback
              (funcall callback delta)))))))
    (get-output-stream-string accumulated)))

;;; ── Convenience ──────────────────────────────────────────────────────────────

(defun simple-chat (client prompt &key model system)
  "Simplest possible chat: send PROMPT, get back the response string.
Optionally provide a SYSTEM message and MODEL override."
  (let ((messages (if system
                      (list (cl-llm/protocol:system-message system)
                            (cl-llm/protocol:user-message prompt))
                      (list (cl-llm/protocol:user-message prompt)))))
    (let* ((response (chat client messages :model model))
           (choice   (first (cl-llm/protocol::response-choices response)))
           (msg      (when choice (cl-llm/protocol::choice-message choice))))
      (when msg
        (cl-llm/protocol:message-content msg)))))

(defmacro with-client ((var &rest make-client-args) &body body)
  "Bind VAR to a new client for the duration of BODY."
  `(let ((,var (make-client ,@make-client-args)))
     ,@body))
