;;;; test-layer5p2-live.lisp — Live integration tests for Layer 5 Phase 2

(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(asdf:clear-source-registry)
(asdf:initialize-source-registry)
(ql:quickload "clambda-core" :silent t)

(defvar *base-url* "http://192.168.1.189:1234/v1")
(defvar *api-key* "not-needed")
(defvar *model* "google/gemma-3-4b")

(defun make-test-client ()
  (cl-llm:make-client
   :base-url *base-url*
   :api-key  *api-key*
   :model    *model*))

;;; ── Test 1: Registry + instantiate ──────────────────────────────────────────
(format t "~%=== Test 1: Registry + instantiate-agent-spec ===~%")

(clambda:define-agent :test-bot
  :model *model*
  :system-prompt "You are a terse test bot. Respond in at most one sentence."
  :role "test")

(let* ((spec   (clambda:find-agent :test-bot))
       (client (make-test-client))
       (agent  (clambda:instantiate-agent-spec spec)))
  ;; Wire the client in
  (setf (clambda:agent-client agent) client)
  (format t "Instantiated: ~a~%" agent)

  ;; Create a session and run one turn
  (let* ((sess (clambda:make-session :id "test-registry-session" :agent agent))
         (resp (clambda:run-agent sess "Say the word 'hello' and nothing else."
                                  :options (clambda:make-loop-options :max-turns 3))))
    (format t "Registry+turn response: ~s~%" resp)
    (assert (and resp (> (length resp) 0)) ()
            "Expected non-empty response, got ~s" resp)))

(format t "Test 1 PASSED~%")

;;; ── Test 2: Subagent spawning ────────────────────────────────────────────────
(format t "~%=== Test 2: Sub-agent spawning ===~%")

(let* ((client (make-test-client))
       (spec   (clambda:find-agent :test-bot))
       (agent  (clambda:instantiate-agent-spec spec)))
  (setf (clambda:agent-client agent) client)

  (let ((handle (clambda:spawn-subagent
                 agent
                 "Reply with exactly 'pong' and nothing else.")))

    (format t "Subagent spawned, status: ~a~%" (clambda:subagent-status handle))

    (multiple-value-bind (result status)
        (clambda:subagent-wait handle :timeout 60)
      (format t "Subagent finished. Status: ~a, Result: ~s~%"
              status result)
      (assert (eq status :done) ()
              "Expected :done status, got ~s" status)
      (assert (and result (> (length result) 0)) ()
              "Expected non-empty result"))))

(format t "Test 2 PASSED~%")

;;; ── Test 3: HTTP Server ──────────────────────────────────────────────────────
(format t "~%=== Test 3: HTTP Server ===~%")

;; Register an agent in the registry with a client (for HTTP use)
(let* ((client (make-test-client))
       (spec   (clambda:find-agent :test-bot))
       (agent  (clambda:instantiate-agent-spec spec)))
  (setf (clambda:agent-client agent) client)
  ;; Register the live agent (not spec) under a different name
  (clambda:register-agent "live-bot" agent))

;; Start the server
(clambda:start-server :port 7474)
(assert (clambda:server-running-p) () "Server should be running")
(format t "HTTP server started~%")

(sleep 0.5)

;; Test GET /agents
(let* ((resp (dex:get "http://127.0.0.1:7474/agents"))
       (data (com.inuoe.jzon:parse resp)))
  (format t "/agents response: ~a~%" resp)
  (assert (gethash "agents" data) () "Expected 'agents' key in response"))

(format t "GET /agents: PASSED~%")

;; Test GET /sessions (initially empty)
(let* ((resp (dex:get "http://127.0.0.1:7474/sessions"))
       (data (com.inuoe.jzon:parse resp)))
  (format t "/sessions response: ~a~%" resp)
  (assert (gethash "sessions" data) () "Expected 'sessions' key"))

(format t "GET /sessions: PASSED~%")

;; Test POST /chat
(let* ((body (com.inuoe.jzon:stringify
              (let ((ht (make-hash-table :test 'equal)))
                (setf (gethash "message" ht) "Say 'ok' and nothing else."
                      (gethash "agent"   ht) "live-bot"
                      (gethash "session_id" ht) "http-test-1")
                ht)))
       (resp (dex:post "http://127.0.0.1:7474/chat"
                       :content body
                       :headers '(("Content-Type" . "application/json"))))
       (data (com.inuoe.jzon:parse resp)))
  (format t "/chat response: ~a~%" resp)
  (let ((response-text (gethash "response" data)))
    (assert (and response-text (> (length response-text) 0)) ()
            "Expected non-empty 'response' in ~s" resp)))

(format t "POST /chat: PASSED~%")

;; Stop the server
(clambda:stop-server)
(assert (not (clambda:server-running-p)) () "Server should be stopped")

(format t "~%=== ALL LIVE TESTS PASSED ===~%")
(quit)
