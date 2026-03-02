# Codex OAuth (Bridge Runtime)

Clawmacs keeps `/codex_login` + `/codex_link` browser OAuth UX, but runtime no longer uses direct `api.openai.com/v1/chat/completions` for `:codex-oauth`.

## Runtime transport (important)

For `:codex-oauth` requests:
1. Primary: **Node OAuth helper** (`projects/cl-llm/node/codex_oauth_helper.mjs`) using `@mariozechner/pi-ai` `openai-codex-responses` runtime.
2. Secondary fallback (optional): Claude CLI transport with explicit warning in the model reply.

Primary runtime is non-CLI Codex OAuth (no `codex` binary required) and avoids direct `api.openai.com/v1/chat/completions` API-key quota/billing path.

## init.lisp configuration

```lisp
(in-package #:clawmacs-user)

(setf clawmacs/telegram:*telegram-llm-api-type* :codex-oauth)
(setf cl-llm:*codex-oauth-client-id* "YOUR_OAUTH_CLIENT_ID")
(setf *default-model* "gpt-5-codex")
```

Optional: disable interim fallback (strict mode)

```lisp
(setf cl-llm:*codex-oauth-fallback-enabled* nil)
```

## Telegram login flow

1. Send `/codex_login`
2. Open the returned URL and approve access
3. Copy the full redirect URL
4. Send `/codex_link <redirect-url>`
5. Verify with `/codex_status`

## Known runtime characteristics

- Streaming for `:codex-oauth` bridge currently emits final text as one chunk.
- If Node helper runtime fails and fallback is enabled, response is prefixed with a warning.
- Helper reads/writes `~/.clawmacs/auth/codex-oauth.json` (and refreshes token when needed).

## Troubleshooting

### Node helper runtime unavailable
- Verify helper exists: `projects/cl-llm/node/codex_oauth_helper.mjs`
- Verify OAuth store has tokens: `~/.clawmacs/auth/codex-oauth.json`
- Re-link via `/codex_login` + `/codex_link`, then retry

### OAuth state mismatch
Run `/codex_login` again and use the latest redirect URL.

### Missing/expired OAuth
Relink via `/codex_login` + `/codex_link`.

## Security notes

- OAuth session file: `~/.clawmacs/auth/codex-oauth.json` (`0600`)
- Tokens are not printed in status output
