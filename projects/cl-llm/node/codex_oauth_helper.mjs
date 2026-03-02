#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const PI_AI_DIST = process.env.PI_AI_DIST || "/home/slime/.npm-global/lib/node_modules/openclaw/node_modules/@mariozechner/pi-ai/dist/index.js";

function readStdin() {
  return new Promise((resolve, reject) => {
    let buf = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (d) => (buf += d));
    process.stdin.on("end", () => resolve(buf));
    process.stdin.on("error", reject);
  });
}

function detectStorePath() {
  const explicit = process.env.CODEX_OAUTH_STORE_PATH;
  if (explicit) return explicit;
  const home = os.homedir();
  const candidates = [
    path.join(home, ".clawmacs", "auth", "codex-oauth.json"),
    path.join(home, ".config", "clawmacs", "auth", "codex-oauth.json"),
    path.join(home, ".codex", "auth.json"),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return candidates[0];
}

function parseStore(raw) {
  if (!raw || typeof raw !== "object") return { format: "unknown", creds: null };
  if (raw["openai-codex"] && typeof raw["openai-codex"] === "object") {
    return { format: "pi-ai", creds: raw["openai-codex"] };
  }
  if (typeof raw.access_token === "string") {
    return {
      format: "clawmacs",
      creds: {
        type: "oauth",
        access: raw.access_token,
        refresh: raw.refresh_token,
        expires: typeof raw.expires_at === "number" ? raw.expires_at * 1000 : undefined,
        accountId: raw.account_id,
      },
    };
  }
  return { format: "unknown", creds: null };
}

function saveStore(storePath, format, raw, creds) {
  let next;
  if (format === "pi-ai") {
    next = { ...(raw || {}), "openai-codex": creds };
  } else {
    next = { ...(raw || {}) };
    next.linked = true;
    next.updated_at = Math.floor(Date.now() / 1000);
    next.access_token = creds.access;
    next.refresh_token = creds.refresh;
    if (typeof creds.expires === "number") next.expires_at = Math.floor(creds.expires / 1000);
    next.account_id = creds.accountId;
  }
  fs.mkdirSync(path.dirname(storePath), { recursive: true });
  fs.writeFileSync(storePath, JSON.stringify(next, null, 2), { mode: 0o600 });
}

function normalizeMessages(messages) {
  const out = [];
  for (const m of messages || []) {
    const role = (m?.role || "user").toLowerCase();
    const content = String(m?.content ?? "");
    if (role === "assistant") out.push({ role: "assistant", content: [{ type: "text", text: content }] });
    else out.push({ role: "user", content: [{ type: "text", text: content }] });
  }
  return out;
}

async function main() {
  try {
    const input = JSON.parse((await readStdin()) || "{}");
    const modelId = input.model || "gpt-5.3-codex";
    const system = input.system || "";
    const prompt = input.prompt || "";
    const messages = normalizeMessages(input.messages || (prompt ? [{ role: "user", content: prompt }] : []));

    const storePath = detectStorePath();
    if (!fs.existsSync(storePath)) throw new Error(`OAuth store missing: ${storePath}`);
    const raw = JSON.parse(fs.readFileSync(storePath, "utf8"));
    const parsed = parseStore(raw);
    if (!parsed.creds?.access) throw new Error(`No usable openai-codex OAuth credentials in ${storePath}`);

    const pi = await import(pathToFileURL(PI_AI_DIST).href);

    let creds = parsed.creds;
    const expiresSoon = typeof creds.expires === "number" && creds.expires <= Date.now() + 30_000;
    if (expiresSoon && creds.refresh) {
      creds = await pi.refreshOpenAICodexToken(creds.refresh);
      saveStore(storePath, parsed.format, raw, creds);
    }

    const model = pi.getModel("openai-codex", modelId);
    const context = { systemPrompt: system, messages };
    const result = await pi.complete(model, context, {
      apiKey: creds.access,
      maxTokens: input.maxTokens,
      reasoning: "low",
      textVerbosity: "medium",
    });

    const textBlocks = (result?.content || []).filter((c) => c?.type === "text").map((c) => c.text || "");
    const text = textBlocks.join("").trim();
    if (!text) throw new Error("Empty completion text from openai-codex runtime");

    process.stdout.write(
      JSON.stringify({
        ok: true,
        text,
        model: result?.model || modelId,
        provider: "openai-codex",
        api: "openai-codex-responses",
        storePath,
      }),
    );
  } catch (err) {
    process.stdout.write(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : String(err) }));
    process.exitCode = 1;
  }
}

main();
