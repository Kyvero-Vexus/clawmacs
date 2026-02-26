;;;; src/commands.lisp — Slash command handling for cl-tui

(in-package #:cl-tui/commands)

;;; ── Command detection ────────────────────────────────────────────────────────

(defun command-p (input)
  "Return T if INPUT looks like a slash command."
  (and (> (length input) 0)
       (char= (char input 0) #\/)))

;;; ── Parse & dispatch ─────────────────────────────────────────────────────────

(defun parse-command (input)
  "Return (cmd . rest-string) from a slash command string like '/model foo'."
  (let* ((trimmed (string-trim " " input))
         (space   (position #\Space trimmed)))
    (if space
        (cons (string-downcase (subseq trimmed 1 space))
              (string-trim " " (subseq trimmed (1+ space))))
        (cons (string-downcase (subseq trimmed 1))
              ""))))

(defun handle-command (input stream)
  "Dispatch INPUT as a slash command. Return T if app should continue, NIL to quit."
  (destructuring-bind (cmd . arg)
      (parse-command input)
    (cond

      ;; /quit — exit
      ((member cmd '("quit" "q" "exit" "bye") :test #'string=)
       (print-system-notice "Goodbye." stream)
       (app-stop *app*)
       nil)

      ;; /model MODEL
      ((string= cmd "model")
       (if (string= arg "")
           (print-system-notice
            (format nil "Current model: ~a" (cl-tui/state:app-model *app*))
            stream)
           (progn
             (app-set-model *app* arg)
             (print-system-notice (format nil "Model set to: ~a" arg) stream)))
       t)

      ;; /system PROMPT — set system prompt (empty arg clears it)
      ((string= cmd "system")
       (if (string= arg "")
           (progn
             (app-set-system-prompt *app* nil)
             (print-system-notice "System prompt cleared." stream))
           (progn
             (app-set-system-prompt *app* arg)
             (print-system-notice (format nil "System prompt set: ~a" arg) stream)))
       t)

      ;; /clear — clear screen and reprint header
      ((string= cmd "clear")
       (cl-tui/display:clear-screen stream)
       (cl-tui/display:print-header
        (cl-tui/state:app-model *app*)
        (cl-tui/state:app-system-prompt *app*)
        stream)
       t)

      ;; /help
      ((member cmd '("help" "h" "?") :test #'string=)
       (print-system-notice "Commands:" stream)
       (print-system-notice "  /quit           — exit the chat" stream)
       (print-system-notice "  /model MODEL    — switch model" stream)
       (print-system-notice "  /system PROMPT  — set system prompt (empty to clear)" stream)
       (print-system-notice "  /clear          — clear the screen" stream)
       (print-system-notice "  /help           — show this help" stream)
       t)

      ;; Unknown
      (t
       (print-error-notice (format nil "Unknown command: /~a  (try /help)" cmd) stream)
       t))))
