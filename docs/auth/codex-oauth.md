# Codex OAuth in Clawmacs

Use this when you want Clawmacs to talk to Codex through an OAuth-linked CLI session instead of storing an API key in `init.lisp`.

## 1) Prerequisites

- `codex` CLI installed and available on `PATH`
- Clawmacs checkout + SBCL/Quicklisp working
- A model compatible with your Codex account (example: `gpt-5-codex`)

Check CLI availability:

```bash
codex --help
```

## 2) Link/login flow

Authenticate the CLI with OAuth:

```bash
codex login
```

Follow the browser/device prompts until the CLI reports success.

## 3) Where session credentials are stored

Clawmacs mirrors OpenClaw behavior and auto-discovers the Codex OAuth session from the local Codex CLI state directory, typically under:

```text
~/.codex/
```

Common files detected by Clawmacs include:
- `~/.codex/auth.json`
- `~/.codex/credentials.json`
- `~/.codex/token.json`
- `~/.codex/config.json`

(Exact file names are CLI-managed and may vary by Codex version.)

## 4) Required `init.lisp` config

Set Clawmacs to use the Codex CLI backend explicitly:

```lisp
(in-package #:clawmacs-user)

(setf clawmacs/telegram:*telegram-llm-api-type* :codex-cli)
(setf clawmacs/telegram:*telegram-codex-auth-mode* :oauth-session)
(setf *default-model* "gpt-5-codex")
```

`*telegram-llm-api-key*` is ignored for `:codex-cli` mode; OAuth session is used automatically.

If you build clients directly, use:

```lisp
(cl-llm:make-codex-cli-client :model "gpt-5-codex")
```

## 5) Verification

First verify CLI auth outside Clawmacs:

```bash
codex exec --json --model gpt-5-codex "Reply with: oauth-ok"
```

Then verify diagnostics in Clawmacs:

```bash
sbcl --eval '(ql:quickload :clawmacs-core)' \
     --eval '(format t "~A~%" (cl-llm:codex-auth-status-string :model "gpt-5-codex"))' \
     --quit
```

In Telegram sessions, you can also check:
- `/status` (includes Codex CLI + OAuth linked/missing when in `:codex-cli` mode)
- `/codex_auth_status` (full diagnostics + remediation commands)

## 6) Troubleshooting

### "Codex CLI failed" / no output

- Ensure `codex` is installed and on `PATH`
- Re-run `codex login`
- Retry the standalone verification command above

### Expired or invalid OAuth session

Re-authenticate:

```bash
codex login
```

### Wrong auth mode in Clawmacs

If Clawmacs still tries HTTP provider auth, ensure:

```lisp
(setf clawmacs/telegram:*telegram-llm-api-type* :codex-cli)
```

and restart the running channel/session.
