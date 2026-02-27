# Clawmacs — Next Steps

## Phase 1: Stabilize (Critical Path)

### 1.1 Full SBCL Compile & Test Pass
- Load `clawmacs-core` in SBCL, fix all compile errors from the rename
- Run full test suite (261+ tests), fix regressions
- Verify Layer 9 superpowers work at runtime (conditions, SWANK, image save, define-agent)
- **Status:** Gensym subagent running now

### 1.2 Boot a Real Agent
- Start Clawmacs with `~/.clawmacs/init.lisp`
- Verify Telegram bot actually connects and responds
- Verify IRC bot actually connects and responds
- Test browser control end-to-end
- Test cron scheduler fires
- Test HTTP management API responds with auth
- **This is the real acceptance test — can it actually run?**

### 1.3 Fix Init.lisp for ~/.clawmacs/
- Ensure the init.lisp created during migration works with renamed packages (clawmacs-user, not clambda-user)
- Test: `sbcl --load clawmacs --eval '(clawmacs:start)'`

## Phase 2: Operational Readiness

### 2.1 Systemd Service
- Write a `clawmacs.service` unit file for running as a daemon
- Auto-restart on crash, journal logging
- `clawmacs start` / `clawmacs stop` / `clawmacs status`

### 2.2 Startup Script Hardening
- The `./clawmacs` launcher script needs to handle:
  - LD_LIBRARY_PATH for cl+ssl
  - Quicklisp path detection
  - ASDF registry setup
  - Graceful shutdown on SIGTERM/SIGINT
  - PID file for service management

### 2.3 Log Rotation
- Structured JSON logs to `~/.clawmacs/logs/`
- Rotate daily, keep 30 days
- Separate logs per channel (telegram.jsonl, irc.jsonl, api.jsonl)

## Phase 3: P2 Superpowers

### 3.1 Pausable Agents
- Agent signals `human-input-needed` condition mid-turn
- System sends question to user via active channel
- User reply resumes the exact continuation
- This is the killer feature no other agent framework has

### 3.2 Self-Modifying Agent Scaffold
- `(agent-inspect-self)` — returns the agent's own tool definitions as s-expressions
- `(agent-redefine-tool name new-fn)` — hot-patches a tool in the running agent
- Safety rails: changelog of all self-modifications, rollback capability
- Start with tool-level self-modification, not full code rewriting

### 3.3 SLIME Integration Guide
- Document how to connect SLIME/Sly to a running Clawmacs
- Example workflows: inspect agent state, modify tools live, debug conditions
- Screencast-style walkthrough in docs

## Phase 4: Repository Hygiene

### 4.1 Rename GitHub/GitLab Repos
- `chrysolambda-ops/clambda` → `chrysolambda-ops/clawmacs`
- `chrysolambda/clambda` → `chrysolambda/clawmacs`
- Update all remote URLs
- Update GitHub Pages URL
- Update all documentation references

### 4.2 CI/CD
- GitHub Actions: run SBCL test suite on push
- Badge in README showing test status
- Auto-rebuild gh-pages on master push

### 4.3 Clean Up Git History
- The gh-pages branch has been force-pushed multiple times
- node_modules were committed at one point (now removed)
- Consider a `git filter-branch` or `git-filter-repo` to clean large objects

## Phase 5: Toward OpenClaw Replacement

### 5.1 Agent Memory System
- Equivalent to OpenClaw's memory search (MEMORY.md + daily files)
- Semantic search using local embeddings (LM Studio has nomic-embed)
- `(memory-search "query")` tool for agents

### 5.2 Multi-Agent Orchestration
- Spawn sub-agents from init.lisp: `(define-agent researcher ...)`
- Agent-to-agent messaging
- CEO/delegation pattern matching OpenClaw's subagent system
- Session isolation per agent

### 5.3 WhatsApp Channel (Optional)
- Lower priority but needed for full parity
- Could use whatsapp-web.js via subprocess bridge (like browser control)

## Priority Order
1. **Phase 1** — without this, nothing else matters
2. **Phase 2** — makes it actually usable day-to-day
3. **Phase 4.1** — repo rename while it's still early
4. **Phase 3** — the features that justify Lisp
5. **Phase 4.2-4.3** — polish
6. **Phase 5** — the endgame
