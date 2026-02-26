;;;; src/display.lisp — Rendering helpers for cl-tui

(in-package #:cl-tui/display)

;;; ── Output helpers ───────────────────────────────────────────────────────────

(defun emit (text &optional (stream *standard-output*))
  "Write TEXT to STREAM and flush."
  (write-string text stream)
  (force-output stream))

;;; ── Header ───────────────────────────────────────────────────────────────────

(defun print-header (model system-prompt &optional (stream *standard-output*))
  "Print the startup banner with model and system info."
  (emit +clear-screen+ stream)
  (emit +cursor-home+ stream)
  (let ((hdr-color (concatenate 'string +bold+ +fg-bright-cyan+)))
    (emit (colored hdr-color "╔══════════════════════════════════════════╗") stream)
    (terpri stream)
    (emit (colored hdr-color "║         cl-tui  ·  LLM Chat TUI         ║") stream)
    (terpri stream)
    (emit (colored hdr-color "╚══════════════════════════════════════════╝") stream)
    (terpri stream))
  (when model
    (emit (colored +fg-bright-yellow+ (format nil "  Model  : ~a" model)) stream)
    (terpri stream))
  (when system-prompt
    (let ((preview (if (> (length system-prompt) 57)
                       (concatenate 'string (subseq system-prompt 0 57) "...")
                       system-prompt)))
      (emit (colored (concatenate 'string +dim+ +fg-white+)
                     (format nil "  System : ~a" preview))
            stream)
      (terpri stream)))
  (emit (colored +fg-bright-black+
                 "  /quit  /model MODEL  /system PROMPT  /clear  /help")
        stream)
  (terpri stream)
  (print-separator stream)
  (force-output stream))

(defun print-separator (&optional (stream *standard-output*))
  "Print a visual divider line."
  (emit (colored +fg-bright-black+ "────────────────────────────────────────────────") stream)
  (terpri stream)
  (force-output stream))

;;; ── Message rendering ────────────────────────────────────────────────────────

(defun role-color+label (role)
  "Return (values color-string label-string) for a message ROLE."
  (cond
    ((string= role "system")
     (values (concatenate 'string +dim+ +fg-magenta+) "SYSTEM"))
    ((string= role "user")
     (values (concatenate 'string +bold+ +fg-bright-blue+) "YOU"))
    ((string= role "assistant")
     (values (concatenate 'string +bold+ +fg-bright-green+) "AI"))
    (t
     (values +fg-white+ (string-upcase role)))))

(defun print-message (message &optional (stream *standard-output*))
  "Print a single conversation message with role label and color."
  (let ((role    (cl-llm:message-role message))
        (content (cl-llm:message-content message)))
    (multiple-value-bind (color label)
        (role-color+label role)
      ;; Role tag
      (emit (colored color (format nil "[~a] " label)) stream)
      ;; Content — style per role
      (cond
        ((string= role "user")
         (emit (colored +fg-bright-white+ (or content "")) stream))
        ((string= role "system")
         (emit (colored (concatenate 'string +dim+ +fg-white+)
                        (or content ""))
               stream))
        (t
         (emit (or content "") stream)))
      (terpri stream)
      (force-output stream))))

;;; ── Streaming output ─────────────────────────────────────────────────────────

(defun print-assistant-start (&optional (stream *standard-output*))
  "Print the [AI] prefix before streaming tokens begin."
  (terpri stream)
  (emit (colored (concatenate 'string +bold+ +fg-bright-green+) "[AI] ") stream)
  (force-output stream))

(defun print-token (token &optional (stream *standard-output*))
  "Write a single streaming token; flush immediately so it appears as it arrives."
  (write-string token stream)
  (force-output stream))

(defun print-assistant-end (&optional (stream *standard-output*))
  "End the streaming response — print newline."
  (terpri stream)
  (force-output stream))

;;; ── Input prompt ─────────────────────────────────────────────────────────────

(defun print-prompt (&optional (stream *standard-output*))
  "Print the user input prompt, flushed, ready for input."
  (terpri stream)
  (emit (colored (concatenate 'string +bold+ +fg-yellow+) ">>> ") stream)
  (force-output stream))

;;; ── Notices ──────────────────────────────────────────────────────────────────

(defun print-system-notice (text &optional (stream *standard-output*))
  "Print a system/info notice in dim cyan."
  (emit (colored (concatenate 'string +dim+ +fg-cyan+)
                 (format nil "  * ~a" text))
        stream)
  (terpri stream)
  (force-output stream))

(defun print-error-notice (text &optional (stream *standard-output*))
  "Print an error notice in bold red."
  (emit (colored (concatenate 'string +bold+ +fg-red+)
                 (format nil "  ! ~a" text))
        stream)
  (terpri stream)
  (force-output stream))

;;; ── Screen control ───────────────────────────────────────────────────────────

(defun clear-screen (&optional (stream *standard-output*))
  "Clear the terminal screen."
  (emit +clear-screen+ stream)
  (emit +cursor-home+ stream)
  (force-output stream))
