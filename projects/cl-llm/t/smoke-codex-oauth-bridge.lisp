;;;; Smoke test: :codex-oauth uses Node OAuth helper runtime first.

(require 'asdf)
(asdf:load-system :cl-llm)

(defun fail (fmt &rest args)
  (format *error-output* "FAIL: ~?~%" fmt args)
  (uiop:quit 1))

(let* ((client (cl-llm:make-codex-oauth-client :model "gpt-5-codex"))
       (base (cl-llm:client-base-url client)))
  (when (search "api.openai.com" base :test #'char-equal)
    (fail "unexpected base-url ~A" base))
  (format t "OK base-url: ~A~%" base)

  (let* ((called nil)
         (orig-helper (symbol-function 'cl-llm/codex-oauth-bridge::%run-node-helper))
         (orig-claude (symbol-function 'cl-llm/claude-cli:claude-cli-chat)))
    (unwind-protect
         (progn
           (setf (symbol-function 'cl-llm/codex-oauth-bridge::%run-node-helper)
                 (lambda (&rest _)
                   (declare (ignore _))
                   (setf called :helper)
                   (let ((ht (make-hash-table :test 'equal)))
                     (setf (gethash "ok" ht) t
                           (gethash "text" ht) "bridge ok"
                           (gethash "model" ht) "gpt-5-codex")
                     ht)))
           (setf (symbol-function 'cl-llm/claude-cli:claude-cli-chat)
                 (lambda (&rest _)
                   (declare (ignore _))
                   (setf called :claude)
                   (cl-llm/protocol::make-completion-response
                    :id "smoke-claude"
                    :model "claude-opus-4-6"
                    :choices (list (cl-llm/protocol::make-choice
                                    :message (cl-llm:assistant-message "fallback")
                                    :finish-reason "stop"))
                    :usage nil)))

           (let ((resp (cl-llm:chat client (list (cl-llm:user-message "hi")))))
             (declare (ignore resp))
             (unless (eq called :helper)
               (fail "bridge dispatch did not call helper first; called=~A" called))))
      (setf (symbol-function 'cl-llm/codex-oauth-bridge::%run-node-helper) orig-helper
            (symbol-function 'cl-llm/claude-cli:claude-cli-chat) orig-claude)))

  (format t "OK dispatch: :codex-oauth -> Node helper primary runtime~%"))

(format t "PASS smoke-codex-oauth-bridge~%")
(uiop:quit 0)
