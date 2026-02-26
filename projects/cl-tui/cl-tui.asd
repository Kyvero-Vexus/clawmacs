;;;; cl-tui.asd — Terminal UI chat interface for cl-llm

(defsystem "cl-tui"
  :description "ANSI terminal chat interface for cl-llm"
  :version "0.1.0"
  :author "Gensym <gensym@cl-team>"
  :license "MIT"
  :depends-on ("cl-llm"
               "alexandria"
               "cl-ppcre")
  :serial t
  :components ((:file "src/packages")
               (:file "src/ansi")
               (:file "src/state")
               (:file "src/display")
               (:file "src/commands")
               (:file "src/loop")))
