# ROADMAP.md — Clambda / OpenClaw Rewrite

> What's been built, what's needed, and in what order.
> Updated after Layer 4 (team codification complete).

---

## Completed Layers

### ✅ Layer 1: `cl-llm` — LLM API Client
**Status:** Shipping. Tested with LM Studio and Ollama.

Delivers:
- OpenAI-compatible HTTP client (non-streaming and streaming)
- SSE parsing for streaming responses
- Tool definition structs and JSON serialization
- Conditions for HTTP and parse errors

Gaps/TODOs:
- No Anthropic-native API support (only OpenAI-compat)
- No retry/backoff on transient errors
- No response caching

---

### ✅ Layer 2a: `cl-tui` — Terminal Chat Interface
**Status:** Shipping. Single-threaded, streaming, slash commands.

Delivers:
- ANSI color output without dependencies
- Streaming token display (`force-output` per token)
- Slash command dispatch (`/model`, `/system`, `/clear`, `/quit`)
- Clean app state struct

Gaps/TODOs:
- No tool use (talks directly to cl-llm, not clambda-core)
- No conversation history persistence
- No multi-model routing

---

### ✅ Layer 2b: `clambda-core` — Agent Platform Core
**Status:** Shipping. Multi-turn tool-using agent loop.

Delivers:
- `agent` + `session` structs
- Tool registry with `register-tool!` + `define-tool`
- `schema-plist->ht` recursive JSON schema converter
- Built-in tools: `exec`, `read_file`, `write_file`, `list_dir`, `web_fetch`
- Hook system: `*on-tool-call*`, `*on-tool-result*`, `*on-llm-response*`, `*on-stream-delta*`
- Agent loop with configurable max-turns
- Session persistence: `save-session` / `load-session` (JSON)
- Structured logging: `clambda/logging` module, JSONL output
- Workspace memory: `clambda/memory` module, priority .md loading, context injection

Gaps/TODOs:
- No tool schema validation
- No sub-agent spawning

---

### ✅ Layer 3: `clambda-gui` — McCLIM GUI Frontend
**Status:** Shipping. Windowed chat with streaming and threading.

Delivers:
- Application frame with chat log, sidebar, status bar, command input
- Background LLM worker thread (bordeaux-threads)
- Streaming token display via hooks and `safe-redisplay`
- Command table (Send, Clear, Quit)

Gaps/TODOs:
- Single session only (no session switching)
- No sidebar model/tools info
- No font configuration (uses CLIM defaults)
- Thread safety is best-effort (`safe-redisplay`)

---

### ✅ Layer 4: Team Codification
**Status:** Complete (this commit).

Delivers:
- `TEAM.md` — operations manual
- `knowledge/cl-style-guide.md` — CL coding standards
- `knowledge/architecture.md` — system architecture doc
- `knowledge/mistakes/recent.md` — reorganized and indexed
- `ROADMAP.md` — this file
- Updated `AGENTS.md`

---

## What OpenClaw Has That Clambda Needs

Listed in priority order for the full rewrite:

### Priority 1 — Core Agent Infrastructure

#### ✅ 1.1 Session Persistence
**What:** Save/load conversation history as JSON files (one per session).
**Status:** Done. `save-session` / `load-session` in `clambda/session`.

#### ✅ 1.2 Memory System
**What:** Daily notes, knowledge base, project state — loaded at startup.
**Status:** Done. `clambda/memory` — `load-workspace-memory`, `memory-context-string`, `search-memory`.
Priority files (SOUL.md, AGENTS.md, etc.) loaded first.

#### 1.3 Skills System
**What:** Load SKILL.md files, inject tool definitions and instructions.
**Why:** OpenClaw's skill system allows capability extension without code changes.
**Approach:** `clambda/skills` — scans skills dir, loads SKILL.md, registers described tools.
**Effort:** Medium-Large (3–5 days)

---

### Priority 2 — Multi-Agent / Orchestration

#### 2.1 Sub-agent Spawning
**What:** Spawn a child agent in a new thread/process, get result back.
**Why:** OpenClaw uses subagents for delegation (coding tasks, research, etc.).
**Approach:** `clambda/subagents` — wrap `bt:make-thread` + new session + result callback.
**Effort:** Medium (2–3 days)

