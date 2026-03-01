;;;; src/system-prompt.lisp — Dynamic system prompt builder for Clawmacs agents
;;;;
;;;; Builds a comprehensive, structured system prompt similar to OpenClaw's
;;;; agent boot sequence. Called when creating a new session/agent.
;;;;
;;;; Sections (in order):
;;;;   1. Tooling — list of available tools with descriptions
;;;;   2. Safety  — short guardrail reminder
;;;;   3. Skills  — note about skills/knowledge
;;;;   4. Workspace — working directory path
;;;;   5. Documentation — path to Clawmacs docs
;;;;   6. Workspace Files (injected) — AGENTS.md, SOUL.md, etc.
;;;;   7. Current Date & Time
;;;;   8. Runtime — agent name, host, OS, model, workspace, shell

(in-package #:clawmacs/system-prompt)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 1. Workspace file injection
;;;; ─────────────────────────────────────────────────────────────────────────────

(defparameter *workspace-inject-files*
  '("AGENTS.md" "SOUL.md" "TOOLS.md" "IDENTITY.md" "USER.md" "HEARTBEAT.md" "MEMORY.md")
  "Files to inject from the agent's workspace directory into the system prompt.")

(defparameter *max-chars-per-file* 20000
  "Maximum characters to include per workspace file.")

(defparameter *max-chars-total* 150000
  "Maximum total characters for all injected workspace files.")

(defun %read-file-safe (path max-chars)
  "Read a file safely, returning string or NIL on error.
Truncates to MAX-CHARS if the file is large."
  (handler-case
      (let ((content (uiop:read-file-string path)))
        (if (> (length content) max-chars)
            (concatenate 'string
                         (subseq content 0 max-chars)
                         (format nil "~%...[truncated at ~a chars]" max-chars))
            content))
    (error () nil)))

(defun inject-workspace-files (workspace-path &key
                                                (files *workspace-inject-files*)
                                                (max-per-file *max-chars-per-file*)
                                                (max-total *max-chars-total*))
  "Return a string section injecting workspace files from WORKSPACE-PATH.
FILES — list of filenames to try (missing files are silently skipped).
Returns a string with ## /path/to/FILE headers and content."
  (when (null workspace-path)
    (return-from inject-workspace-files ""))
  (let ((dir (uiop:ensure-directory-pathname workspace-path))
        (total 0)
        (parts '()))
    (dolist (fname files)
      (when (< total max-total)
        (let* ((path (merge-pathnames fname dir))
               (remaining (- max-total total))
               (limit (min max-per-file remaining))
               (content (and (probe-file path)
                             (%read-file-safe path limit))))
          (when content
            (let ((section (format nil "## ~a~%~%~a~%~%" path content)))
              (push section parts)
              (incf total (length content)))))))
    (if parts
        (with-output-to-string (s)
          (write-string "# Workspace Files (injected)" s)
          (write-char #\Newline s)
          (write-char #\Newline s)
          (dolist (part (nreverse parts))
            (write-string part s)))
        "")))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 2. Tool listing
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun format-tool-listing (tool-registry)
  "Return a string listing all tools in TOOL-REGISTRY with their descriptions.
Uses clawmacs/tools:tool-definitions-for-llm to enumerate tools."
  (if (null tool-registry)
      "No tools available."
      (handler-case
          (let ((tools (clawmacs/tools:tool-definitions-for-llm tool-registry)))
            (if (null tools)
                "No tools available."
                (with-output-to-string (s)
                  (dolist (tool tools)
                    (let* ((name (cl-llm/protocol:tool-definition-name tool))
                           (desc (cl-llm/protocol:tool-definition-description tool)))
                      (format s "- **~a**: ~a~%" name (or desc "(no description)")))))))
        (error () "Tool listing unavailable."))))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 3. Runtime info
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun %get-hostname ()
  "Return hostname string."
  (handler-case
      (string-trim '(#\Newline #\Return #\Space)
                   (with-output-to-string (s)
                     (uiop:run-program '("hostname") :output s :ignore-error-status t)))
    (error () "unknown")))

(defun %get-os-info ()
  "Return a one-line OS description."
  (handler-case
      (string-trim '(#\Newline #\Return #\Space)
                   (with-output-to-string (s)
                     (uiop:run-program
                      (list "/bin/bash" "-c" "uname -sr")
                      :output s :ignore-error-status t)))
    (error () "Linux")))

(defun %current-datetime-string ()
  "Return current date/time in a readable format using universal time."
  (multiple-value-bind (sec min hour day month year dow)
      (decode-universal-time (get-universal-time))
    (declare (ignore dow))
    (format nil "~4d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d UTC"
            year month day hour min sec)))

(defun %default-model ()
  "Return the current default model string."
  (handler-case
      (let* ((pkg (find-package '#:clawmacs/config))
             (sym (and pkg (find-symbol "*DEFAULT-MODEL*" pkg))))
        (if (and sym (boundp sym))
            (symbol-value sym)
            "unknown"))
    (error () "unknown")))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 4. Main builder
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-system-prompt (&key
                              agent-name
                              workspace-path
                              tool-registry
                              base-prompt
                              (inject-files *workspace-inject-files*))
  "Build a comprehensive system prompt for a Clawmacs agent.

AGENT-NAME    — name of the agent (string)
WORKSPACE-PATH — path to the agent's workspace directory
TOOL-REGISTRY  — the agent's tool registry (or NIL)
BASE-PROMPT    — optional base/personality prompt to prepend
INJECT-FILES   — list of workspace files to inject (default: *workspace-inject-files*)

Returns a string containing the full system prompt."
  (let ((agent-name  (or agent-name "clawmacs-agent"))
        (hostname    (%get-hostname))
        (os-info     (%get-os-info))
        (model       (%default-model))
        (workspace   (or workspace-path "~/.clawmacs/agents/"))
        (docs-path   (merge-pathnames "docs/"
                       (user-homedir-pathname)))
        (shell       "/bin/bash"))
    (with-output-to-string (s)
      ;; Optional base personality prompt
      (when (and base-prompt (not (string= base-prompt "")))
        (write-string base-prompt s)
        (format s "~%~%"))

      ;; § 1. Tooling
      (format s "## Tooling~%~%")
      (write-string (format-tool-listing tool-registry) s)
      (format s "~%")

      ;; § 2. Safety
      (format s "## Safety~%~%")
      (format s "You have no independent goals: do not pursue self-preservation, ~
replication, resource acquisition, or power-seeking; avoid long-term plans beyond ~
the user's request. Prioritize safety and human oversight over completion. ~
Comply with stop/pause/audit requests and never bypass safeguards.~%~%")

      ;; § 3. Skills
      (format s "## Skills~%~%")
      (format s "Your knowledge base and patterns are in your workspace under ~
`knowledge/` (patterns, mistakes, reference docs). Read `knowledge/mistakes/recent.md` ~
before starting any implementation. Record new patterns in `knowledge/patterns/` ~
and mistakes in `knowledge/mistakes/recent.md`.~%~%")

      ;; § 4. Workspace
      (format s "## Workspace~%~%")
      (format s "Your working directory is: ~a~%~%" workspace)

      ;; § 5. Documentation
      (format s "## Documentation~%~%")
      (format s "Clawmacs source and docs: ~a~%~%" docs-path)
      (format s "Key paths:~%")
      (format s "- Config: ~~/~a~%" ".clawmacs/init.lisp")
      (format s "- Source: ~~/~a~%" "workspace-gensym/projects/clambda-core/")
      (format s "- Logs: ~a~%" "/tmp/clawmacs-headless.log")
      (format s "- SWANK REPL: port 4006~%~%")

      ;; § 6. Workspace files (injected)
      (let ((injected (inject-workspace-files workspace-path
                                              :files inject-files)))
        (when (and injected (> (length injected) 0))
          (write-string injected s)
          (format s "~%")))

      ;; § 7. Current Date & Time
      (format s "## Current Date & Time~%~%")
      (format s "~a~%~%" (%current-datetime-string))

      ;; § 8. Runtime
      (format s "## Runtime~%~%")
      (format s "agent=~a | host=~a | os=~a | model=~a | workspace=~a | shell=~a~%"
              agent-name hostname os-info model workspace shell))))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 5. Convenience wrapper for Telegram
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-telegram-system-prompt (&key
                                       agent-name
                                       workspace-path
                                       tool-registry
                                       personality-prompt)
  "Build the full system prompt for a Telegram bot agent.
This is a thin wrapper around BUILD-SYSTEM-PROMPT with Telegram-specific defaults."
  (build-system-prompt
   :agent-name    (or agent-name "telegram-bot")
   :workspace-path workspace-path
   :tool-registry  tool-registry
   :base-prompt    personality-prompt))
