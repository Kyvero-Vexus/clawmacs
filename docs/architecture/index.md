# Architecture Overview

Clawmacs is layered. Each layer builds on lower layers.

## Dependency shape

```text
                    clawmacs-gui (Layer 3)
                         │
                         ▼
                  clawmacs-core (Layer 2b)
                    │             │
                    │             └── cl-tui (Layer 2a)
                    ▼
                 cl-llm (Layer 1)
```

Core Quicklisp/runtime dependencies include: `dexador`, `jzon`, `alexandria`,
`cl-ppcre`, `usocket`, `cl+ssl`, `hunchentoot`, `bordeaux-threads`.

## Layer 1: cl-llm

OpenAI-compatible chat client with streaming and tool-call payload support.

## Layer 2a: cl-tui

Terminal chat interface (ASDF system: `cl-tui`).

## Layer 2b: clawmacs-core

Agent runtime: sessions, tool registry, built-in tools, channels, hooks,
subagents, HTTP API, configuration loader.

Source tree path in this repo is currently:

- `projects/clambda-core/` (directory)
- `clawmacs-core` (ASDF system name)

## Layer 3: clawmacs-gui

Optional McCLIM frontend.

Source tree path in this repo is currently:

- `projects/clambda-gui/` (directory)
- `clawmacs-gui` (ASDF system name)

## Runtime flow (high-level)

1. Inbound message arrives (CLI/channel/API)
2. Session history updated
3. LLM call performed
4. Tool calls dispatched if requested
5. Tool results appended and loop continues
6. Final assistant response emitted

## Extension points

- Register custom tools
- Add hooks (`*after-init-hook*`, `*before-agent-turn-hook*`, etc.)
- Register channels
- Start management API for remote control

## Status

The architecture and core systems load and run; naming migration is in progress,
which is why directory names (`clambda-*`) and system names (`clawmacs-*`) differ.
