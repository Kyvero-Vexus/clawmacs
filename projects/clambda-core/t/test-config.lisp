;;;; t/test-config.lisp — Tests for clambda/config (Layer 6a)
;;;;
;;;; All tests are unit/integration tests that do NOT require a running LLM.
;;;; Tests: defoption, hook system, register-channel, define-user-tool,
;;;; load-user-config (with temp files), and package structure.

(in-package #:clambda-core/tests)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; Helpers
;;;; ─────────────────────────────────────────────────────────────────────────────

(defmacro with-temp-init-file ((forms-list) &body body)
  "Write FORMS-LIST to a unique temp init.lisp, bind *clambda-home* to its dir,
reset *user-config-loaded*, execute BODY, then clean up the temp file.

FORMS-LIST is a list of forms (not evaluated) that are written to the file."
  (let ((dir-sym  (gensym "DIR"))
        (path-sym (gensym "PATH")))
    `(let* ((,dir-sym  (uiop:ensure-directory-pathname
                        (merge-pathnames
                         (format nil "clambda-test-~A/" (get-universal-time))
                         (uiop:temporary-directory))))
            (,path-sym (merge-pathnames "init.lisp" ,dir-sym))
            (clambda/config:*clambda-home* ,dir-sym)
            (clambda/config::*user-config-loaded* nil))
       (ensure-directories-exist ,path-sym)
       (with-open-file (s ,path-sym :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create)
         (dolist (form ',forms-list)
           (format s "~S~%" form)))
       (unwind-protect
            (progn ,@body)
         (ignore-errors (delete-file ,path-sym))
         (ignore-errors (uiop:delete-directory-tree ,dir-sym :validate t))))))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 1. defoption
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun test-defoption-defaults ()
  "Built-in options have correct default values."
  (format t "~%=== test-defoption-defaults ===~%")

  (assert (boundp 'clambda/config:*default-model*))
  (assert (stringp clambda/config:*default-model*))
  (format t "  PASS: *default-model* = ~S~%" clambda/config:*default-model*)

  (assert (boundp 'clambda/config:*default-max-turns*))
  (assert (integerp clambda/config:*default-max-turns*))
  (format t "  PASS: *default-max-turns* = ~A~%" clambda/config:*default-max-turns*)

  (assert (boundp 'clambda/config:*default-stream*))
  (format t "  PASS: *default-stream* = ~A~%" clambda/config:*default-stream*)

  (assert (boundp 'clambda/config:*log-level*))
  (assert (keywordp clambda/config:*log-level*))
  (format t "  PASS: *log-level* = ~A~%" clambda/config:*log-level*)

  t)

(defun test-defoption-registry ()
  "defoption registers options in *option-registry*."
  (format t "~%=== test-defoption-registry ===~%")

  (let ((registry clambda/config:*option-registry*))
    (assert (listp registry))
    (assert (> (length registry) 0))

    ;; Check *default-model* is there
    (let ((entry (assoc 'clambda/config:*default-model* registry)))
      (assert entry () "*default-model* not in option registry")
      (let ((plist (cdr entry)))
        (assert (getf plist :default))
        (assert (getf plist :doc))
        (format t "  PASS: *default-model* in registry~%")
        (format t "        :type ~A :doc ~S~%"
                (getf plist :type)
                (getf plist :doc)))))
  t)

(defun test-defoption-setf ()
  "defoption variables are setf-able."
  (format t "~%=== test-defoption-setf ===~%")

  (let ((original clambda/config:*default-model*))
    (unwind-protect
         (progn
           (setf clambda/config:*default-model* "test/my-model")
           (assert (string= clambda/config:*default-model* "test/my-model"))
           (format t "  PASS: setf *default-model* to ~S~%"
                   clambda/config:*default-model*))
      (setf clambda/config:*default-model* original)))
  t)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 2. Hook system
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun test-hooks-add-remove ()
  "add-hook appends, remove-hook removes; duplicates are ignored."
  (format t "~%=== test-hooks-add-remove ===~%")

  ;; Use a fresh binding so we don't pollute global state
  (let ((clambda/config:*after-init-hook* '()))
    (let ((fn1 (lambda () 'a))
          (fn2 (lambda () 'b)))

      ;; Add fn1
      (clambda/config:add-hook '*after-init-hook* fn1)
      (assert (= 1 (length clambda/config:*after-init-hook*)))
      (format t "  PASS: add-hook adds~%")

      ;; Duplicate add — ignored
      (clambda/config:add-hook '*after-init-hook* fn1)
      (assert (= 1 (length clambda/config:*after-init-hook*)))
      (format t "  PASS: add-hook deduplicates~%")

      ;; Add fn2
      (clambda/config:add-hook '*after-init-hook* fn2)
      (assert (= 2 (length clambda/config:*after-init-hook*)))
      (format t "  PASS: add-hook adds second fn~%")

      ;; Remove fn1
      (clambda/config:remove-hook '*after-init-hook* fn1)
      (assert (= 1 (length clambda/config:*after-init-hook*)))
      (format t "  PASS: remove-hook removes fn1~%")

      ;; Remove non-existent — no error
      (clambda/config:remove-hook '*after-init-hook* fn1)
      (assert (= 1 (length clambda/config:*after-init-hook*)))
      (format t "  PASS: remove-hook handles non-member~%")))
  t)

(defun test-hooks-run-order ()
  "run-hook calls all functions in insertion order."
  (format t "~%=== test-hooks-run-order ===~%")

  (let ((clambda/config:*after-init-hook* '())
        (log '()))

    (clambda/config:add-hook '*after-init-hook* (lambda () (push 1 log)))
    (clambda/config:add-hook '*after-init-hook* (lambda () (push 2 log)))
    (clambda/config:add-hook '*after-init-hook* (lambda () (push 3 log)))

    (clambda/config:run-hook '*after-init-hook*)

    ;; push reverses; the hooks ran 1,2,3 → log is (3 2 1)
    (assert (equal log '(3 2 1))
            () "Hook run order wrong: ~A" log)
    (format t "  PASS: hooks ran in insertion order (1,2,3)~%"))
  t)

(defun test-hooks-run-with-args ()
  "run-hook-with-args passes all args to each function."
  (format t "~%=== test-hooks-run-with-args ===~%")

  (let ((clambda/config:*channel-message-hook* '())
        (received-args '()))

    (clambda/config:add-hook '*channel-message-hook*
                             (lambda (ch msg)
                               (push (list ch msg) received-args)))

    (clambda/config:run-hook-with-args '*channel-message-hook* :telegram "hello")

    (assert (= 1 (length received-args)))
    (assert (equal (first received-args) '(:telegram "hello")))
    (format t "  PASS: run-hook-with-args passed (:telegram \"hello\")~%"))
  t)

(defun test-hooks-error-isolation ()
  "An error in one hook function does not prevent subsequent hooks from running."
  (format t "~%=== test-hooks-error-isolation ===~%")

  (let ((clambda/config:*after-init-hook* '())
        (second-ran nil))

    (clambda/config:add-hook '*after-init-hook*
                             (lambda () (error "intentional error")))
    (clambda/config:add-hook '*after-init-hook*
                             (lambda () (setf second-ran t)))

    ;; run-hook must not propagate errors
    (clambda/config:run-hook '*after-init-hook*)

    (assert second-ran () "Second hook did not run after first errored")
    (format t "  PASS: error in hook fn isolated; second fn ran~%"))
  t)

(defun test-standard-hook-variables ()
  "Standard hook variables are bound and initially empty lists."
  (format t "~%=== test-standard-hook-variables ===~%")

  (dolist (var '(clambda/config:*after-init-hook*
                 clambda/config:*before-agent-turn-hook*
                 clambda/config:*after-tool-call-hook*
                 clambda/config:*channel-message-hook*))
    (assert (boundp var) () "~A not bound" var)
    (format t "  PASS: ~A is bound~%" var))
  t)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 3. register-channel
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun test-register-channel-basic ()
  "register-channel stores config in *registered-channels*."
  (format t "~%=== test-register-channel-basic ===~%")

  (let ((clambda/config:*registered-channels* '()))

    (clambda/config:register-channel :test-ch
                                     :token "TKN"
                                     :allowed-users '(1001 1002))

    (let ((entry (assoc :test-ch clambda/config:*registered-channels*)))
      (assert entry () ":test-ch not registered")
      (let ((plist (cdr entry)))
        (assert (string= (getf plist :token) "TKN"))
        (assert (equal (getf plist :allowed-users) '(1001 1002)))
        (format t "  PASS: channel :test-ch registered~%")
        (format t "        :token ~S :allowed-users ~A~%"
                (getf plist :token) (getf plist :allowed-users)))))
  t)

(defun test-register-channel-overwrites ()
  "Registering the same channel keyword twice replaces the old entry."
  (format t "~%=== test-register-channel-overwrites ===~%")

  (let ((clambda/config:*registered-channels* '()))
    (clambda/config:register-channel :dup-ch :v "first")
    (clambda/config:register-channel :dup-ch :v "second")

    (let ((entries (remove-if-not (lambda (e) (eq (car e) :dup-ch))
                                  clambda/config:*registered-channels*)))
      (assert (= 1 (length entries)) () "Expected 1 entry, got ~A" (length entries))
      (assert (string= (getf (cdr (first entries)) :v) "second"))
      (format t "  PASS: duplicate register overwrites, entry has :v \"second\"~%")))
  t)

(defun test-register-channel-custom-method ()
  "Users can defmethod on register-channel to intercept registration."
  (format t "~%=== test-register-channel-custom-method ===~%")

  (let ((intercepted nil)
        (clambda/config:*registered-channels* '()))

    ;; Add a method for :test-plugin-unique (unique keyword to avoid cross-test pollution)
    (defmethod clambda/config:register-channel ((type (eql :test-plugin-unique))
                                                &rest args &key &allow-other-keys)
      (setf intercepted (list type args))
      (call-next-method))

    (clambda/config:register-channel :test-plugin-unique :setting 42)

    (assert intercepted () "Custom method was not called")
    (assert (eq (first intercepted) :test-plugin-unique))
    (format t "  PASS: custom register-channel method was called~%")
    (format t "        intercepted: ~A~%" intercepted)

    ;; Clean up: remove the method using SBCL MOP (ignore errors if cleanup fails)
    (ignore-errors
     (let ((method (find-method #'clambda/config:register-channel
                                '()
                                (list (sb-mop:intern-eql-specializer :test-plugin-unique))
                                nil)))
       (when method
         (remove-method #'clambda/config:register-channel method)))))
  t)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 4. User tool registration
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun test-register-user-tool ()
  "register-user-tool! registers a tool in a fresh *user-tool-registry*."
  (format t "~%=== test-register-user-tool ===~%")

  (let ((clambda/config:*user-tool-registry* (make-tool-registry)))

    ;; Register
    (clambda/config:register-user-tool!
     "greet-user"
     "Greet someone"
     '((:name "name" :type "string" :description "Name to greet"))
     (lambda (args)
       (format nil "Hello, ~A!" (gethash "name" args))))

    ;; Verify registered
    (let ((entry (clambda/tools:find-tool clambda/config:*user-tool-registry*
                                          "greet-user")))
      (assert entry () "greet-user not in *user-tool-registry*")
      (format t "  PASS: tool 'greet-user' registered~%")

      ;; Call the handler directly
      (let* ((args (make-hash-table :test #'equal)))
        (setf (gethash "name" args) "Lisp")
        (let ((result (funcall (clambda/tools::tool-entry-handler entry) args)))
          ;; Handler returns a string (or tool-result wrapping it)
          (let ((str (if (stringp result)
                         result
                         (clambda/tools:tool-result-value result))))
            (assert (string= str "Hello, Lisp!"))
            (format t "  PASS: tool output = ~S~%" str)))))
    t))

(defun test-register-user-tool-no-params ()
  "register-user-tool! with nil parameters works."
  (format t "~%=== test-register-user-tool-no-params ===~%")

  (let ((clambda/config:*user-tool-registry* (make-tool-registry)))
    (clambda/config:register-user-tool!
     "ping" "Returns pong" nil
     (lambda (args) (declare (ignore args)) "pong"))

    (assert (clambda/tools:find-tool clambda/config:*user-tool-registry* "ping"))
    (format t "  PASS: no-param tool registered~%"))
  t)

(defun test-define-user-tool-macro ()
  "define-user-tool macro produces the same result as register-user-tool!."
  (format t "~%=== test-define-user-tool-macro ===~%")

  (let ((clambda/config:*user-tool-registry* (make-tool-registry)))
    ;; Use the macro
    (clambda/config:define-user-tool shout-tool
      :description "Shouts the input"
      :parameters '((:name "text" :type "string" :description "Text to shout"))
      :function (lambda (args)
                  (string-upcase (gethash "text" args))))

    (let ((entry (clambda/tools:find-tool clambda/config:*user-tool-registry*
                                          "shout-tool")))
      (assert entry () "shout-tool not registered via macro")
      (format t "  PASS: define-user-tool macro registered 'shout-tool'~%")

      (let* ((args (make-hash-table :test #'equal)))
        (setf (gethash "text" args) "hello world")
        (let ((result (funcall (clambda/tools::tool-entry-handler entry) args)))
          (let ((str (if (stringp result)
                         result
                         (clambda/tools:tool-result-value result))))
            (assert (string= str "HELLO WORLD"))
            (format t "  PASS: shout-tool output = ~S~%" str)))))
    t))

(defun test-merge-user-tools ()
  "merge-user-tools! copies all user tools into a target registry."
  (format t "~%=== test-merge-user-tools ===~%")

  (let ((clambda/config:*user-tool-registry* (make-tool-registry))
        (target (make-tool-registry)))

    (clambda/config:register-user-tool!
     "tool-alpha" "Alpha" nil (lambda (a) (declare (ignore a)) "alpha"))
    (clambda/config:register-user-tool!
     "tool-beta" "Beta" nil (lambda (a) (declare (ignore a)) "beta"))

    (clambda/config:merge-user-tools! target)

    (assert (clambda/tools:find-tool target "tool-alpha"))
    (assert (clambda/tools:find-tool target "tool-beta"))
    (format t "  PASS: merge-user-tools! copied ~A tools~%"
            (length (clambda/tools:list-tools target))))
  t)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 5. load-user-config
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun test-load-config-not-found ()
  "load-user-config returns NIL when no init.lisp exists."
  (format t "~%=== test-load-config-not-found ===~%")

  (let ((clambda/config:*clambda-home*
         (uiop:ensure-directory-pathname "/tmp/clambda-definitely-not-here-xyz/"))
        (clambda/config::*user-config-loaded* nil))

    (let ((result (clambda/config:load-user-config)))
      (assert (null result) () "Expected NIL, got ~A" result)
      (assert (null (clambda/config:user-config-loaded-p)))
      (format t "  PASS: returns NIL when no init.lisp~%")))
  t)

(defun test-load-config-success ()
  "load-user-config loads a valid init.lisp and sets *user-config-loaded*."
  (format t "~%=== test-load-config-success ===~%")

  (let ((original-model clambda/config:*default-model*))
    (unwind-protect
         (with-temp-init-file
             (((in-package #:clambda-user)
               (setf *default-model* "init-test/my-model")))

           (let ((result (clambda/config:load-user-config)))
             (assert result () "Expected T from load-user-config")
             (assert (clambda/config:user-config-loaded-p))
             (format t "  PASS: load-user-config returned T~%")

             (assert (string= clambda/config:*default-model* "init-test/my-model"))
             (format t "  PASS: *default-model* = ~S (set by init.lisp)~%"
                     clambda/config:*default-model*)))
      (setf clambda/config:*default-model* original-model)))
  t)

(defun test-load-config-runs-after-init-hook ()
  "*after-init-hook* fires after successful init.lisp load."
  (format t "~%=== test-load-config-runs-after-init-hook ===~%")

  ;; We pre-install a hook, then load an init.lisp (any valid one)
  (let ((clambda/config:*after-init-hook* '())
        (hook-fired nil))

    (clambda/config:add-hook '*after-init-hook* (lambda () (setf hook-fired t)))

    (with-temp-init-file
        (((in-package #:clambda-user)))  ; minimal valid init

      (clambda/config:load-user-config)

      (assert hook-fired () "*after-init-hook* did not fire")
      (format t "  PASS: *after-init-hook* fired after init.lisp load~%")))
  t)

(defun test-load-config-error-recovery ()
  "load-user-config catches init.lisp errors and returns NIL (does not signal)."
  (format t "~%=== test-load-config-error-recovery ===~%")

  (with-temp-init-file
      (((error "deliberate init.lisp error for testing")))

    (let ((result (clambda/config:load-user-config)))
      (assert (null result) () "Expected NIL on init.lisp error, got ~A" result)
      (assert (null (clambda/config:user-config-loaded-p)))
      (format t "  PASS: init.lisp error caught gracefully, returned NIL~%")))
  t)

(defun test-load-config-channel-registration ()
  "init.lisp can call register-channel; result appears in *registered-channels*."
  (format t "~%=== test-load-config-channel-registration ===~%")

  (let ((clambda/config:*registered-channels* '()))
    (with-temp-init-file
        (((in-package #:clambda-user)
          (register-channel :my-test-bot
                            :token "SECRET"
                            :allowed-users (list 999))))

      (clambda/config:load-user-config)

      (let ((entry (assoc :my-test-bot clambda/config:*registered-channels*)))
        (assert entry () ":my-test-bot not in *registered-channels* after init load")
        (assert (string= (getf (cdr entry) :token) "SECRET"))
        (format t "  PASS: init.lisp registered :my-test-bot channel~%")
        (format t "        :token = ~S~%" (getf (cdr entry) :token)))))
  t)

(defun test-load-config-user-tool ()
  "init.lisp can define user tools via define-user-tool."
  (format t "~%=== test-load-config-user-tool ===~%")

  (let ((clambda/config:*user-tool-registry* (make-tool-registry)))
    (with-temp-init-file
        (((in-package #:clambda-user)
          (define-user-tool reverse-string-tool
            :description "Reverses a string"
            :parameters (list (list :name "s" :type "string" :description "String to reverse"))
            :function (lambda (args)
                        (reverse (gethash "s" args))))))

      (clambda/config:load-user-config)

      (let ((entry (clambda/tools:find-tool clambda/config:*user-tool-registry*
                                            "reverse-string-tool")))
        (assert entry () "reverse-string-tool not found after init load")
        (format t "  PASS: init.lisp registered 'reverse-string-tool'~%")

        ;; Run it
        (let* ((args (make-hash-table :test #'equal)))
          (setf (gethash "s" args) "hello")
          (let ((result (funcall (clambda/tools::tool-entry-handler entry) args)))
            (let ((str (if (stringp result)
                           result
                           (clambda/tools:tool-result-value result))))
              (assert (string= str "olleh"))
              (format t "  PASS: tool output = ~S~%" str))))))
    t))

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 6. Package structure
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun test-clambda-user-package ()
  "clambda-user package exists and exports expected symbols."
  (format t "~%=== test-clambda-user-package ===~%")

  (let ((pkg (find-package '#:clambda-user)))
    (assert pkg () "clambda-user package not found")
    (format t "  PASS: clambda-user package exists~%")

    (dolist (sym-str '("DEFOPTION"
                       "ADD-HOOK" "REMOVE-HOOK" "RUN-HOOK" "RUN-HOOK-WITH-ARGS"
                       "*AFTER-INIT-HOOK*"
                       "*BEFORE-AGENT-TURN-HOOK*"
                       "*AFTER-TOOL-CALL-HOOK*"
                       "*CHANNEL-MESSAGE-HOOK*"
                       "REGISTER-CHANNEL"
                       "DEFINE-USER-TOOL"
                       "*USER-TOOL-REGISTRY*"
                       "*DEFAULT-MODEL*"
                       "*DEFAULT-MAX-TURNS*"
                       "*DEFAULT-STREAM*"
                       "MAKE-TOOL-REGISTRY"
                       "REGISTER-TOOL!"
                       "FIND-TOOL"
                       "MAKE-AGENT"
                       "MAKE-CLIENT"))
      (multiple-value-bind (sym status)
          (find-symbol sym-str pkg)
        (assert (and sym status)
                () "Symbol ~A not accessible in clambda-user" sym-str)
        (format t "  PASS: clambda-user:~A (~A)~%" sym-str status))))
  t)

(defun test-clambda-package-exports ()
  "Top-level clambda package re-exports all config symbols."
  (format t "~%=== test-clambda-package-exports ===~%")

  (dolist (sym-str '("LOAD-USER-CONFIG"
                     "USER-CONFIG-LOADED-P"
                     "DEFOPTION"
                     "*OPTION-REGISTRY*"
                     "DESCRIBE-OPTIONS"
                     "ADD-HOOK"
                     "REMOVE-HOOK"
                     "RUN-HOOK"
                     "RUN-HOOK-WITH-ARGS"
                     "*AFTER-INIT-HOOK*"
                     "*BEFORE-AGENT-TURN-HOOK*"
                     "*AFTER-TOOL-CALL-HOOK*"
                     "*CHANNEL-MESSAGE-HOOK*"
                     "REGISTER-CHANNEL"
                     "*REGISTERED-CHANNELS*"
                     "DEFINE-USER-TOOL"
                     "REGISTER-USER-TOOL!"
                     "*USER-TOOL-REGISTRY*"
                     "*DEFAULT-MODEL*"
                     "*DEFAULT-MAX-TURNS*"
                     "*DEFAULT-STREAM*"
                     "*LOG-LEVEL*"
                     "*STARTUP-MESSAGE*"
                     "*CLAMBDA-HOME*"
                     "CLAMBDA-HOME"))
    (multiple-value-bind (sym status)
        (find-symbol sym-str (find-package '#:clambda))
      (assert (and sym (eq status :external))
              () "~A not :external in clambda package (got ~A ~A)"
              sym-str sym status)
      (format t "  PASS: clambda:~A~%" sym-str)))
  t)

(defun test-describe-options-runs ()
  "describe-options executes without error."
  (format t "~%=== test-describe-options-runs ===~%")

  (let ((output (with-output-to-string (*standard-output*)
                  (clambda/config:describe-options))))
    (assert (> (length output) 10) () "describe-options produced no output")
    ;; Should mention at least one known option
    (assert (search "DEFAULT-MODEL" (string-upcase output))
            () "describe-options output missing *default-model*")
    (format t "  PASS: describe-options produced ~A chars~%" (length output)))
  t)

;;;; ─────────────────────────────────────────────────────────────────────────────
;;;; § 7. Run all
;;;; ─────────────────────────────────────────────────────────────────────────────

(defun run-config-tests ()
  "Run all Layer 6a config system tests. Returns T if all pass."
  (format t "~%~%============================================~%")
  (format t "    Layer 6a: Config System Tests~%")
  (format t "============================================~%")

  (let ((results '()))

    (flet ((run1 (name fn)
             (format t "~%Running ~A ...~%" name)
             (let ((pass
                     (handler-case
                         (funcall fn)
                       (error (e)
                         (format t "  FAIL: ~A~%  Error: ~A~%" name e)
                         nil))))
               (push (cons name pass) results)
               pass)))

      ;; defoption
      (run1 "defoption-defaults"   #'test-defoption-defaults)
      (run1 "defoption-registry"   #'test-defoption-registry)
      (run1 "defoption-setf"       #'test-defoption-setf)

      ;; hooks
      (run1 "hooks-add-remove"        #'test-hooks-add-remove)
      (run1 "hooks-run-order"         #'test-hooks-run-order)
      (run1 "hooks-run-with-args"     #'test-hooks-run-with-args)
      (run1 "hooks-error-isolation"   #'test-hooks-error-isolation)
      (run1 "hooks-standard-vars"     #'test-standard-hook-variables)

      ;; channels
      (run1 "register-channel-basic"      #'test-register-channel-basic)
      (run1 "register-channel-overwrites" #'test-register-channel-overwrites)
      (run1 "register-channel-method"     #'test-register-channel-custom-method)

      ;; user tools
      (run1 "register-user-tool"       #'test-register-user-tool)
      (run1 "register-user-tool-noparam" #'test-register-user-tool-no-params)
      (run1 "define-user-tool-macro"   #'test-define-user-tool-macro)
      (run1 "merge-user-tools"         #'test-merge-user-tools)

      ;; load-user-config
      (run1 "load-not-found"          #'test-load-config-not-found)
      (run1 "load-success"            #'test-load-config-success)
      (run1 "load-after-init-hook"    #'test-load-config-runs-after-init-hook)
      (run1 "load-error-recovery"     #'test-load-config-error-recovery)
      (run1 "load-channel-reg"        #'test-load-config-channel-registration)
      (run1 "load-user-tool"          #'test-load-config-user-tool)

      ;; package structure
      (run1 "clambda-user-package"    #'test-clambda-user-package)
      (run1 "clambda-pkg-exports"     #'test-clambda-package-exports)
      (run1 "describe-options"        #'test-describe-options-runs))

    ;; Summary
    (format t "~%~%--- Layer 6a Config Test Summary ---~%")
    (let ((passed (count-if #'cdr results))
          (total  (length results)))
      (dolist (r (reverse results))
        (format t "  [~A] ~A~%"
                (if (cdr r) "PASS" "FAIL")
                (car r)))
      (format t "~%~A / ~A passed~%~%" passed total)
      (= passed total))))
