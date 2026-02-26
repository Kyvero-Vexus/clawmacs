;;;; src/http-server.lisp — HTTP API Server (Task 3.2)
;;;;
;;;; A lightweight REST API over the agent loop using Hunchentoot.
;;;;
;;;; Endpoints:
;;;;   POST /chat         — send message, get response (synchronous JSON)
;;;;   POST /chat/stream  — streaming response via SSE
;;;;   GET  /agents       — list registered agents
;;;;   GET  /sessions     — list active sessions
;;;;
;;;; Wire-up: the channel protocol is used internally for the streaming path.
;;;; The synchronous /chat path calls RUN-AGENT directly.

(in-package #:clambda/http-server)

;;; ── Globals ──────────────────────────────────────────────────────────────────

(defvar *default-port* 7474
  "Default port for the Clambda HTTP API server.")

(defvar *server* nil
  "The running HUNCHENTOOT:EASY-ACCEPTOR instance, or NIL.")

(defvar *http-sessions* (make-hash-table :test 'equal)
  "Active sessions keyed by session-id string.")

(defvar *sessions-lock* (bt:make-lock "http-sessions-lock")
  "Protects *HTTP-SESSIONS* for concurrent access.")

;;; ── Session helpers ──────────────────────────────────────────────────────────

(defun http-session-get (session-id)
  "Return the SESSION for SESSION-ID, or NIL."
  (bt:with-lock-held (*sessions-lock*)
    (gethash session-id *http-sessions*)))

(defun http-session-create (session-id agent)
  "Create and register a new SESSION for SESSION-ID with AGENT.
Returns the new session."
  (let ((sess (clambda/session:make-session :id session-id :agent agent)))
    (bt:with-lock-held (*sessions-lock*)
      (setf (gethash session-id *http-sessions*) sess))
    sess))

(defun list-http-sessions ()
  "Return a list of all active SESSION objects."
  (bt:with-lock-held (*sessions-lock*)
    (let ((result '()))
      (maphash (lambda (k v) (declare (ignore k)) (push v result))
               *http-sessions*)
      (nreverse result))))

;;; ── JSON helpers ─────────────────────────────────────────────────────────────

(defun parse-json-body ()
  "Parse the request body as JSON, returning a hash-table or NIL."
  (let ((body (hunchentoot:raw-post-data :force-text t)))
    (when (and body (> (length body) 0))
      (handler-case (com.inuoe.jzon:parse body)
        (error (c)
          (declare (ignore c))
          nil)))))

(defun json-response (data &optional (status 200))
  "Set hunchentoot response to JSON content type and return DATA as JSON string."
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8"
        (hunchentoot:return-code*) status)
  (com.inuoe.jzon:stringify data))

(defun json-error (message &optional (status 400))
  "Return a JSON error response."
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "error" ht) message)
    (json-response ht status)))

(defun ht-get (ht key)
  "Get KEY from jzon-parsed hash-table HT."
  (gethash key ht))

;;; ── Agent resolution ─────────────────────────────────────────────────────────

(defun resolve-agent (agent-name)
  "Find an agent by name (string) in the registry, instantiate if needed.
Returns an AGENT object or NIL."
  (let ((entry (clambda/registry:find-agent agent-name)))
    (when entry
      (typecase entry
        (clambda/registry:agent-spec
         (clambda/registry:instantiate-agent-spec entry))
        (clambda/agent:agent
         entry)
        (t nil)))))

;;; ── Handlers ─────────────────────────────────────────────────────────────────

;;; POST /chat
;;; Body: {"message": "...", "session_id": "...", "agent": "...", "stream": false}
;;; Returns: {"response": "...", "session_id": "..."}

