;;;; t/packages.lisp — Test package

(defpackage #:cl-llm/tests
  (:use #:cl #:cl-llm)
  (:export #:run-tests))
