import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const failures = [];

function collectFiles(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if ([".git", "node_modules", ".next", "build", ".gradle", "target"].includes(entry.name)) continue;
      if (full.startsWith(path.join(root, "docs", "archive"))) continue;
      collectFiles(full, out);
    } else {
      out.push(full);
    }
  }
  return out;
}

function rpcLike(name) {
  return /^(?:get_|participant_|staff_|bot_|mc_|site_|consume_|record_|touch_|upsert_|claim_|mark_|lift_|revoke_|create_|update_|delete_|set_|list_|accept_|decline_|start_|finish_|respond_|remove_|submit_|approve_|reject_|vote_|rate_|close_|cancel_|enqueue_|process_|sync_|refresh_|bind_|check_)/.test(name);
}

const sqlFiles = collectFiles(path.join(root, "supabase", "migrations"))
  .filter((file) => file.endsWith(".sql"));

const definedFunctions = new Set();

for (const file of sqlFiles) {
  const source = fs.readFileSync(file, "utf8");
  for (const match of source.matchAll(
    /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/gi
  )) {
    definedFunctions.add(match[1].toLowerCase());
  }
}

const usedFunctions = new Map();

function addUse(name, file) {
  const normalized = name.toLowerCase();
  if (!rpcLike(normalized)) return;
  const locations = usedFunctions.get(normalized) ?? new Set();
  locations.add(file);
  usedFunctions.set(normalized, locations);
}

const sourceRoots = [
  "site/src",
  "panel/src",
  "bot",
  "minecraft-plugin/src/main/java",
  "packages/contracts/src",
];

for (const relativeRoot of sourceRoots) {
  const absoluteRoot = path.join(root, relativeRoot);
  for (const file of collectFiles(absoluteRoot)) {
    if (!/\.(?:ts|tsx|js|mjs|cjs|py|java)$/.test(file)) continue;

    const relative = path.relative(root, file);
    const source = fs.readFileSync(file, "utf8");

    for (const match of source.matchAll(
      /(?:\.rpc|call_rpc_async|postRpcAsync|postRpcSync)\s*\(\s*["']([A-Za-z_][A-Za-z0-9_]*)["']/g
    )) {
      addUse(match[1], relative);
    }

    if (relative === "packages/contracts/src/index.ts") {
      for (const match of source.matchAll(
        /\b[a-zA-Z][a-zA-Z0-9_]*\s*:\s*["']([a-z_][a-z0-9_]*)["']/g
      )) {
        addUse(match[1], relative);
      }
    }

    if (relative === "minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java") {
      for (const match of source.matchAll(
        /public\s+static\s+final\s+String\s+[A-Z0-9_]+\s*=\s*"([a-z_][a-z0-9_]*)"/g
      )) {
        addUse(match[1], relative);
      }
    }
  }
}

for (const [name, locations] of usedFunctions) {
  if (!definedFunctions.has(name)) {
    failures.push(
      `RPC contract missing from Supabase migrations: ${name} (used by ${[...locations].join(", ")})`
    );
  }
}

if (failures.length) {
  console.error("PRISMA RPC contract verification failed:");
  console.error(failures.map((failure) => `- ${failure}`).join("\n"));
  console.error(
    `Checked ${usedFunctions.size} used RPC names against ${definedFunctions.size} migration-defined functions.`
  );
  process.exit(1);
}

console.log(
  `PRISMA RPC contract verification passed: ${usedFunctions.size} used RPC names, ${definedFunctions.size} migration-defined functions, 0 unresolved.`
);
