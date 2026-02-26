# Pattern: Subagent Handle (bt:make-thread + result struct)

## Problem
Need to spawn a background agent loop and get its result back asynchronously, with the ability to poll status, block-until-done, and cancel.

## Solution

Return an opaque handle struct immediately; the thread writes back to it.

```lisp
(defstruct subagent-handle
  thread session
  (status :running :type keyword)
  result error lock cvar)

(defun spawn-subagent (agent task &key callback options)
  (let* ((sess   (make-session :agent agent))
         (lock   (bt:make-lock "sa-lock"))
         (cvar   (bt:make-condition-variable :name "sa-cvar"))
         (handle (%make-subagent-handle :session sess :lock lock :cvar cvar)))
    (setf (subagent-handle-thread handle)
          (bt:make-thread
           (lambda ()
             (handler-case
                 (let ((result (run-agent sess task :options options)))
                   (bt:with-lock-held (lock)
                     (setf (subagent-handle-result handle) result
                           (subagent-handle-status handle) :done)
                     (bt:condition-notify cvar))
                   (when callback (funcall callback result)))
               (serious-condition (c)
                 (bt:with-lock-held (lock)
                   (setf (subagent-handle-error  handle) c
                         (subagent-handle-status handle) :failed)
                   (bt:condition-notify cvar))
                 (when callback (funcall callback nil)))))
           :name "subagent"))
    handle))

(defun subagent-wait (handle &key timeout)
  (bt:with-lock-held ((subagent-handle-lock handle))
    (loop :while (eq (subagent-handle-status handle) :running)
          :do (if timeout
                  (bt:condition-wait (subagent-handle-cvar handle)
                                     (subagent-handle-lock handle)
                                     :timeout timeout)
                  (bt:condition-wait (subagent-handle-cvar handle)
                                     (subagent-handle-lock handle))))
    (values (subagent-handle-result handle)
            (subagent-handle-status handle))))
```

## Key Rules

1. **Struct slots for status/result** — never use shared globals. Each handle is self-contained.
2. **Lock + condvar for signalling** — thread writes result, sets `:done`, notifies; waiter blocks until not `:running`.
3. **`handler-case serious-condition`** — catch all serious conditions (not just `error`), set `:failed`, store the condition object. This prevents silent thread death.
4. **Callback is called in the child thread** — don't block the main thread; callbacks must be thread-safe.
5. **`bt:destroy-thread` is last resort** — it is asynchronous and may leave resources (open files, locks) in bad state. Document this in the API.

## Status Transitions

```
:running → :done    (normal completion)
:running → :failed  (unhandled condition)
:running → :killed  (bt:destroy-thread called)
```

## When to Use

Any time you need fire-and-forget background work with structured result retrieval. Especially useful for:
- Sub-agent delegation in multi-agent orchestration
- Parallel tool execution
- Background indexing/search