#### 2.2 Agent Registry
**What:** Named agents with defined capabilities and system prompts.
**Why:** Multi-agent orchestration needs a way to route tasks to the right agent.
**Approach:** Global `*agent-registry*` alist; `(find-agent :researcher)` etc.
**Effort:** Small (1 day)

---

### Priority 3 — I/O Channels

#### 3.1 Structured Output / Message Routing
**What:** Route agent output to different channels (file, socket, HTTP endpoint).
**Why:** OpenClaw has channel plugins for Discord, Telegram, webchat, etc.
**Approach:** `clambda/channels` protocol — `send-message`, `recv-message` generics.
**Effort:** Medium (2–3 days)

#### 3.2 REST API / Webhook Receiver
**What:** HTTP server that accepts inbound messages and dispatches to agent.
**Why:** Needed for channel integrations, webhooks, external triggers.
**Approach:** Use `hunchentoot` or `woo` for HTTP; route to session dispatcher.
**Effort:** Medium (2–4 days)

---

### Priority 4 — Extended Tools

#### ✅ 4.1 Web Fetch Tool
**What:** Built-in tool to fetch and extract readable content from a URL.
**Status:** Done. `web_fetch` in `clambda/builtins`. Uses dexador + cl-ppcre HTML stripping.

#### 4.2 Browser Control
**What:** Drive a headless browser (screenshots, clicks, form fills).
**Why:** OpenClaw has browser automation for web tasks.
**Approach:** Wrap `cl-selenium` or call `playwright` via shell.
**Effort:** Large (1–2 weeks)

#### ✅ 4.3 TTS Output
**What:** Text-to-speech for voice output.
**Status:** Done. `tts` built-in tool in `clambda/builtins`. Shells out to `espeak-ng`, `espeak`,
`piper`, or `say` (checked at runtime). Graceful no-op if none available.

---

### Priority 5 — Production Hardening

#### ✅ 5.1 Retry / Backoff
**What:** Retry transient HTTP errors with exponential backoff.
**Status:** Done. `cl-llm/http` — `post-json` and `post-json-stream` retry on 429/500/502/503/504.
Exponential backoff. Configurable `*max-retries*` (default 3) and `*retry-base-delay-seconds*` (default 1).
`retryable-error` condition with `retry` restart.

#### ✅ 5.2 Token Budget / Turn Limits
**What:** Hard limits on tokens and turns per session.
**Status:** Done. `session-total-tokens` slot tracks cumulative usage. `loop-options` accepts
`:max-tokens` and `:max-turns`. `budget-exceeded` condition signalled when limit hit.
`:max-turns` was already implemented; `:max-tokens` added in Layer 5 Phase 3.

#### ✅ 5.3 Structured Logging
**What:** JSON logs of all agent activity (requests, tool calls, results).
**Status:** Done. `clambda/logging` module — JSONL output, `with-logging` macro, configurable path.
Wired into agent loop (LLM requests, tool calls, tool results) and HTTP server (requests, responses, errors).
Default log file: `logs/clambda.jsonl` relative to process working directory.

---

## Known Gaps and Risks

| Gap | Risk | Mitigation |
|-----|------|-----------|
| ~~No session persistence~~ | ~~Agent loses state on restart~~ | ✅ Done: `save-session`/`load-session` |
| McCLIM thread safety | Possible redisplay race conditions | Use event queue; move to CLIM's redisplay queue |
| Tool schema not validated | LLM may call tools with wrong types | Add schema validator in tool dispatch |
| ~~`*on-stream-delta*` not re-exported~~| ~~Downstream packages break subtly~~ | ✅ Done: now exported from `clambda` |
| No error recovery in agent loop | One bad tool call can break session | Add condition-based restart in `agent-turn` |
| LM Studio models change | Hardcoded model names go stale | Store model config in workspace file |
| Guix LD_LIBRARY_PATH | Fresh shells break dexador | Add to workspace startup script |
| ~~No retry/backoff~~ | ~~Transient errors kill sessions~~ | ✅ Done: exponential backoff in `cl-llm/http` |
| `tool-result-ok` naming collision | `format-tool-result` always shows value w/o ERROR: | Rename slot or constructor (low priority) |

---

## ✅ Layer 5 Complete — Production Hardening

All Layer 5 tasks complete as of 2026-02-26:

