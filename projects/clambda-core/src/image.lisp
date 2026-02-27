;;;; src/image.lisp — Lisp image save/restore for Clambda
;;;;
;;;; Genera-inspired: save the entire running Clambda system — config, agents,
;;;; tool registries, loaded channels, everything — as a single executable file.
;;;; Restore it instantly with zero dependency resolution at startup.
;;;;
;;;; HOW IT WORKS
;;;;
;;;; `sb-ext:save-lisp-and-die` saves the entire SBCL Lisp image to a file.
;;;; The file includes:
;;;;   - All loaded code (clambda-core, cl-llm, dexador, jzon, ...)
;;;;   - All global state (registered agents, channels, options)
;;;;   - Your init.lisp configuration (since it was already loaded)
;;;;
;;;; When you run the saved image, it calls CLAMBDA-MAIN as the toplevel,
;;;; which re-establishes runtime connections (channels, SWANK server, etc.)
;;;; and resumes normal operation — no startup time for compilation or loading.
;;;;
;;;; USAGE
;;;;
;;;;   ;; Save (from a running Clambda REPL or SWANK session):
;;;;   (save-clambda-image)            ; → ./clambda.core
;;;;   (save-clambda-image #P"/opt/clambda/clambda-bot")  ; custom path
;;;;
;;;;   ;; Restore:
;;;;   ./clambda.core          ; runs clambda-main as the toplevel
;;;;
;;;;   ;; Or explicitly:
;;;;   sbcl --core clambda.core
;;;;
;;;; WHY THIS IS A SUPERPOWER
;;;;
;;;; - Zero cold-start: no dependency loading, no compilation (< 100ms)
;;;; - Distribute as a single binary with all config baked in
;;;; - "Fork" a running agent: save → copy to another host → run → instant clone
;;;; - Checkpoint before risky operations → restore on failure
;;;; - Like Docker, but the entire Lisp runtime. Lispier.
;;;;
;;;; OpenClaw (Node.js) cannot do this. Node has no equivalent to
;;;; sb-ext:save-lisp-and-die — there is no way to save the entire runtime
;;;; state of a V8 engine as a portable executable.
;;;;
;;;; NOTE: Long-running background threads (Telegram polling, IRC reader,
;;;; SWANK) will NOT survive the save/restore boundary. CLAMBDA-MAIN
;;;; re-establishes them on resume. Transient session state (in-memory
;;;; message histories) IS preserved if sessions are in global variables.
;;;; For persistent sessions, call SAVE-SESSION before saving the image.

(in-package #:clambda/image)

;;;; ── Toplevel for saved images ───────────────────────────────────────────────

(defun clambda-main ()
  "Toplevel function for saved Clambda images.

Called automatically when a saved image starts. Performs:
  1. Re-establish the LD_LIBRARY_PATH for CFFI (dexador/SSL)
  2. Print a startup banner
  3. Re-start SWANK server (if *SWANK-PORT* is set)
  4. Re-start channels (if registered, using START-ALL-CHANNELS)
  5. Run *AFTER-INIT-HOOK* to let user code re-initialise
  6. Drop into a REPL (or block forever if started as a daemon)

The image retains all registered agents, tool definitions, and config
from the original session when it was saved."
  ;; 1. Announce startup
  (format t "~&~%╔══════════════════════════════════════════╗~%~
               ║  Clambda — Lisp Agent Platform          ║~%~
               ║  Restored from saved image               ║~%~
               ╚══════════════════════════════════════════╝~%~%")

  ;; 2. Set LD_LIBRARY_PATH so CFFI/dexador can find libcrypto
  ;;    (the saved image may be run from a different shell environment)
  (let ((existing (uiop:getenv "LD_LIBRARY_PATH"))
        (needed "/lib/x86_64-linux-gnu"))
    (unless (and existing (search needed existing))
      (setf (uiop:getenv "LD_LIBRARY_PATH")
            (if (and existing (> (length existing) 0))
                (concatenate 'string needed ":" existing)
                needed))))

  ;; 3. Re-start SWANK (if was running before save)
  (handler-case
      (when (find-package '#:clambda/swank)
        (let ((swank-fn (find-symbol "START-SWANK" '#:clambda/swank)))
          (when swank-fn
            (funcall swank-fn))))
    (error (e)
      (format *error-output*
              "~&[clambda/image] Could not start SWANK on resume: ~a~%" e)))

  ;; 4. Re-start channels (Telegram, IRC, etc.)
  ;;    start-all-channels is safe to call even if nothing is registered
  (handler-case
      (when (find-package '#:clambda/telegram)
        (let ((fn (find-symbol "START-ALL-CHANNELS" '#:clambda/telegram)))
          (when fn (funcall fn))))
    (error (e)
      (format *error-output*
              "~&[clambda/image] Could not restart channels on resume: ~a~%" e)))

  ;; 5. Run after-init hooks (so user code can re-initialise live state)
  (handler-case
      (when (find-package '#:clambda/config)
        (let ((fn (find-symbol "RUN-HOOK" '#:clambda/config)))
          (when fn (funcall fn '*after-init-hook*))))
    (error (e)
      (format *error-output*
              "~&[clambda/image] Error in after-init hooks on resume: ~a~%" e)))

  ;; 6. Show what's loaded and start REPL
  (format t "~&[clambda] Image restored. ~
               ~@[Registered agents: ~a~]~%"
          (handler-case
              (when (find-package '#:clambda/registry)
                (let ((fn (find-symbol "LIST-AGENTS" '#:clambda/registry)))
                  (when fn
                    (length (funcall fn)))))
            (error () nil)))

  ;; Drop into SBCL REPL
  (sb-impl::toplevel-init))

;;;; ── Save function ───────────────────────────────────────────────────────────

(defun save-clambda-image (&optional (path "clambda.core"))
  "Save the entire running Clambda system as a SBCL core/executable file.

PATH — pathname or string for the output file.
       Default: \"clambda.core\" in the current directory.
       For a self-contained executable, use a path without extension.

The saved image includes:
  - All loaded systems (clambda-core, cl-llm, all dependencies)
  - All registered agents, channel configs, user options
  - Your init.lisp settings (already evaluated)
  - The full Quicklisp distribution (loaded at save time)

When run, CLAMBDA-MAIN is invoked as the toplevel, which:
  - Re-starts SWANK (if configured)
  - Re-connects channels (Telegram, IRC, etc.)
  - Runs *AFTER-INIT-HOOK*
  - Drops into a REPL

NOTE: This function DOES NOT RETURN — SBCL exits after saving.
Start a new Clambda instance to use the saved image.

Example:
  (save-clambda-image)                           ; → ./clambda.core
  (save-clambda-image #P\"/usr/local/bin/clambda\") ; → standalone executable

To run the saved image:
  ./clambda.core
  ;; or: sbcl --core clambda.core"
  (let ((path-str (if (pathnamep path)
                      (namestring path)
                      (string path))))
    (format t "~&[clambda/image] Saving Clambda image to: ~a~%" path-str)
    (format t "~&[clambda/image] This process will exit after saving.~%")
    (finish-output)

    ;; Save as executable with clambda-main as the entry point
    (sb-ext:save-lisp-and-die
     path-str
     :toplevel     #'clambda-main
     :executable   t
     :compression  t
     :save-runtime-options t)))
