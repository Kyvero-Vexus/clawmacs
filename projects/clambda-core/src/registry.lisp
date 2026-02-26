;;;; src/registry.lisp — Agent Registry (Task 2.2)
;;;;
;;;; Provides a global registry of named agent specs.
;;;; Specs can be created declaratively with DEFINE-AGENT and
;;;; instantiated into live AGENT objects with INSTANTIATE-AGENT-SPEC.

(in-package #:clambda/registry)

;;; ── Agent Spec ───────────────────────────────────────────────────────────────

(defstruct (agent-spec (:conc-name agent-spec-))
  "A declarative description of an agent (data, not a live object).
Can be registered by name and later instantiated into an AGENT."
  (name          ""  :type string)
  (role          "assistant" :type string)
  (model         nil :type (or null string))
  (system-prompt nil :type (or null string))
  (tools         nil :type list)         ; list of tool names or tool objects
  (client        nil))                   ; a CL-LLM:CLIENT, or NIL

(defmethod print-object ((spec agent-spec) stream)
  (print-unreadable-object (spec stream :type t)
    (format stream "~s role=~s model=~s"
            (agent-spec-name spec)
            (agent-spec-role spec)
            (or (agent-spec-model spec) "(default)"))))

;;; ── Global Registry ──────────────────────────────────────────────────────────

(defvar *agent-registry* (make-hash-table :test 'equal)
  "Global registry mapping agent name strings (and keywords) to AGENT-SPEC objects.
Use REGISTER-AGENT / FIND-AGENT / LIST-AGENTS to access it.")

(defvar *registry-lock* (bt:make-lock "agent-registry-lock")
  "Protects *AGENT-REGISTRY* for concurrent access.")

;;; ── Operations ───────────────────────────────────────────────────────────────

(defun normalize-name (name)
  "Normalize NAME to a string key. Accepts strings and keywords."
  (etypecase name
    (string  name)
    (keyword (string-downcase (symbol-name name)))))

(defun register-agent (name spec)
  "Register SPEC (an AGENT-SPEC or an AGENT) under NAME in *AGENT-REGISTRY*.
NAME can be a string or keyword. Returns SPEC."
  (let ((key (normalize-name name)))
    (bt:with-lock-held (*registry-lock*)
      (setf (gethash key *agent-registry*) spec)))
  spec)

(defun find-agent (name)
  "Return the AGENT-SPEC registered under NAME, or NIL if not found.
NAME can be a string or keyword."
  (let ((key (normalize-name name)))
    (bt:with-lock-held (*registry-lock*)
      (gethash key *agent-registry*))))

(defun unregister-agent (name)
  "Remove the entry for NAME from *AGENT-REGISTRY*. Returns T if removed."
  (let ((key (normalize-name name)))
    (bt:with-lock-held (*registry-lock*)
      (remhash key *agent-registry*))))

(defun list-agents ()
  "Return a list of all registered AGENT-SPECs."
  (bt:with-lock-held (*registry-lock*)
    (let ((result '()))
      (maphash (lambda (k v)
                 (declare (ignore k))
                 (push v result))
               *agent-registry*)
      (nreverse result))))

(defun clear-registry ()
  "Remove all entries from *AGENT-REGISTRY*."
  (bt:with-lock-held (*registry-lock*)
    (clrhash *agent-registry*)))

;;; ── Instantiation ────────────────────────────────────────────────────────────

(defun instantiate-agent-spec (spec)
  "Create a live AGENT from SPEC (an AGENT-SPEC).

The returned agent has:
- name, role, model, system-prompt from the spec
- client from the spec (or NIL if not set)
- tool-registry: NIL (caller is responsible for registering tools)

Returns: (values agent spec)"
  (check-type spec agent-spec)
  (values
   (clambda/agent:make-agent
    :name           (agent-spec-name spec)
    :role           (agent-spec-role spec)
    :model          (agent-spec-model spec)
    :system-prompt  (agent-spec-system-prompt spec)
    :client         (agent-spec-client spec)
    :tool-registry  nil)
   spec))

;;; ── Declarative Definition Macro ─────────────────────────────────────────────

(defmacro define-agent (name &key (role "assistant") model system-prompt tools client)
  "Declaratively define and register an agent spec.

  (define-agent :researcher
    :model \"qwen2.5-7b-instruct\"
    :system-prompt \"You are a research assistant.\"
    :tools (:web-search :read-file))

Registers the spec in *AGENT-REGISTRY* and returns it.
NAME — keyword or string.
ROLE — role label (default: \"assistant\").
MODEL — LLM model string.
SYSTEM-PROMPT — system prompt string.
TOOLS — list of tool name keywords (for documentation; wiring is done by caller).
CLIENT — a CL-LLM:CLIENT instance, or NIL."
  (let ((name-str (etypecase name
                    (string  name)
                    (keyword (string-downcase (symbol-name name))))))
    `(let ((spec (make-agent-spec
                  :name          ,name-str
                  :role          ,role
                  :model         ,model
                  :system-prompt ,system-prompt
                  :tools         (list ,@tools)
                  :client        ,client)))
       (register-agent ,name spec)
       spec)))