1. ✅ **Fix `*on-stream-delta*` re-export** in `clambda` package
2. ✅ **Session persistence** — `save-session` / `load-session` (JSON, one file per session)
3. ✅ **Memory loading** — `clambda/memory` module, `load-workspace-memory`, `memory-context-string`
4. ✅ **Web fetch builtin** — `web_fetch` in `clambda/builtins` (dexador + cl-ppcre HTML stripping)
5. ✅ **Structured logging** — `clambda/logging` module, JSONL to configurable file, `with-logging` macro
6. ✅ **Sub-agent spawning** — `clambda/subagents`, `spawn-subagent`, `subagent-wait`
7. ✅ **Agent/session registry** — `clambda/registry`, `define-agent`, `find-agent`
8. ✅ **Channel protocol** — `clambda/channels`, `repl-channel`, `queue-channel`
9. ✅ **HTTP API server** — `clambda/http-server`, `/chat`, `/agents`, `/sessions` endpoints
10. ✅ **TTS output tool** — `tts` builtin, graceful no-op if no TTS engine available
11. ✅ **Retry/backoff** — `cl-llm/http` exponential backoff, `retryable-error` condition
12. ✅ **Token budget** — `session-total-tokens`, `loop-options :max-tokens`, `budget-exceeded` condition
13. ✅ **Logging wired in** — agent loop, tool dispatch, and HTTP server all emit JSONL log entries
14. ✅ **Full integration test** — `projects/clambda-core/integration-test.lisp`, 12/12 tests pass

Clambda is now functionally comparable to the core of OpenClaw, minus channel plugins and browser control.

---

## ✅ Layer 6a Complete — Emacs-Style Configuration System

All Layer 6a tasks complete as of 2026-02-26:

1. ✅ **`clambda/config` module** — new `src/config.lisp`, loaded last in clambda-core
2. ✅ **`*clambda-home*`** — resolved from `$CLAMBDA_HOME` or `~/.clambda/`, setf-able
3. ✅ **`load-user-config`** — finds and loads `init.lisp` in `clambda-user` package;
   catches/reports errors without crashing; returns T on success, NIL on miss/error
4. ✅ **`defoption` macro** — Emacs defcustom analog; DEFVAR + option registry entry;
   all options setf-able from init.lisp
5. ✅ **Built-in options** — `*default-model*`, `*default-max-turns*`, `*default-stream*`,
   `*log-level*`, `*startup-message*` — all registered in `*option-registry*`
6. ✅ **`describe-options`** — prints all known options with types, current values, docs
7. ✅ **Hook system** — `add-hook`, `remove-hook`, `run-hook`, `run-hook-with-args`;
   error isolation per hook fn; standard hook vars:
   `*after-init-hook*`, `*before-agent-turn-hook*`, `*after-tool-call-hook*`, `*channel-message-hook*`
8. ✅ **`register-channel` generic** — default method stores config in `*registered-channels*`;
   channel plugins add EQL-specialised methods to start their transport
9. ✅ **`define-user-tool` macro** — keyword-style tool definition (name, description,
   parameters plist, function); registers into `*user-tool-registry*`
10. ✅ **`merge-user-tools!`** — copies all user tools from `*user-tool-registry*` into
    any target registry (call at agent-creation time)
11. ✅ **`clambda-user` package** — default `*package*` for init.lisp; imports all config
    and core API symbols; no sandboxing, full CL available
12. ✅ **`example-init.lisp`** — fully commented example covering all features
13. ✅ **24/24 integration tests** in `t/test-config.lisp` — all pass
14. ✅ **`clambda-core.asd` updated** to v0.4.0; `src/config` added as last component
15. ✅ **`clambda` package updated** — all config symbols re-exported

## ✅ Layer 6b Complete — Telegram Bot API Channel

All Layer 6b tasks complete as of 2026-02-26:

