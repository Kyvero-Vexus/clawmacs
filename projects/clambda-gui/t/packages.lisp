;;;; t/packages.lisp — Test package for clambda-gui

(defpackage #:clambda-gui/tests
  (:use #:clim-lisp)
  (:import-from #:clambda-gui
                #:make-chat-message
                #:chat-message-role
                #:chat-message-content
                #:chat-message-timestamp
                #:format-timestamp
                #:role-ink
                #:role-label))