(defun handle-chat ()
  "Handle POST /chat — synchronous agent response."
  (let ((body (parse-json-body)))
    (unless body
      (return-from handle-chat (json-error "Invalid or missing JSON body")))

    (let* ((message    (ht-get body "message"))
           (session-id (or (ht-get body "session_id")
                           (format nil "http-~a" (get-universal-time))))
           (agent-name (ht-get body "agent"))
           ;; Get or create session
           (session    (or (http-session-get session-id)
                           (let ((agent (when agent-name
                                          (resolve-agent agent-name))))
                             (if agent
                                 (http-session-create session-id agent)
                                 (return-from handle-chat
                                   (json-error
                                    (format nil "Agent not found: ~a" agent-name)
                                    404)))))))

      (unless message
        (return-from handle-chat (json-error "Missing 'message' field")))

      ;; Run the agent loop
      (let ((response
             (handler-case
                 (clambda/loop:run-agent session message
                                         :options (clambda/loop:make-loop-options
                                                   :max-turns 10))
               (error (c)
                 (return-from handle-chat
                   (json-error (format nil "Agent error: ~a" c) 500))))))

        ;; Build response
        (let ((out (make-hash-table :test 'equal)))
          (setf (gethash "response"   out) (or response "")
                (gethash "session_id" out) session-id)
          (json-response out))))))

;;; POST /chat/stream
;;; Body: {"message": "...", "session_id": "...", "agent": "..."}
;;; Returns: text/event-stream (SSE)

(defun handle-chat-stream ()
  "Handle POST /chat/stream — streaming SSE response."
  (let ((body (parse-json-body)))
    (unless body
      (return-from handle-chat-stream (json-error "Invalid JSON body")))

    (let* ((message    (ht-get body "message"))
           (session-id (or (ht-get body "session_id")
                           (format nil "http-stream-~a" (get-universal-time))))
           (agent-name (ht-get body "agent"))
           (session    (or (http-session-get session-id)
                           (let ((agent (when agent-name
                                          (resolve-agent agent-name))))
                             (if agent
                                 (http-session-create session-id agent)
                                 (return-from handle-chat-stream
                                   (json-error
                                    (format nil "Agent not found: ~a" agent-name)
                                    404)))))))

      (unless message
        (return-from handle-chat-stream (json-error "Missing 'message' field")))

      ;; Set SSE headers
      (setf (hunchentoot:content-type*) "text/event-stream; charset=utf-8")
      (setf (hunchentoot:header-out "Cache-Control") "no-cache")
      (setf (hunchentoot:header-out "Connection") "keep-alive")
      (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")

      ;; Stream via the agent loop with *on-stream-delta* hook
      (let ((out-stream (hunchentoot:send-headers)))
        (let ((clambda/loop:*on-stream-delta*
               (lambda (delta)
                 ;; SSE format: "data: <text>\n\n"
                 (let ((safe-delta (cl-ppcre:regex-replace-all "\\n" delta "\\\\n")))
                   (format out-stream "data: ~a~%~%" safe-delta)
                   (finish-output out-stream)))))
          (handler-case
              (clambda/loop:run-agent session message
                                      :options (clambda/loop:make-loop-options
                                                :max-turns 10
                                                :stream t))
            (error (c)
              (format out-stream "data: [ERROR] ~a~%~%" c)
              (finish-output out-stream))))
        ;; Signal end of stream
        (format out-stream "data: [DONE]~%~%")
        (finish-output out-stream))
      ;; Return empty string (headers already sent)
      "")))

;;; GET /agents
;;; Returns: {"agents": [{"name": "...", "role": "...", "model": "..."}, ...]}

(defun handle-list-agents ()
  "Handle GET /agents — list all registered agent specs."
  (let* ((specs (clambda/registry:list-agents))
         (out-list
          (mapcar (lambda (spec)
                    (let ((ht (make-hash-table :test 'equal)))
                      (etypecase spec
                        (clambda/registry:agent-spec
                         (setf (gethash "name"  ht)
                               (clambda/registry:agent-spec-name spec)
                               (gethash "role"  ht)
                               (clambda/registry:agent-spec-role spec)
                               (gethash "model" ht)
                               (or (clambda/registry:agent-spec-model spec) "")))
                        (clambda/agent:agent
                         (setf (gethash "name"  ht)
                               (clambda/agent:agent-name spec)
                               (gethash "role"  ht)
                               (clambda/agent:agent-role spec)
                               (gethash "model" ht)
                               (or (clambda/agent:agent-model spec) ""))))
                      ht))
                  specs))
         (result (make-hash-table :test 'equal)))
    (setf (gethash "agents" result) (coerce out-list 'vector))
    (json-response result)))

;;; GET /sessions
;;; Returns: {"sessions": [{"id": "...", "message_count": N}, ...]}

(defun handle-list-sessions ()
  "Handle GET /sessions — list all active HTTP sessions."
  (let* ((sessions (list-http-sessions))
         (out-list
          (mapcar (lambda (sess)
                    (let ((ht (make-hash-table :test 'equal)))
                      (setf (gethash "id" ht)
                            (clambda/session:session-id sess)
                            (gethash "message_count" ht)
                            (length (clambda/session:session-messages sess)))
                      ht))
                  sessions))
         (result (make-hash-table :test 'equal)))
    (setf (gethash "sessions" result) (coerce out-list 'vector))
    (json-response result)))

;;; ── Dispatch table ───────────────────────────────────────────────────────────

(defun make-dispatch-table ()
  "Build the Hunchentoot dispatch table for the Clambda API."
  (list
   ;; POST /chat
   (hunchentoot:create-prefix-dispatcher "/chat/stream" #'handle-chat-stream)
   (hunchentoot:create-prefix-dispatcher "/chat"        #'handle-chat)
   ;; GET /agents
   (hunchentoot:create-prefix-dispatcher "/agents"      #'handle-list-agents)
   ;; GET /sessions
   (hunchentoot:create-prefix-dispatcher "/sessions"    #'handle-list-sessions)
   ;; Fallback
   (hunchentoot:create-prefix-dispatcher "/"
     (lambda ()
       (json-response
        (let ((ht (make-hash-table :test 'equal)))
          (setf (gethash "name"    ht) "clambda-core API"
                (gethash "version" ht) "0.2.0"
                (gethash "paths"   ht) (vector "/chat" "/chat/stream"
                                               "/agents" "/sessions"))
          ht))))))

;;; ── Server lifecycle ─────────────────────────────────────────────────────────

(defun start-server (&key (port *default-port*) (address "127.0.0.1"))
  "Start the Clambda HTTP API server on PORT (default: *DEFAULT-PORT*).
Sets *SERVER* to the running acceptor.
Returns the acceptor."
  (when (and *server* (hunchentoot:started-p *server*))
    (warn "Server already running on port ~a. Stop it first." port)
    (return-from start-server *server*))
  (let ((acceptor (make-instance 'hunchentoot:easy-acceptor
                                 :port port
                                 :address address
                                 :access-log-destination nil
                                 :message-log-destination *error-output*)))
    ;; Install dispatch table
    (setf hunchentoot:*dispatch-table* (make-dispatch-table))
    (hunchentoot:start acceptor)
    (setf *server* acceptor)
    (format t "~&[clambda/http-server] Started on ~a:~a~%" address port)
    acceptor))

(defun stop-server ()
  "Stop the running Clambda HTTP API server. Sets *SERVER* to NIL."
  (when *server*
    (hunchentoot:stop *server*)
    (format t "~&[clambda/http-server] Stopped.~%")
    (setf *server* nil))
  nil)

(defun server-running-p ()
  "Return T if the HTTP server is currently running."
  (and *server* (hunchentoot:started-p *server*)))

(defun restart-server (&key (port *default-port*) (address "127.0.0.1"))
  "Stop and restart the HTTP server."
  (stop-server)
  (start-server :port port :address address))
