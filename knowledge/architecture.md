# Clambda Architecture Overview

> How the 4 completed projects fit together and form the foundation for the
> full OpenClaw rewrite. Updated after Layer 4.

---

## 1. System Dependency Graph

```
                    clambda-gui
                       │
                       │ :depends-on
                       ▼
              ┌── clambda-core ──┐
              │                  │
              │ :depends-on      │ :depends-on
              ▼                  │
           cl-llm             cl-tui (standalone TUI)
              │
              │ :depends-on
              ▼
       (Quicklisp libs)
       dexador, jzon,
       alexandria, cl-ppcre
```

**Leaf → root order:** `cl-llm` → `cl-tui` | `clambda-core` → `clambda-gui`

### Direct dependency table

| System | Depends On |
|--------|-----------|
| `cl-llm` | `dexador`, `com.inuoe.jzon`, `alexandria`, `cl-ppcre` |
| `cl-tui` | `cl-llm`, `alexandria`, `cl-ppcre` |
| `clambda-core` | `cl-llm`, `alexandria`, `com.inuoe.jzon`, `uiop` |
| `clambda-gui` | `clambda-core`, `cl-llm`, `mcclim`, `bordeaux-threads` |

---

## 2. Layer Descriptions

### Layer 1: `cl-llm` — LLM API Client

**Purpose:** Talk to any OpenAI-compatible API (LM Studio, Ollama, OpenRouter).

**Packages:**
- `cl-llm/protocol` — structs: `client`, `completion-response`, `tool-definition`, `tool-call`, `chat-message`
- `cl-llm/conditions` — `network-error`, `parse-error`
- `cl-llm/json` — `plist->object` (shallow), `object->plist`
- `cl-llm/http` — `post-json`, `post-json-stream` (wraps dexador)
- `cl-llm/streaming` — `parse-sse-line`, `chat-stream`
- `cl-llm/client` — `make-client`, `chat`, `chat-stream`
- `cl-llm/tools` — `make-tool-definition`
- `cl-llm` — public re-export surface

**Key interfaces:**
```lisp
;; Create a client
(cl-llm:make-client :base-url "..." :api-key "..." :model "...")

;; Non-streaming chat → returns string
(cl-llm:chat client messages)

;; Streaming chat → calls callback with each delta, returns full string
(cl-llm:chat-stream client messages callback)

;; Tool definitions for the API
(cl-llm:make-tool-definition :name "..." :description "..." :parameters ht)
```

---

### Layer 2a: `cl-tui` — Terminal UI Chat

**Purpose:** ANSI terminal chat interface using `cl-llm`. Standalone.

**Packages:**
- `cl-tui/ansi` — ANSI escape code constants and helpers
- `cl-tui/state` — `app` struct, global `*app*`
- `cl-tui/display` — print functions, streaming token display
- `cl-tui/commands` — slash command dispatch
- `cl-tui/loop` — main REPL loop
- `cl-tui` — public surface

**Key interfaces:**
```lisp
;; Entry point
(cl-tui:run &key model system-prompt)
```

**Architecture notes:**
- Single-threaded (no background threads)
- Streaming via `cl-llm:chat-stream` + `force-output` per token
- State in `*app*` global (mutable, but single-threaded so safe)
- Slash commands: `/model`, `/system`, `/clear`, `/quit`

---

### Layer 2b: `clambda-core` — Agent Platform

**Purpose:** Multi-turn agent loop with tool execution. Powers both TUI and GUI agents.

**Packages:**
- `clambda/agent` — `agent` struct: name, client, tool-registry, system-prompt
- `clambda/session` — `session` struct: agent + message history
- `clambda/tools` — `tool-registry`, `register-tool!`, `define-tool` macro, `schema-plist->ht`
- `clambda/builtins` — pre-built tools: `exec`, `read_file`, `write_file`, `list_dir`
- `clambda/loop` — `run-agent`, `agent-turn`; hook variables `*on-tool-call*`, `*on-tool-result*`, `*on-llm-response*`, `*on-stream-delta*`
- `clambda/conditions` — `tool-error`, `agent-error`
- `clambda` — public surface

**Key interfaces:**
```lisp
;; Build an agent
(clambda:make-agent :name "bot" :client client :tool-registry registry)

;; Create a session (holds conversation history)
(clambda:make-session :agent agent)

;; Register tools
(clambda:register-tool! registry "name" handler-fn :description "..." :parameters schema)
(clambda:define-tool registry "name" "desc" ((param-specs)) body...)

;; Run the agent loop
(clambda:run-agent session user-message :options opts)

;; Hook variables (setf before run-agent)
clambda/loop:*on-stream-delta*   ; lambda (delta) — called per streaming token
clambda:*on-tool-call*           ; lambda (name tc) — called when tool invoked
clambda:*on-tool-result*         ; lambda (name result) — called after tool runs
clambda:*on-llm-response*        ; lambda (text) — called with final LLM text
```

**Agent loop flow:**
```
run-agent
  │
  ├── add user message to session history
  │
  └── loop (up to max-turns):
        agent-turn
          │
          ├── call cl-llm:chat (with tools)
          │     └── returns (text tool-calls response)
          │
          ├── if no tool-calls → return text (done)
          │
          └── for each tool-call:
                execute tool from registry
                add tool-result to session
                → loop again
```

---

### Layer 3: `clambda-gui` — McCLIM GUI Frontend

