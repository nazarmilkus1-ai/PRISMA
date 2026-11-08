import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const registryPath = path.join(root, "modules/registry.json");
const templatePath = path.join(root, "docs/FEATURE_MODULE_TEMPLATE.md");
const docsDir = path.join(root, "docs/modules");

const args = Object.fromEntries(
  process.argv.slice(2)
    .filter((arg) => arg.startsWith("--"))
    .map((arg) => {
      const index = arg.indexOf("=");
      return index === -1 ? [arg.slice(2), "true"] : [arg.slice(2, index), arg.slice(index + 1)];
    }),
);

const id = args.id?.trim();
const title = args.title?.trim();
const owner = args.owner?.trim() || "core";
const dependsOn = args.depends ? args.depends.split(",").map((value) => value.trim()).filter(Boolean) : [];

if (!id || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id)) {
  console.error("Usage: node scripts/create-feature-module.mjs --id=example --title=\"Example module\" [--owner=core] [--depends=auth,players]");
  process.exit(1);
}
if (!title) {
  console.error("Missing --title");
  process.exit(1);
}

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
if (registry.modules.some((module) => module.id === id)) {
  console.error("Module already exists: " + id);
  process.exit(1);
}
for (const dependency of dependsOn) {
  if (!registry.modules.some((module) => module.id === dependency)) {
    console.error("Unknown dependency: " + dependency);
    process.exit(1);
  }
}

registry.modules.push({
  id,
  title,
  status: "planned",
  owner,
  runtimeManaged: true,
  runtimeToggleProtected: false,
  dependsOn,
  surfaces: [],
  contractNamespaces: [],
  uses: [],
  sourceRoots: [],
  removal: {
    entrypoints: true,
    contracts: true,
    database: "forward-migration",
    acl: true,
  },
});

fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2) + "\n", "utf8");

const syncScript = path.join(root, "scripts/sync-module-contracts.mjs");
execFileSync(process.execPath, [syncScript], { cwd: root, stdio: "inherit" });

const template = fs.readFileSync(templatePath, "utf8");
const doc = template
  .replace("- **Module:** ", "- **Module:** " + id)
  .replace("- **Owner:** ", "- **Owner:** " + owner)
  .replace("- **Status:** planned | active | deprecated", "- **Status:** planned");

fs.mkdirSync(docsDir, { recursive: true });
fs.writeFileSync(path.join(docsDir, id + ".md"), "# " + title + "\n\n" + doc, "utf8");

console.log("Created planned module: " + id);
console.log("Registry: modules/registry.json");
console.log("Contracts: packages/contracts/src/modules.generated.ts");
console.log("Spec: docs/modules/" + id + ".md");
