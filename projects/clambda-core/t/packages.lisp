;;;; t/packages.lisp — Test packages for clambda-core

(defpackage #:clambda-core/tests
  (:use #:cl #:clambda)
  (:export #:run-smoke-test))

(defpackage #:clambda-core/tests/telegram
  (:use #:cl #:parachute)
  ;; Import public API symbols
  (:import-from #:clambda/telegram
                #:telegram-channel
                #:make-telegram-channel
                #:telegram-channel-token
                #:telegram-channel-allowed-users
                #:telegram-channel-polling-interval
                #:telegram-channel-running
                #:telegram-channel-last-update-id
                #:telegram-api-url
                #:allowed-user-p)
  ;; Internal helpers accessed via :: for white-box testing
  ;; (clambda/telegram::%extract-message-fields ...)
  ;; (clambda/telegram::%plist->ht ...)
  )
