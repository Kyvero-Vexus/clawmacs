;;;; example-init.lisp — Sample ~/.clambda/init.lisp for Clambda
;;;;
;;;; Copy this to ~/.clambda/init.lisp and customise.
;;;; This file is loaded automatically at startup by (clambda/config:load-user-config).
;;;; It runs in the CLAMBDA-USER package — all public Clambda symbols are
;;;; available without qualification. Full Common Lisp is available.
;;;;
;;;; Quick start:
;;;;   mkdir -p ~/.clambda
;;;;   cp example-init.lisp ~/.clambda/init.lisp
;;;;   $EDITOR ~/.clambda/init.lisp

(in-package #:clambda-user)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 1. Options — override defaults
;;;; ─────────────────────────────────────────────────────────────────────────────
;;;;
;;;; All options defined with defoption are settable here.
;;;; Run (clambda:describe-options) in the REPL to see all options.

;; Change the default model
(setf *default-model* "google/gemma-3-4b")

;; Use more turns for complex tasks
(setf *default-max-turns* 15)

;; Enable streaming by default
;; (setf *default-stream* t)

;; Logging verbosity
(setf *log-level* :info)

;; Print a greeting at startup
(setf *startup-message* "Clambda ready. λ")


;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 2. Define your own options with defoption
;;;; ─────────────────────────────────────────────────────────────────────────────
;;;;
;;;; Use defoption to declare configurable variables that other init.lisp
;;;; sections (or downstream code) can read.

(defoption *my-workspace-path* "~/projects/"
  :type string
  :doc "Default path for the coding agent's workspace.")

(defoption *my-preferred-editor* "emacs"
  :type string
  :doc "Editor to open when the assistant uses the edit tool.")

(defoption *my-timezone* "America/New_York"
  :type string
  :doc "Timezone hint passed to time-related tools.")


;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 3. Channel registration
;;;; ─────────────────────────────────────────────────────────────────────────────
;;;;
;;;; Register communication channels. The channel plugin for each type
;;;; must be loaded separately (or it just stores the config for later).

;; Telegram bot (uncomment and fill in your token)
;; (register-channel :telegram
;;   :token "YOUR_BOT_TOKEN_HERE"
;;   :allowed-users '(123456789)          ; Telegram user IDs
;;   :admin-users   '(123456789)          ; Users who can use admin commands
;;   :max-message-length 4096)

;; IRC
;; (register-channel :irc
;;   :server   "irc.libera.chat"
;;   :port     6697
;;   :tls      t
;;   :nick     "clambda-bot"
;;   :realname "Clambda AI"
;;   :channels '("#clambda" "#lisp"))

;; Local REPL channel (always available, no config needed)
;; (register-channel :repl)


;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 4. Custom tools
;;;; ─────────────────────────────────────────────────────────────────────────────
;;;;
;;;; Define tools that will be available to agents.
;;;; Tools are registered into *user-tool-registry* via define-user-tool.
;;;; Use (clambda/config:merge-user-tools! registry) when building an agent.

;;; A simple tool: get current time
(defun %get-current-time-handler (args)
  (declare (ignore args))
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time (get-universal-time))
    (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D"
            year month day hour min sec)))

(define-user-tool get-current-time
  :description "Returns the current date and time as a string."
  :parameters nil
  :function #'%get-current-time-handler)

;;; A tool that echoes back the input (useful for testing)
(define-user-tool echo
  :description "Echo the input message back to the caller."
  :parameters '((:name "message" :type "string" :description "The message to echo."))
  :function (lambda (args)
              (format nil "Echo: ~A" (gethash "message" args))))

;;; A tool with multiple parameters
(define-user-tool format-greeting
  :description "Format a personalised greeting."
  :parameters '((:name "name"     :type "string" :description "Person's name.")
                (:name "language" :type "string" :description "Language code: en, es, fr."
                                  :required nil))
  :function (lambda (args)
              (let ((name (gethash "name" args))
                    (lang (or (gethash "language" args) "en")))
                (cond
                  ((string= lang "es") (format nil "¡Hola, ~A!" name))
                  ((string= lang "fr") (format nil "Bonjour, ~A!" name))
                  (t                   (format nil "Hello, ~A!" name))))))


;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 5. Hooks
;;;; ─────────────────────────────────────────────────────────────────────────────
;;;;
;;;; Register hook functions to extend Clambda's behaviour.
;;;; Hooks run in insertion order. Errors are caught per-function.

;;; Log every tool call to standard output
(defun %log-tool-call (tool-name result)
  (format t "[hook] tool ~A → ~A chars~%"
          tool-name (length result)))

;; Uncomment to enable tool call logging hook:
;; (add-hook '*after-tool-call-hook* #'%log-tool-call)

;;; Print a separator before each agent turn
(defun %print-turn-separator (session user-message)
  (declare (ignore session user-message))
  (format t "~%────────────────────────────────────────~%"))

;; (add-hook '*before-agent-turn-hook* #'%print-turn-separator)

;;; After init: print a summary of what's configured
(defun %print-config-summary ()
  (format t "~%Config summary:~%")
  (format t "  model:      ~A~%" *default-model*)
  (format t "  max-turns:  ~A~%" *default-max-turns*)
  (format t "  log-level:  ~A~%" *log-level*)
  (format t "  user tools: ~A~%"
          (clambda/tools:list-tools *user-tool-registry*))
  (let ((channels clambda/config:*registered-channels*))
    (when channels
      (format t "  channels:   ~{~A~^, ~}~%"
              (mapcar #'car channels)))))

(add-hook '*after-init-hook* #'%print-config-summary)


;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 6. Agent definitions
;;;; ─────────────────────────────────────────────────────────────────────────────
;;;;
;;;; Pre-define agents with specific configs. Use find-agent to retrieve them.
;;;; Agents defined here are available to channel plugins at startup.

;; Example: define a coding assistant
;; (define-agent :coder
;;   :model "google/gemma-3-4b"
;;   :system-prompt "You are an expert Common Lisp programmer.
;; Use exec, read_file, and write_file tools to work with code.
;; Always explain what you're doing and why.")

;; Example: define a research assistant
;; (define-agent :researcher
;;   :model "deepseek-r1-distill-qwen-7b"
;;   :system-prompt "You are a research assistant. Fetch and summarise web content.
;; Be concise and cite your sources.")


;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 7. Lisp is the config
;;;; ─────────────────────────────────────────────────────────────────────────────
;;;;
;;;; You have full Common Lisp here. Load other files, conditionally configure
;;;; based on hostname, read secrets from files, etc.

;; Conditional config by hostname
;; (let ((host (machine-instance)))
;;   (cond
;;     ;; On my dev laptop: use local LM Studio
;;     ((string= host "my-laptop")
;;      (setf *default-model* "local/qwen2.5-7b"))
;;
;;     ;; On the server: use a remote model
;;     ((string= host "my-server")
;;      (setf *default-model* "google/gemma-3-12b"))
;;
;;     (t nil) ; use defaults
;;     ))

;; Load additional config files from ~/.clambda/
;; (let ((private (merge-pathnames "private.lisp" *clambda-home*)))
;;   (when (probe-file private)
;;     (load private)))
