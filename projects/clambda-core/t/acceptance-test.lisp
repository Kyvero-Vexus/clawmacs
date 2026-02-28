(require :asdf)
(push #P"/home/slime/.openclaw/workspace-gensym/projects/clambda-core/" asdf:*central-registry*)
(push #P"/home/slime/.openclaw/workspace-gensym/projects/cl-llm/" asdf:*central-registry*)
(asdf:load-system :clawmacs-core)

(defvar *errors* nil)
(defvar *passes* 0)

(defmacro test-feature (name &body body)
  `(handler-case (progn ,@body (incf *passes*) (format t "PASS: ~a~%" ,name))
     (error (e) (push (format nil "~a: ~a" ,name e) *errors*)
                (format t "FAIL: ~a — ~a~%" ,name e))))

(let ((client (cl-llm:make-client
               :base-url "http://192.168.1.189:1234/v1"
               :api-key "lm-studio"
               :model "google/gemma-3-4b"))
      (registry (clawmacs:make-builtin-registry)))

  (test-feature "1. HTTP server start/stop"
    (clawmacs:start-server :port 19999 :api-token "test123")
    (assert (clawmacs:server-running-p))
    (clawmacs:stop-server))

  (test-feature "2. Agent creation"
    (clawmacs:make-agent :name "test" :model "google/gemma-3-4b"
                         :system-prompt "Test." :client client
                         :tool-registry registry))

  (test-feature "3. Session creation"
    (let ((agent (clawmacs:make-agent :name "test" :model "google/gemma-3-4b"
                                      :system-prompt "Test." :client client
                                      :tool-registry registry)))
      (clawmacs:make-session :agent agent)))

  (test-feature "4. run-agent with LLM (live)"
    (let* ((agent (clawmacs:make-agent :name "test" :model "google/gemma-3-4b"
                                        :system-prompt "Reply with just OK"
                                        :client client :tool-registry registry))
           (session (clawmacs:make-session :agent agent)))
      (let ((result (clawmacs:run-agent session "Say OK")))
        (assert (stringp result)))))

  (test-feature "5. Session save/load"
    (let* ((agent (clawmacs:make-agent :name "test" :model "google/gemma-3-4b"
                                        :system-prompt "Test" :client client
                                        :tool-registry registry))
           (session (clawmacs:make-session :agent agent)))
      (clawmacs:run-agent session "Hello")
      (clawmacs:save-session session "/tmp/test-sess.json")
      (let ((loaded (clawmacs:load-session agent "/tmp/test-sess.json")))
        (assert (> (clawmacs:session-message-count loaded) 0)))))

  (test-feature "6. SWANK start/stop"
    (clawmacs:start-swank :port 4007)
    (sleep 1)
    (clawmacs:stop-swank))

  (test-feature "7. Cron schedule-task :every"
    (clawmacs:schedule-task "test-every" :every 9999 :function (lambda () nil))
    (clawmacs:cancel-task "test-every"))

  (test-feature "8. Cron schedule-task :after"
    (clawmacs:schedule-task "test-after" :after 9999 :function (lambda () nil))
    (clawmacs:cancel-task "test-after"))

  (test-feature "9. Memory search"
    (clawmacs:memory-search "test query"))

  (test-feature "10. Config load"
    (clawmacs:load-user-config))

  (test-feature "11. define-agent macro"
    (eval '(clawmacs:define-agent test-defined-agent
             :model "google/gemma-3-4b"
             :system-prompt "Test agent"
             :display-name "TestBot"
             :emoji "T")))

  (test-feature "12. Agent identity"
    (let ((agent (clawmacs:make-agent :name "id-test" :model "test"
                                       :system-prompt "x" :client client
                                       :tool-registry registry
                                       :display-name "CEO" :emoji "Y"
                                       :theme "lisp")))
      (assert (string= (clawmacs:agent-display-name agent) "CEO"))
      (assert (string= (clawmacs:agent-emoji agent) "Y"))))

  (test-feature "13. Browser exports"
    (assert (fboundp 'clawmacs:browser-launch))
    (assert (fboundp 'clawmacs:browser-navigate))
    (assert (fboundp 'clawmacs:browser-snapshot))
    (assert (fboundp 'clawmacs:browser-close)))

  (test-feature "14. Cross-session messaging"
    (clawmacs:send-to-agent "nonexistent" "hello" :from "test"))

  (test-feature "15. Image save (check fboundp)"
    (assert (fboundp 'clawmacs:save-clawmacs-image)))

  (test-feature "16. Workspace injection config"
    (assert (boundp 'clawmacs:*workspace-inject-files*)))

  (test-feature "17. Context compaction config"
    (assert (boundp 'clawmacs:*default-context-window*))
    (assert (boundp 'clawmacs:*context-compaction-keep-last-messages*)))

  (test-feature "18. Fallback models config"
    (assert (boundp 'clawmacs:*fallback-models*)))

  (format t "~%=== RESULTS: ~a/18 passed ===~%" *passes*)
  (when *errors*
    (format t "~%FAILURES:~%")
    (dolist (e (reverse *errors*))
      (format t "  ~a~%" e)))
  (unless *errors*
    (format t "~%ALL TESTS PASSED!~%")))

(sb-ext:exit :code (if *errors* 1 0))
