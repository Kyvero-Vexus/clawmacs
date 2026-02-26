;;;; src/packages.lisp — Package definitions for clambda-gui

;;; ── GUI package ──────────────────────────────────────────────────────────────
;;;
;;; We use CLIM-LISP (which shadows CL with CLIM-compatible versions of
;;; stream/io generics) plus CLIM itself.  All clambda-core and cl-llm
;;; symbols are imported explicitly to avoid conflicts.

(defpackage #:clambda-gui
  (:use #:clim-lisp #:clim)

  ;; clambda-core — agent / session / loop machinery
  (:import-from #:clambda
                ;; Agent
                #:agent #:make-agent
                #:agent-name #:agent-role #:agent-model
                #:agent-system-prompt #:agent-client #:agent-tool-registry
                ;; Session
                #:session #:make-session
                #:session-id #:session-agent #:session-messages
                #:session-add-message #:session-clear-messages
                #:session-message-count
                ;; Loop
                #:run-agent #:agent-turn
                #:*on-tool-call* #:*on-tool-result*
                #:*on-llm-response* #:*on-stream-delta*
                #:make-loop-options)

  ;; cl-llm — message inspection
  (:import-from #:cl-llm
                #:make-client
                #:message-role #:message-content
                #:message-tool-calls #:message-tool-call-id
                #:tool-call-function-name)

  (:export
   ;; Frame class (for introspection)
   #:clambda-gui-frame

   ;; Accessors
   #:frame-session
   #:frame-chat-log
   #:frame-status
   #:frame-streaming-buffer

   ;; Chat message record
   #:chat-message
   #:make-chat-message
   #:chat-message-role
   #:chat-message-content
   #:chat-message-timestamp

   ;; Helpers
   #:role-ink
   #:role-label
   #:format-timestamp
   #:role-from-message
   #:session-messages->chat-log

   ;; Main entry points
   #:run-gui
   #:launch-gui
   #:make-gui-session
   #:make-gui-frame))