1. ✅ **`clambda/telegram` module** — `src/telegram.lisp`; loaded after `src/config`
2. ✅ **Long-polling loop** — `bt:make-thread`; `getUpdates` with 5s timeout for responsive shutdown
3. ✅ **Bot API HTTP client** — dexador + jzon; `getUpdates`, `sendMessage`, `getMe`
4. ✅ **Message routing** — per-chat-id session hash-table; `find-or-create-session`; `run-agent` → `sendMessage`
5. ✅ **Markdown support** — `sendMessage` with `parse_mode: "Markdown"` by default
6. ✅ **`register-channel :telegram`** — EQL-specialised method on config generic; stores config + sets `*telegram-channel*`; does NOT auto-start
7. ✅ **`start-telegram` / `stop-telegram`** — start/stop the background polling thread
8. ✅ **Allowlist enforcement** — `:allowed-users` list; silently reject unlisted user-IDs
9. ✅ **Graceful shutdown** — `running` flag; thread exits after current poll completes (≤ `*telegram-poll-timeout*` seconds)
10. ✅ **Error handling** — network/parse errors in polling loop → log + sleep + retry, no crash
11. ✅ **`start-all-channels`** — iterates `*registered-channels*`, starts all telegram channels
12. ✅ **Configurable options** — `*telegram-llm-base-url*`, `*telegram-llm-api-key*`, `*telegram-system-prompt*`, `*telegram-poll-timeout*`
13. ✅ **39/39 unit tests** — URL construction, allowlist logic, message field extraction, mock update routing; all pass
14. ✅ **`clambda-core.asd` updated** to v0.5.0; `src/telegram` component added; test file added
15. ✅ **`clambda` + `clambda-user` packages updated** — all telegram symbols re-exported

---

## ✅ Layer 6c Complete — IRC Client Channel

All Layer 6c tasks complete as of 2026-02-26:

1. ✅ **`clambda/irc` module** — `src/irc.lisp` (raw sockets, no external IRC library)
2. ✅ **Raw IRC protocol** — `usocket` for TCP, `cl+ssl` for TLS
3. ✅ **IRC protocol primitives:**
   - `parse-irc-line` — parser returning `(:prefix :command :params :trailing)` plist
   - `irc-build-line` — line builder (command + params + trailing)
   - `prefix-nick` — extract nick from `nick!user@host` prefix
4. ✅ **Full registration flow** — NICK, USER, auto-JOIN after RPL_WELCOME (001)
5. ✅ **NickServ IDENTIFY** — sent after 001 if `nickserv-password` configured
6. ✅ **PING/PONG keepalive** — server PINGs dispatched immediately
7. ✅ **CTCP VERSION response** — replies with version string
8. ✅ **Message routing** — PRIVMSG → trigger check → find/create session → `run-agent` → PRIVMSG reply
9. ✅ **Trigger detection** — nick mention or `nick:` prefix for channels; any message for DMs
10. ✅ **Flood protection** — background flood-sender thread, 2 msg/sec max (`*irc-send-interval*` = 0.5s)
11. ✅ **Reconnection** — exponential backoff on disconnect (5s → 10s → 20s … max 300s)
12. ✅ **Nick collision handling** — 433/436 → append `_` and retry
13. ✅ **Response splitting** — long responses split into multiple PRIVMSGs at word boundaries (max 400 chars)
14. ✅ **Allowed-users** — optional nick allowlist per connection
15. ✅ **`register-channel :irc`** — EQL-specialised method; stores config, user calls `start-irc`
16. ✅ **`start-irc` / `stop-irc`** — lifecycle; graceful QUIT on disconnect
17. ✅ **`clambda-core.asd` updated** — v0.6.0; `usocket` + `cl+ssl` deps; `src/irc` component
18. ✅ **87/87 unit tests** in `t/test-irc.lisp` — all pass
    - IRC line parser (11 tests)
    - IRC line builder (9 tests)
    - prefix-nick extraction (5 tests)
    - Flood queue mechanics (2 tests)
    - Trigger/message-body extraction (7 tests)
    - Response splitting (4 tests)
    - Struct construction (3 tests)
    - Allowed-users (1 test)
    - Round-trip parse/build (2 tests)

---

## What's Left

### For Channel Plugins (Discord, etc.)

1. **Discord channel** — `clambda/channels/discord.lisp`
   - Use Discord REST API + gateway WebSocket for real-time
   - Effort: Large (1 week+, WebSocket dependency needed)

2. **Skills system** — `clambda/skills`
   - Scan a skills directory for `SKILL.md` files
   - Parse tool definitions from skill metadata
   - Inject skill instructions into agent system prompt
   - Effort: Medium (2–3 days)

3. **Browser control** — `clambda/browser`
   - Shell out to Playwright or Puppeteer (Node.js)
   - Or wrap a headless browser library
   - Effort: Large (1–2 weeks)

4. **Cron / scheduled tasks** — `clambda/cron`
   - Periodic agent triggers
   - Integrate with bordeaux-threads sleep-loop or a proper scheduler
   - Effort: Small-Medium (1–2 days)
