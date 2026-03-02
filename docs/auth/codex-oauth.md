# Codex OAuth (No Codex CLI Required)

Clawmacs supports a native browser-link OAuth flow for Codex/OpenAI endpoints.

## What changed

- ✅ No `codex` CLI dependency
- ✅ Login URL generated in bot via `/codex_login`
- ✅ Paste redirect URL into `/codex_link <redirect-url>`
- ✅ Tokens stored locally at `~/.clawmacs/auth/codex-oauth.json` (mode `0600`)
- ✅ Auto-refresh with refresh token during runtime

## init.lisp configuration

```lisp
(in-package #:clawmacs-user)

(setf clawmacs/telegram:*telegram-llm-api-type* :codex-oauth)
(setf cl-llm:*codex-oauth-client-id* "YOUR_OAUTH_CLIENT_ID")
(setf *default-model* "gpt-5-codex")
```

Optional endpoint overrides:

```lisp
(setf cl-llm:*codex-oauth-authorize-endpoint* "https://auth.openai.com/oauth/authorize")
(setf cl-llm:*codex-oauth-token-endpoint* "https://auth.openai.com/oauth/token")
(setf cl-llm:*codex-oauth-redirect-uri* "https://localhost/callback")
```

## Telegram login flow

1. Send `/codex_login`
2. Open the returned URL and approve access
3. Copy the full redirect URL from your browser
4. Send `/codex_link <redirect-url>`
5. Verify with `/codex_status`

Accepted `/codex_link` payloads:
- full redirect URL containing `?code=...&state=...`
- `code#state` blob

## Troubleshooting

### `Codex OAuth client id missing`
Set `cl-llm:*codex-oauth-client-id*` in `init.lisp`.

### `OAuth state mismatch`
Run `/codex_login` again and use the newest redirect.

### `Malformed input`
Paste the full redirect URL exactly as copied from browser.

### Expired token
Refresh is automatic if a refresh token exists. If refresh fails, relink using `/codex_login` + `/codex_link`.

## Security notes

- Token file path: `~/.clawmacs/auth/codex-oauth.json`
- File permissions forced to `0600` on save
- Raw tokens are not printed in status output
- Re-running link overwrites previous stored session (rotation supported)