**Purpose:** Windowed chat UI using McCLIM, threaded LLM calls, streaming display.

**Packages:**
- `clambda-gui/colors` — ink constants and role→color mapping
- `clambda-gui/chat-record` — `chat-message` struct (role, content, timestamp)
- `clambda-gui/frame` — `clambda-frame` definition, pane layout, slots
- `clambda-gui/display` — display functions for each pane
- `clambda-gui/commands` — CLIM command table (Send, Clear, Quit)
- `clambda-gui/main` — `run-gui` entry point

**Key interfaces:**
```lisp
;; Launch the GUI (blocks until window closes)
(clambda-gui:run-gui &key session width height)

;; Inside the frame, messages pushed via:
(push-chat-message frame :user "Hello")
(push-chat-message frame :assistant "Hi there")
(push-chat-message frame :system "Tool result: ...")
```

**Threading model:**
- Main thread: McCLIM event loop (`run-frame-top-level`)
- LLM calls: `bordeaux-threads` worker thread per request
- Streaming tokens: worker thread calls `safe-redisplay` to update display pane
- Only one worker at a time (guarded by `frame-worker` slot check)

---

## 3. Key Interfaces Between Layers

### cl-llm → clambda-core

`clambda-core` uses `cl-llm` for all LLM communication:
- `cl-llm:make-client` → stored in `agent` struct
- `cl-llm:chat` / `cl-llm:chat-stream` → called by `agent-turn`
- `cl-llm:make-tool-definition` → used when serializing registry to API
- `cl-llm/protocol` structs: `chat-message`, `tool-call`, `completion-response`

### clambda-core → clambda-gui

`clambda-gui` embeds a `clambda-core` session:
- `clambda:make-session` stored in frame slot
- `clambda:run-agent` called from worker thread
- Hook variables set before run:
  - `*on-stream-delta*` → `push-streaming-token frame delta` → `safe-redisplay`
  - `*on-tool-call*` → `push-chat-message frame :system ...`
  - `*on-llm-response*` → `push-chat-message frame :assistant text`

### cl-llm → cl-tui

`cl-tui` uses `cl-llm` directly (no clambda-core):
- `cl-llm:make-client` → stored in `app` struct
- `cl-llm:chat-stream` → called in main loop, token callback → `print-token`

---

## 4. Data Flow: User Message to Response

### In cl-tui (simple, single-threaded)

```
User types text
  │
  └── cl-tui/loop:handle-message
        │
        └── cl-llm:chat-stream client messages
              │ (calls callback per SSE chunk)
              └── print-token → write-string + force-output
                  (streaming display)
```

### In clambda-gui + clambda-core (multi-turn, threaded)

```
User enters command "Send <text>"
  │
  └── climbda-gui/commands:com-send
        │
        └── run-llm-async frame text
              │
              └── bt:make-thread
                    │
                    └── run-agent session text
                          │
                          ├── *on-stream-delta* → safe-redisplay (streaming tokens)
                          ├── tool-call → execute → *on-tool-call* + *on-tool-result*
                          └── final text → *on-llm-response* → push-chat-message
```

---

## 5. Extension Points for OpenClaw Rewrite

### What's already implemented

| OpenClaw Feature | CL Equivalent | Status |
|-----------------|---------------|--------|
| LLM API client | `cl-llm` | ✅ Complete |
| Streaming SSE | `cl-llm/streaming` | ✅ Complete |
| Tool protocol | `clambda/tools` | ✅ Complete |
| Agent loop | `clambda/loop` | ✅ Complete |
| Built-in tools (exec, file ops) | `clambda/builtins` | ✅ Complete |
| TUI chat | `cl-tui` | ✅ Complete |
| GUI chat | `clambda-gui` | ✅ Complete |

### What OpenClaw has that Clambda needs

| OpenClaw Feature | CL Gap | Priority |
|-----------------|--------|---------|
| Skills system (SKILL.md loading) | Not implemented | High |
| Sub-agent spawning | Not implemented | High |
| Channel plugins (Discord, Telegram) | Not implemented | Medium |
| Message routing / sessions | Partial (session history only) | Medium |
| Web browser control | Not implemented | Low |
| Canvas / UI presentation | Not implemented | Low |
| Node pairing (mobile/devices) | Not implemented | Low |
| TTS output | Not implemented | Low |
| Cron / scheduled tasks | Not implemented | Medium |
| Memory persistence (markdown files) | Not implemented | High |
| Multi-model routing | Not implemented | Medium |

### Natural extension points

1. **New tools** → `(clambda:register-tool! registry ...)` in `clambda/builtins.lisp`
2. **New backends** → implement `cl-llm:make-client` pattern for Anthropic, etc.
3. **New frontends** → create new ASDF system, depend on `clambda-core`, use hooks
4. **Skills** → load SKILL.md, inject instructions into system prompt, register tools
5. **Sub-agents** → `clambda-core` already models session isolation; spawn via `bt:make-thread`

---

## 6. Known Architectural Gaps

1. **No persistence** — session history is in-memory only; lost on process exit
2. **No multi-agent coordination** — no message passing between agent instances
3. **Tool schema validation** — parameters accepted but not validated against schema
4. **No streaming tool calls** — tool calls are only parsed from complete responses
5. **Thread safety** — McCLIM redisplay from worker threads needs care; `safe-redisplay` is a workaround not a solution
6. **No retry/backoff** — HTTP errors propagate immediately; no exponential backoff
