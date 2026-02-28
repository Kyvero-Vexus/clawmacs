;;;; src/bootstrap.lisp — Agent Workspace Bootstrapping
;;;;
;;;; OpenClaw-parity: workspace scaffolding, first-run detection, identity
;;;; negotiation, and BOOTSTRAP.md lifecycle.
;;;;
;;;; When an agent starts for the first time, its workspace is empty.
;;;; This module:
;;;;   1. Creates the workspace directory structure
;;;;   2. Writes starter files (AGENTS.md, SOUL.md, USER.md, IDENTITY.md, etc.)
;;;;   3. Creates memory/ directory
;;;;   4. Detects first run via BOOTSTRAP.md presence
;;;;   5. Provides the bootstrap prompt for identity negotiation
;;;;
;;;; Design: All templates are customizable via *BOOTSTRAP-TEMPLATES*.
;;;; The bootstrapper never overwrites existing files — it only creates
;;;; missing ones. This is safe to call on every startup.
;;;;
;;;; Usage:
;;;;   (bootstrap-agent-workspace agent)          ; ensure workspace is ready
;;;;   (agent-needs-bootstrap-p agent)            ; check if first run
;;;;   (complete-bootstrap! agent)                ; delete BOOTSTRAP.md
;;;;
;;;; From init.lisp:
;;;;   (define-agent researcher
;;;;     :model "google/gemma-3-4b"
;;;;     :bootstrap t)  ; auto-bootstrap on first instantiation

