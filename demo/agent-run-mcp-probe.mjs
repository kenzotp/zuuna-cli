#!/usr/bin/env node
// A real MCP client session against the published mcp-server-zuuna (npm,
// stdio transport): initialize -> tools/list -> tools/call zuuna_me.
//
// The API token arrives via ZUUNA_API_TOKEN and is never printed; the only
// values on screen are what the server itself announces. This is the same
// interface any coding agent (ZCode, Claude Code, Cursor, ...) drives.
import { spawn } from "node:child_process";

if (!process.env.ZUUNA_API_TOKEN) {
  console.error("ZUUNA_API_TOKEN not set");
  process.exit(1);
}

const child = spawn("npx", ["-y", "mcp-server-zuuna"], {
  env: { ...process.env },
  stdio: ["pipe", "pipe", "ignore"],
});

let buf = "";
const pending = new Map();
let nextId = 1;

child.stdout.on("data", (d) => {
  buf += d.toString();
  let idx;
  while ((idx = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.id && pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    } catch {
      /* not JSON — ignore */
    }
  }
});

function rpc(method, params) {
  const id = nextId++;
  const p = new Promise((res) => pending.set(id, res));
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return p;
}

const guard = setTimeout(() => {
  console.error("MCP session timed out");
  child.kill();
  process.exit(1);
}, 90_000);

const init = await rpc("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "zuuna-agent-demo", version: "1.0.0" },
});
const info = init.result?.serverInfo ?? {};
console.log(`  connected: ${info.name} v${info.version} (stdio)`);

child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

const tools = await rpc("tools/list", {});
console.log("  tools: " + (tools.result?.tools ?? []).map((t) => t.name).join(", "));

const me = await rpc("tools/call", { name: "zuuna_me", arguments: {} });
const meText = me.result?.content?.[0]?.text ?? "{}";
try {
  const meJson = JSON.parse(meText);
  console.log(`  zuuna_me: org ${meJson.org.id} · ${meJson.org.product} plan (${meJson.org.plan})`);
  console.log(`  scopes:   ${(meJson.scopes ?? []).join(", ")}`);
} catch {
  console.log(meText.slice(0, 200));
}

clearTimeout(guard);
child.kill();
