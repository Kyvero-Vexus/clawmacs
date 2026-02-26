;;;; src/tools.lisp — Tool/function calling support

(in-package #:cl-llm/tools)

;;; ── Tool Registry ────────────────────────────────────────────────────────────

(defstruct tool-registry
  "A registry mapping tool names to handler functions and definitions."
  (table (make-hash-table :test #'equal)))

(defun make-registry ()
  "Create a new empty tool registry."
  (make-tool-registry))

(defun register-tool (registry name handler &key description parameters)
  "Register a tool with NAME, HANDLER function, and optional DESCRIPTION/PARAMETERS.

HANDLER is a function called with the parsed arguments (as a plist or hash-table).
PARAMETERS should be a JSON Schema (as a plist or hash-table)."
  (let ((def (make-tool-definition
              :name name
              :description description
              :parameters (etypecase parameters
                            (null nil)
                            (list (cl-llm/json:plist->object parameters))
                            (hash-table parameters)))))
    (setf (gethash name (tool-registry-table registry))
          (cons handler def)))
  registry)

(defun find-tool (registry name)
  "Return (values handler definition) for NAME, or (values NIL NIL)."
  (let ((entry (gethash name (tool-registry-table registry))))
    (if entry
        (values (car entry) (cdr entry))
        (values nil nil))))

(defun all-tool-definitions (registry)
  "Return list of all TOOL-DEFINITION structs in REGISTRY."
  (loop :for (handler . def)
        :being :the :hash-values :of (tool-registry-table registry)
        :collect def))

(defun dispatch-tool-call (registry tool-call)
  "Dispatch a TOOL-CALL through the registry.
Returns the handler's return value, or signals an error if tool not found."
  (let ((name (cl-llm/protocol:tool-call-function-name tool-call))
        (raw-args (cl-llm/protocol:tool-call-function-arguments tool-call)))
    (multiple-value-bind (handler def)
        (find-tool registry name)
      (declare (ignore def))
      (unless handler
        (error "No tool registered for ~s" name))
      ;; Parse arguments: could be a JSON string or already a hash-table
      (let ((args (etypecase raw-args
                    (null (make-hash-table :test #'equal))
                    (string (com.inuoe.jzon:parse raw-args))
                    (hash-table raw-args))))
        (funcall handler args)))))

(defun make-tool-result-message (tool-call result)
  "Create a tool result message for TOOL-CALL with RESULT string."
  (cl-llm/protocol:tool-message
   (if (stringp result) result (format nil "~a" result))
   (cl-llm/protocol:tool-call-id tool-call)))

;;; ── DEFINE-TOOL macro ────────────────────────────────────────────────────────

(defmacro define-tool (registry name (&rest arg-specs) &body body)
  "Define and register a tool in REGISTRY.

NAME — a string, the tool name.
ARG-SPECS — list of (PARAM-NAME TYPE DESCRIPTION) triples.
BODY — function body; args are bound by name as CL symbols (keyword → symbol).

Example:
  (define-tool *registry* \"get_weather\"
    ((location \"string\" \"City name\")
     (unit \"string\" \"celsius or fahrenheit\"))
    (get-weather-data location unit))

The macro generates JSON Schema for the parameters automatically."
  (let* ((param-symbols (mapcar (lambda (spec)
                                  (intern (string-upcase
                                           (substitute #\- #\_
                                                       (string (first spec))))))
                                arg-specs))
         (param-names   (mapcar (lambda (spec) (string (first spec))) arg-specs))
         (param-types   (mapcar #'second arg-specs))
         (param-descs   (mapcar #'third arg-specs))
         (ht-sym        (gensym "ARGS")))
    `(register-tool
      ,registry
      ,name
      (lambda (,ht-sym)
        ;; Bind each parameter from the args hash-table
        (let ,(mapcar (lambda (sym pname)
                        `(,sym (gethash ,pname ,ht-sym)))
                      param-symbols param-names)
          ,@body))
      :description ,(when body (format nil ""))
      :parameters  (list :|type| "object"
                         :|properties|
                         (list ,@(mapcan
                                  (lambda (pname ptype pdesc)
                                    `(,(intern pname :keyword)
                                      (list :|type| ,ptype
                                            ,@(when pdesc
                                                `(:|description| ,pdesc)))))
                                  param-names param-types param-descs))
                         :|required|
                         (vector ,@param-names)))))

(defun tool-schema (registry)
  "Return the list of tool definitions from REGISTRY, ready for CHAT."
  (all-tool-definitions registry))
