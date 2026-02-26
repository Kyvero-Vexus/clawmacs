;;;; src/state.lisp — Application state for cl-tui

(in-package #:cl-tui/state)

;;; ── App struct ───────────────────────────────────────────────────────────────

(defstruct (app (:constructor %make-app))
  "Top-level TUI application state."
  (client        nil)                ; cl-llm:client
  (messages      '() :type list)     ; conversation history (cl-llm messages)
  (model         nil :type (or null string))
  (system-prompt nil :type (or null string))
  (running-p     t   :type boolean)
  (stream        *standard-output*)) ; output stream for display

(defun make-app (&key client model system-prompt (stream *standard-output*))
  "Create the TUI app state."
  (%make-app :client        client
             :model         model
             :system-prompt system-prompt
             :stream        stream))

;;; Global app state (set at startup)
(defvar *app* nil)

;;; ── Mutators ─────────────────────────────────────────────────────────────────

(defun app-push-message (app message)
  "Append MESSAGE to app's conversation history."
  (setf (app-messages app)
        (append (app-messages app) (list message))))

(defun app-set-model (app model-name)
  "Change the active model."
  (setf (app-model app) model-name))

(defun app-set-system-prompt (app prompt)
  "Set (or clear) the system prompt. Nil clears it."
  (setf (app-system-prompt app) prompt))

(defun app-stop (app)
  "Signal that the app loop should exit."
  (setf (app-running-p app) nil))

;;; ── Chat message list ────────────────────────────────────────────────────────

(defun get-chat-messages (app)
  "Return the full message list, prepending system message if set."
  (let ((sys (app-system-prompt app)))
    (if sys
        (cons (system-message sys)
              (app-messages app))
        (app-messages app))))
