;;;; src/claude-cli.lisp — Claude CLI backend for cl-llm
;;;;
;;;; Calls the `claude` CLI (from claude.ai) instead of the HTTP API.
;;;; This is the ONLY reliable way to use Anthropic OAuth credentials.
;;;;
;;;; CRITICAL: Always unset ANTHROPIC_API_KEY when invoking the CLI,
;;;; otherwise it overrides the OAuth session and fails.
;;;;
;;;; Usage:
;;;;   (cl-llm/claude-cli:claude-cli-chat messages :model "claude-opus-4-6")
;;;;   => a COMPLETION-RESPONSE struct
;;;;
;;;; CLI invocation:
;;;;   env -u ANTHROPIC_API_KEY claude --print --model MODEL \
;;;;       --output-format json -p PROMPT [--system-prompt SYSPROMPT]
;;;;
;;;; Output JSON: {"type":"result","result":"TEXT","usage":{...},...}

(in-package #:cl-llm/claude-cli)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 1. Configuration
;;;; ─────────────────────────────────────────────────────────────────────────────

(defvar *claude-cli-path* "/home/slime/.local/bin/claude"
  "Path to the claude CLI binary.")

(defvar *claude-cli-default-model* "claude-opus-4-6"
  "Default model to use with the claude CLI.")

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 2. Message Conversion
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun %messages->system-prompt (messages)
  "Extract and return the system message content from MESSAGES, or NIL."
  (let ((sys (find :system messages :key #'cl-llm/protocol:message-role)))
    (when sys
      (cl-llm/protocol:message-content sys))))

(defun %messages->prompt (messages)
  "Convert non-system MESSAGES to a conversation string for the claude CLI.

For a single user message, returns just the content.
For multi-turn conversations, formats as:
  Human: ...
  Assistant: ...
  Human: ..."
  (let ((non-system (remove :system messages
                            :key #'cl-llm/protocol:message-role)))
    (if (= (length non-system) 1)
        ;; Single message — just return content directly
        (or (cl-llm/protocol:message-content (first non-system)) "")
        ;; Multi-turn — format with role labels
        (with-output-to-string (s)
          (dolist (msg non-system)
            (let* ((role    (cl-llm/protocol:message-role msg))
                   (content (or (cl-llm/protocol:message-content msg) ""))
                   (label   (ecase role
                              (:user      "Human")
                              (:assistant "Assistant")
                              (:tool      "Tool"))))
              (format s "~A: ~A~%~%" label content)))))))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 3. CLI Invocation
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun %build-cli-args (prompt &key model system-prompt)
  "Build the argument list for invoking the claude CLI.

Prepends `env -u ANTHROPIC_API_KEY` to ensure OAuth session is used."
  (let ((base-args (list "env" "-u" "ANTHROPIC_API_KEY"
                         *claude-cli-path*
                         "--print"
                         "--model" (or model *claude-cli-default-model*)
                         "--output-format" "json"
                         "-p" prompt)))
    (if (and system-prompt (not (string= system-prompt "")))
        (append base-args (list "--system-prompt" system-prompt))
        base-args)))

(defun %run-cli (args)
  "Run the claude CLI with ARGS (a list of strings).
Returns (values output-string exit-code error-string)."
  (multiple-value-bind (output error-output exit-code)
      (uiop:run-program args
                        :output      :string
                        :error-output :string
                        :ignore-error-status t)
    (values output exit-code error-output)))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 4. Response Parsing
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun %parse-cli-output (output exit-code error-output)
  "Parse the JSON output from claude CLI.
Returns the result text string.
Signals an error on failure."
  (when (and (not (zerop exit-code)) (string= output ""))
    (error "Claude CLI failed (exit ~A): ~A" exit-code error-output))
  ;; Output may contain multiple JSON objects (stream-json lines) or one blob.
  ;; With --output-format json, we get one JSON object.
  ;; Find the last line that parses as JSON with a "result" key.
  (let ((result-text nil))
    (dolist (line (cl-ppcre:split "\\n" output))
      (let ((trimmed (string-trim " " line)))
        (when (and (> (length trimmed) 0)
                   (char= (char trimmed 0) #\{))
          (handler-case
              (let* ((parsed (com.inuoe.jzon:parse trimmed))
                     (type   (gethash "type" parsed))
                     (result (gethash "result" parsed)))
                (when (and (equal type "result") result)
                  (setf result-text result)))
            (error () nil)))))
    (unless result-text
      ;; Fallback: maybe the entire output is plain text (no JSON wrapper)
      (if (and output (not (string= (string-trim " 
" output) "")))
          (setf result-text (string-trim " 
" output))
          (error "Claude CLI returned no result. Exit: ~A. Output: ~S. Error: ~S"
                 exit-code output error-output)))
    result-text))

(defun %text->completion-response (text model)
  "Wrap TEXT string in a COMPLETION-RESPONSE struct."
  (cl-llm/protocol::make-completion-response
   :id      (format nil "cli-~A" (get-universal-time))
   :model   (or model *claude-cli-default-model*)
   :choices (list (cl-llm/protocol::make-choice
                   :message       (cl-llm/protocol:assistant-message text)
                   :finish-reason "stop"))
   :usage   nil))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 5. Public API
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun claude-cli-chat (messages &key model system-prompt max-tokens)
  "Send MESSAGES to Claude via the claude CLI and return a COMPLETION-RESPONSE.

MESSAGES     — list of MESSAGE structs (system-message, user-message, etc.)
MODEL        — model string, e.g. \"claude-opus-4-6\" (default: *claude-cli-default-model*)
SYSTEM-PROMPT — override system prompt (otherwise extracted from MESSAGES)
MAX-TOKENS   — ignored (claude CLI picks its own limits), present for API compat.

CRITICAL: Unsets ANTHROPIC_API_KEY so OAuth session is used, not API key.

Returns a COMPLETION-RESPONSE struct."
  (declare (ignore max-tokens))
  (let* ((effective-system (or system-prompt
                               (%messages->system-prompt messages)))
         (prompt           (%messages->prompt messages))
         (effective-model  (or model *claude-cli-default-model*))
         (args             (%build-cli-args prompt
                                            :model         effective-model
                                            :system-prompt effective-system)))
    (format *error-output*
            "~&[claude-cli] Invoking claude CLI, model=~A, prompt-len=~A~%"
            effective-model (length prompt))
    (multiple-value-bind (output exit-code error-output)
        (%run-cli args)
      (let ((text (%parse-cli-output output exit-code error-output)))
        (%text->completion-response text effective-model)))))

(defun claude-cli-chat-stream (messages callback &key model system-prompt max-tokens)
  "Like CLAUDE-CLI-CHAT but calls CALLBACK with the full text when done.

Currently non-streaming (calls the CLI once, then invokes callback with result).
For streaming output, the full text is returned at once.

CALLBACK — function of one argument (text-delta string). Called once with
           the complete response text.

Returns the full response text string."
  (declare (ignore max-tokens))
  (let* ((response (claude-cli-chat messages
                                    :model         model
                                    :system-prompt system-prompt))
         (choice   (first (cl-llm/protocol:response-choices response)))
         (msg      (when choice (cl-llm/protocol:choice-message choice)))
         (text     (when msg (cl-llm/protocol:message-content msg))))
    (when (and callback text)
      (funcall callback text))
    (or text "")))
