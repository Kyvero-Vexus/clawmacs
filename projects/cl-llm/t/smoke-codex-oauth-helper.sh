#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/node/codex_oauth_helper.mjs"

if [[ ! -f "$HELPER" ]]; then
  echo "FAIL: helper missing: $HELPER" >&2
  exit 1
fi

PAYLOAD='{"prompt":"Reply with: oauth_helper_ok","model":"gpt-5.3-codex","system":"You are a terse test assistant."}'
OUT="$(printf '%s' "$PAYLOAD" | node "$HELPER")"
echo "$OUT"

echo "$OUT" | grep -q '"ok":true' || { echo "FAIL: helper did not return ok=true" >&2; exit 1; }
echo "$OUT" | grep -q '"provider":"openai-codex"' || { echo "FAIL: provider not openai-codex" >&2; exit 1; }
echo "$OUT" | grep -q '"api":"openai-codex-responses"' || { echo "FAIL: api not openai-codex-responses" >&2; exit 1; }

echo "PASS: codex oauth helper used openai-codex responses runtime (non API-key chat/completions path)."
