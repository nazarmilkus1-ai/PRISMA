import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const registryPath = path.join(root, "modules/registry.json");
const outputPath = path.join(root, "packages/contracts/src/modules.generated.ts");

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const modules = registry.modules;
if (!Array.isArray(modules) || modules.length === 0) throw new Error("modules/registry.json must contain modules");

const ids = modules.map((module) => module.id);
const metadata = Object.fromEntries(modules.map((module) => [
  module.id,
  {
    title: module.title,
    owner: module.owner,
    status: module.status,
    runtimeManaged: module.runtimeManaged === true,
    runtimeToggleProtected: module.runtimeToggleProtected === true,
    dependsOn: module.dependsOn ?? [],
  },
]));

const output = [
  "// AUTO-GENERATED from modules/registry.json. Do not edit by hand.",
  "export const MODULE_IDS = " + JSON.stringify(ids, null, 2) + " as const;",
  "",
  "export type ModuleId = (typeof MODULE_IDS)[number];",
  "",
  "export const MODULE_METADATA: Record<ModuleId, {",
  "  title: string;",
  "  owner: string;",
  "  status: \"planned\" | \"active\" | \"deprecated\";",
  "  runtimeManaged: boolean;",
  "  runtimeToggleProtected: boolean;",
  "  dependsOn: readonly ModuleId[];",
  "}> = " + JSON.stringify(metadata, null, 2) + " as const;",
  "",
].join("\n");

fs.writeFileSync(outputPath, output, "utf8");
console.log("Synced " + ids.length + " module contracts -> " + path.relative(root, outputPath));
