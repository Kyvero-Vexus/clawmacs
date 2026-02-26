;;;; load-and-test.lisp — Quick loader for development/testing

;; Add this project to ASDF's source registry
(pushnew (truename #p"./") asdf:*central-registry* :test #'equal)

;; Load the system
(ql:quickload "cl-llm" :silent nil)

;; Load tests (without parachute dependency)
(load "t/packages.lisp")
(load "t/test-basic.lisp")

;; Run
(cl-llm/tests:run-tests :live t)
