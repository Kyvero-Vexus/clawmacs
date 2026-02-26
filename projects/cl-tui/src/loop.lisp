;;;; src/loop.lisp — Main chat loop for cl-tui

(in-package #:cl-tui/loop)

;;; ── Default config ───────────────────────────────────────────────────────────

(defparameter *default-base-url* "http://192.168.1.189:1234/v1")
(defparameter *default-api-key*  "not-needed")
(defparameter *default-model*    "google/gemma-3-4b")

;;; ── Chat round-trip ──────────────────────────────────────────────────────────

(defun do-chat (app user-input stream)
  "Send USER-INPUT to the LLM, stream the response, update conversation history."
  ;; Append user message to history
  (app-push-message app (user-message user-input))

  ;; Print the [AI] prefix then stream tokens inline
  (print-assistant-start stream)

  (let ((full-text
         (handler-case
             (chat-stream
              (app-client app)
              (get-chat-messages app)
              (lambda (token) (print-token token stream))
              :model (app-model app))
           (cl-llm:llm-error (e)
             (print-assistant-end stream)
             (print-error-notice (format nil "LLM error: ~a" e) stream)
             nil)
           (error (e)
             (print-assistant-end stream)
             (print-error-notice (format nil "Error: ~a" e) stream)
             nil))))

    (print-assistant-end stream)

    ;; Persist assistant response in history
    (when (and full-text (> (length full-text) 0))
      (app-push-message app (assistant-message full-text)))))

;;; ── Input reader ─────────────────────────────────────────────────────────────

(defun read-input ()
  "Read a line from *standard-input*. Returns NIL on EOF."
  (handler-case
      (read-line *standard-input* nil nil)
    (end-of-file () nil)))

;;; ── Main loop ────────────────────────────────────────────────────────────────

(defun chat-loop (app)
  "Run the main interactive chat loop until quit or EOF."
  (let ((stream (app-stream app)))
    (loop while (app-running-p app)
          do
          (print-prompt stream)
          (let ((input (read-input)))
            ;; EOF → clean exit
            (when (null input)
              (print-system-notice "EOF — exiting." stream)
              (app-stop app)
              (loop-finish))
            (let ((trimmed (string-trim " " input)))
              ;; Skip blank lines
              (unless (string= trimmed "")
                (cond
                  ;; Slash command
                  ((command-p trimmed)
                   (handle-command trimmed stream))
                  ;; Normal chat
                  (t
                   (do-chat app trimmed stream)))))))))

;;; ── Entry point ──────────────────────────────────────────────────────────────

(defun run-tui (&key (base-url *default-base-url*)
                     (api-key  *default-api-key*)
                     (model    *default-model*)
                     system-prompt
                     (stream   *standard-output*))
  "Start the TUI chat interface.

BASE-URL     — LM Studio / OpenAI-compatible endpoint root.
API-KEY      — API key (\"not-needed\" for local servers).
MODEL        — model name string.
SYSTEM-PROMPT — optional system prompt string.
STREAM       — output stream (default: *standard-output*)."
  (let* ((client (make-client :base-url base-url
                              :api-key  api-key
                              :model    model))
         (app    (make-app :client        client
                           :model         model
                           :system-prompt system-prompt
                           :stream        stream)))
    (setf *app* app)
    (print-header model system-prompt stream)
    (unwind-protect
         (chat-loop app)
      (setf *app* nil)
      (terpri stream)
      (force-output stream)))
  (values))

;;; Alias
(defun run (&rest args)
  "Alias for RUN-TUI."
  (apply #'run-tui args))