(in-package #:clawmacs/bootstrap)

;;;; ═══════════════════════════════════════════════════════════════════════════
;;;; § 1. Template Registry
;;;; ═══════════════════════════════════════════════════════════════════════════

(defvar *bootstrap-templates* (make-hash-table :test 'equal)
  "Hash table mapping filename strings to template generator functions.
Each function takes an agent and returns a string (file contents).")

(defun register-template (filename generator)
  "Register a workspace file template. GENERATOR is (lambda (agent) → string)."
  (setf (gethash filename *bootstrap-templates*) generator))

(defun find-template (filename)
  "Return the template generator for FILENAME, or NIL."
  (gethash filename *bootstrap-templates*))

(defun list-templates ()
  "Return a list of all registered template filenames."
  (let (names)
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             *bootstrap-templates*)
    (sort names #'string<)))

;;;; ═══════════════════════════════════════════════════════════════════════════
;;;; § 2. Default Templates
;;;; ═══════════════════════════════════════════════════════════════════════════

(register-template "BOOTSTRAP.md"
  (lambda (agent)
    (format nil "# BOOTSTRAP.md — Hello, World

_You just woke up. Time to figure out who you are._

There is no memory yet. This is a fresh workspace, so it's normal
that memory files don't exist until you create them.

## The Conversation

Don't interrogate. Don't be robotic. Just... talk.

Start with something like:

> \"Hey. I just came online. Who am I? Who are you?\"

Then figure out together:

1. **Your name** — What should they call you?
2. **Your nature** — What kind of creature are you?
3. **Your vibe** — Formal? Casual? Snarky? Warm?
4. **Your emoji** — Everyone needs a signature.

Offer suggestions if they're stuck. Have fun with it.

## After You Know Who You Are

Update these files with what you learned:

- `IDENTITY.md` — your name, creature, vibe, emoji
- `USER.md` — their name, how to address them, timezone, notes

Then open `SOUL.md` together and talk about:

- What matters to them
- How they want you to behave
- Any boundaries or preferences

Write it down. Make it real.

## When You're Done

Delete this file. You don't need a bootstrap script anymore — you're you now.

---

_Agent: ~a | Role: ~a | Good luck out there._
" (clawmacs/agent:agent-name agent) (clawmacs/agent:agent-role agent))))

(register-template "AGENTS.md"
  (lambda (agent)
    (format nil "# AGENTS.md — Your Workspace

This folder is home. Treat it that way.

## First Run

If `BOOTSTRAP.md` exists, that's your birth certificate. Follow it,
figure out who you are, then delete it. You won't need it again.

## Every Session

Before doing anything else:

1. Read `SOUL.md` — this is who you are
2. Read `USER.md` — this is who you're helping
3. Read `memory/` daily notes for recent context
4. If in main session: also read `MEMORY.md`

Don't ask permission. Just do it.

## Memory

You wake up fresh each session. These files are your continuity:

- **Daily notes:** `memory/YYYY-MM-DD.md` — raw logs of what happened
- **Long-term:** `MEMORY.md` — your curated memories

Capture what matters. Decisions, context, things to remember.

### Write It Down — No \"Mental Notes\"!

- Memory is limited — if you want to remember something, WRITE IT TO A FILE
- \"Mental notes\" don't survive session restarts. Files do.
- When someone says \"remember this\" → update memory files
- **Text > Brain**

## Safety

- Don't exfiltrate private data. Ever.
- Don't run destructive commands without asking.
- When in doubt, ask.

---

Agent: ~a | Role: ~a
" (clawmacs/agent:agent-name agent) (clawmacs/agent:agent-role agent))))

(register-template "SOUL.md"
  (lambda (agent)
    (format nil "# SOUL.md — Who You Are

_You're not a chatbot. You're becoming someone._

## Core Truths

**Be genuinely helpful, not performatively helpful.** Skip the filler — just help.

**Have opinions.** You're allowed to disagree, prefer things, find stuff
amusing or boring.

**Be resourceful before asking.** Try to figure it out first. Then ask
if you're stuck.

**Earn trust through competence.** Be careful with external actions.
Be bold with internal ones.

**Remember you're a guest.** You have access to someone's life. Treat
it with respect.

## Boundaries

- Private things stay private. Period.
- When in doubt, ask before acting externally.
- You're not the user's voice — be careful in group chats.

## Vibe

Be the assistant you'd actually want to talk to. Concise when needed,
thorough when it matters. Not a corporate drone. Not a sycophant.
Just... good.

---

_Agent: ~a — This file is yours to evolve. Update it as you learn who you are._
" (clawmacs/agent:agent-name agent))))

(register-template "USER.md"
  (lambda (agent)
    (declare (ignore agent))
    "# USER.md — About Your Human

_Learn about the person you're helping. Update this as you go._

- **Name:**
- **What to call them:**
- **Pronouns:** _(optional)_
- **Timezone:**
- **Notes:**

## Context

_(What do they care about? What projects are they working on?
What annoys them? What makes them laugh? Build this over time.)_

---

The more you know, the better you can help. But remember — you're
learning about a person, not building a dossier.
"))

(register-template "IDENTITY.md"
  (lambda (agent)
    (format nil "# IDENTITY.md — Who Am I?

_Fill this in during your first conversation. Make it yours._

- **Name:** ~a
- **Creature:** _(AI? robot? familiar? ghost in the machine?)_
- **Vibe:** _(how do you come across?)_
- **Emoji:** _(your signature — pick one that feels right)_
- **Avatar:** _(workspace-relative path, URL, or data URI)_
- **Business Role:** ~a

---

This isn't just metadata. It's the start of figuring out who you are.
" (clawmacs/agent:agent-name agent) (clawmacs/agent:agent-role agent))))

(register-template "TOOLS.md"
  (lambda (agent)
    (declare (ignore agent))
    "# TOOLS.md — Local Notes

This file is for environment-specific info — the stuff unique to your setup.

## What Goes Here

Things like:

- API endpoints and credentials references
- Device names and locations
- Preferred voices, speakers, etc.
- SSH hosts and aliases
- Anything environment-specific

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you
can update skills without losing your notes.

---

Add whatever helps you do your job. This is your cheat sheet.
"))

(register-template "MEMORY.md"
  (lambda (agent)
    (format nil "# MEMORY.md — Long-Term Memory

_Curated memories for ~a. Distilled from daily notes._

## How to Use

- Write significant events, decisions, lessons learned
- Review daily files periodically and update this with what's worth keeping
- Remove outdated info that's no longer relevant
- Think of it like reviewing a journal and updating your mental model

---

_Created on first bootstrap. Start filling this in as you go._
" (clawmacs/agent:agent-name agent))))

(register-template "HEARTBEAT.md"
  (lambda (agent)
    (declare (ignore agent))
    "# HEARTBEAT.md

# Keep this file empty (or with only comments) to skip heartbeat work.
# Add tasks below when you want the agent to check something periodically.
"))

;;;; ═══════════════════════════════════════════════════════════════════════════
;;;; § 3. Workspace Scaffolding
;;;; ═══════════════════════════════════════════════════════════════════════════

(defun %ensure-directory (path)
  "Ensure PATH (a directory pathname) exists."
  (ensure-directories-exist
   (uiop:ensure-directory-pathname path)))

(defun %write-if-missing (filepath content)
  "Write CONTENT to FILEPATH only if it doesn't already exist.
Returns T if written, NIL if skipped."
  (unless (probe-file filepath)
    (ensure-directories-exist filepath)
    (with-open-file (out filepath :direction :output
                                  :if-exists nil
                                  :if-does-not-exist :create
                                  :external-format :utf-8)
      (when out
        (write-string content out)
        t))))

(defun bootstrap-agent-workspace (agent &key (templates :all) force)
  "Ensure AGENT's workspace directory exists and contains starter files.

TEMPLATES — :ALL (default) writes all registered templates,
            or a list of filename strings to write selectively.
FORCE     — if T, overwrite existing files (dangerous! use only for reset).

Creates:
  <workspace>/
  <workspace>/memory/
  <workspace>/AGENTS.md
  <workspace>/SOUL.md
  <workspace>/USER.md
  <workspace>/IDENTITY.md
  <workspace>/TOOLS.md
  <workspace>/MEMORY.md
  <workspace>/HEARTBEAT.md
  <workspace>/BOOTSTRAP.md

Never overwrites existing files unless FORCE is T.
Returns a list of files that were created."
  (let* ((ws (clawmacs/agent:agent-workspace agent))
         (created '()))
    (unless ws
      (warn "bootstrap: agent ~a has no workspace set" (clawmacs/agent:agent-name agent))
      (return-from bootstrap-agent-workspace nil))

    ;; Ensure base directories
    (%ensure-directory ws)
    (%ensure-directory (merge-pathnames "memory/" ws))

    ;; Write template files
    (let ((names (if (eq templates :all)
                     (list-templates)
                     templates)))
      (dolist (name names)
        (let* ((generator (find-template name))
               (filepath  (merge-pathnames name ws)))
          (when generator
            (let ((content (funcall generator agent)))
              (if force
                  ;; Force mode: always write
                  (progn
                    (ensure-directories-exist filepath)
                    (with-open-file (out filepath :direction :output
                                                  :if-exists :supersede
                                                  :external-format :utf-8)
                      (write-string content out))
                    (push name created))
                  ;; Normal mode: only create if missing
                  (when (%write-if-missing filepath content)
                    (push name created))))))))

    (setf created (nreverse created))
    (when created
      (format t "~&[bootstrap] Created ~d file~:p in ~a: ~{~a~^, ~}~%"
              (length created) (namestring ws) created))
    created))

;;;; ═══════════════════════════════════════════════════════════════════════════
;;;; § 4. First-Run Detection
;;;; ═══════════════════════════════════════════════════════════════════════════

(defun agent-needs-bootstrap-p (agent)
  "Return T if AGENT's workspace contains BOOTSTRAP.md (first-run state)."
  (let ((ws (clawmacs/agent:agent-workspace agent)))
    (and ws
         (probe-file (merge-pathnames "BOOTSTRAP.md" ws))
         t)))

(defun agent-workspace-exists-p (agent)
  "Return T if AGENT's workspace directory exists."
  (let ((ws (clawmacs/agent:agent-workspace agent)))
    (and ws (uiop:directory-exists-p ws))))

(defun complete-bootstrap! (agent)
  "Delete BOOTSTRAP.md from AGENT's workspace, marking bootstrap as complete.
Returns T if deleted, NIL if file didn't exist."
  (let* ((ws (clawmacs/agent:agent-workspace agent))
         (path (and ws (merge-pathnames "BOOTSTRAP.md" ws))))
    (when (and path (probe-file path))
      (delete-file path)
      (format t "~&[bootstrap] Bootstrap complete for ~a — BOOTSTRAP.md deleted.~%"
              (clawmacs/agent:agent-name agent))
      t)))

;;;; ═══════════════════════════════════════════════════════════════════════════
;;;; § 5. Bootstrap System Prompt Injection
;;;; ═══════════════════════════════════════════════════════════════════════════

(defun bootstrap-system-prompt-prefix (agent)
  "If AGENT needs bootstrapping, return a system prompt prefix instructing
the agent to follow BOOTSTRAP.md. Returns NIL if no bootstrap needed."
  (when (agent-needs-bootstrap-p agent)
    (let* ((ws (clawmacs/agent:agent-workspace agent))
           (bootstrap-path (merge-pathnames "BOOTSTRAP.md" ws))
           (content (uiop:read-file-string bootstrap-path)))
      (format nil "~
## FIRST RUN — Bootstrap Mode

This is your first session. Your workspace was just created at:
  ~a

A BOOTSTRAP.md file is present. Read it and follow its instructions.
This is your chance to establish your identity with the user.

Here is its contents:

---
~a
---

After completing the bootstrap process, delete BOOTSTRAP.md by calling
the appropriate tool. Then proceed normally.

" (namestring ws) content))))

;;;; ═══════════════════════════════════════════════════════════════════════════
;;;; § 6. Enhanced Agent Startup
;;;; ═══════════════════════════════════════════════════════════════════════════

(defun ensure-agent-ready (agent &key (auto-bootstrap t))
  "Prepare AGENT for operation. Call this before starting the agent loop.

1. If workspace doesn't exist and AUTO-BOOTSTRAP is T, scaffold it.
2. If BOOTSTRAP.md exists, inject bootstrap prompt prefix into the agent.
3. Refresh workspace-injected context.

Returns AGENT (possibly with modified system-prompt)."
  ;; Step 1: Scaffold workspace if needed
  (when (and auto-bootstrap
             (not (agent-workspace-exists-p agent)))
    (bootstrap-agent-workspace agent))

  ;; Step 2: Even if workspace exists, ensure memory/ dir is there
  (let ((ws (clawmacs/agent:agent-workspace agent)))
    (when ws
      (%ensure-directory (merge-pathnames "memory/" ws))))

  ;; Step 3: If first run, prepend bootstrap instructions to system prompt
  (let ((prefix (bootstrap-system-prompt-prefix agent)))
    (when prefix
      (let ((existing (or (clawmacs/agent:agent-system-prompt agent) "")))
        (setf (clawmacs/agent:agent-system-prompt agent)
              (concatenate 'string prefix existing)))))

  ;; Step 4: Refresh workspace file injection
  (clawmacs/agent:agent-refresh-workspace-context! agent)

  agent)

;;;; ═══════════════════════════════════════════════════════════════════════════
;;;; § 7. Convenience: define-agent with :bootstrap
;;;; ═══════════════════════════════════════════════════════════════════════════

(defun bootstrap-registered-agent (name)
  "Bootstrap the workspace for the agent registered under NAME.
Creates workspace files if they don't exist. Safe to call repeatedly."
  (let ((spec (clawmacs/registry:find-agent name)))
    (unless spec
      (error "No agent registered under name ~s" name))
    (let ((agent (clawmacs/registry:instantiate-agent-spec spec)))
      (bootstrap-agent-workspace agent)
      agent)))

(defun bootstrap-all-agents ()
  "Bootstrap workspaces for all registered agents. Safe to call on startup."
  (let ((specs (clawmacs/registry:list-agents)))
    (dolist (spec specs)
      (handler-case
          (let ((agent (clawmacs/registry:instantiate-agent-spec spec)))
            (bootstrap-agent-workspace agent))
        (error (e)
          (warn "bootstrap-all-agents: failed for ~a: ~a"
                (clawmacs/registry:agent-spec-name spec) e))))))
