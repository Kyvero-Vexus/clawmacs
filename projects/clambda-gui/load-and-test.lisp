;;;; load-and-test.lisp — Attempt to load clambda-gui and run non-GUI tests

;; Clear ASDF cache so it picks up the new system
(asdf:clear-configuration)
(asdf:initialize-source-registry)

(format t "~%Loading clambda-gui...~%")

(handler-case
    (progn
      (ql:quickload "clambda-gui" :silent nil)
      (format t "~%clambda-gui loaded successfully.~%"))
  (error (e)
    (format t "~%LOAD ERROR: ~a~%" e)
    (uiop:quit 1)))

;; Run smoke tests (non-GUI)
(format t "~%Running non-GUI smoke tests...~%")
(handler-case
    (progn
      (asdf:test-system "clambda-gui")
      (format t "~%Tests complete.~%"))
  (error (e)
    (format t "~%TEST ERROR: ~a~%" e)))

;; Show what was loaded
(format t "~%Systems loaded successfully:~%")
(dolist (s '("cl-llm" "clambda-core" "clambda-gui"))
  (let ((sys (asdf:find-system s nil)))
    (if sys
        (format t "  ~a ~a~%" s (asdf:component-version sys))
        (format t "  ~a [not found]~%" s))))

(uiop:quit 0)
