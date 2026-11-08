import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const failures = [];
const fail = (message) => failures.push(message);
const read = (file) => {
  try {
    return fs.readFileSync(path.join(root, file), "utf8");
  } catch (error) {
    fail("unable to read " + file + ": " + error.message);
    return "";
  }
};
const registryPath = path.join(root, "modules/registry.json");
const contractsPath = path.join(root, "packages/contracts/src/index.ts");
const generatedContractsPath = path.join(root, "packages/contracts/src/modules.generated.ts");
const syncScriptPath = path.join(root, "scripts/sync-module-contracts.mjs");
const runtimeMigrationPath = path.join(root, "supabase/migrations/20261001085000_prisma_module_runtime_control.sql");
const runtimeGuardMigrationPath = path.join(root, "supabase/migrations/20261001090000_prisma_module_runtime_guardrails.sql");
const runtimeHelperPath = path.join(root, "packages/contracts/src/module-runtime.ts");

function renderGeneratedManifest(registry) {
  const modules = Array.isArray(registry?.modules)
    ? registry.modules.filter((module) => module && typeof module === "object" && !Array.isArray(module))
    : [];
  const ids = modules.map((module) => module.id);
  const metadata = Object.fromEntries(modules.map((module) => [module.id, {
    title: module.title,
    owner: module.owner,
    status: module.status,
    runtimeManaged: module.runtimeManaged === true,
    runtimeToggleProtected: module.runtimeToggleProtected === true,
    dependsOn: module.dependsOn ?? [],
  }]));
  return [
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
}


for (const requiredFile of [runtimeMigrationPath, runtimeGuardMigrationPath, runtimeHelperPath, generatedContractsPath, syncScriptPath]) {
  if (!fs.existsSync(requiredFile)) fail("runtime module migration missing: " + path.relative(root, requiredFile));
}

let registryForManifest = { modules: [] };
if (!fs.existsSync(registryPath)) {
  fail("modules/registry.json is missing");
} else {
  let registry;
  try {
    registry = JSON.parse(read("modules/registry.json"));
    if (!registry || typeof registry !== "object" || Array.isArray(registry)) {
      throw new Error("root value must be a JSON object");
    }
    if (!Array.isArray(registry.modules)) {
      fail("modules/registry.json must contain a non-empty modules array");
      registry.modules = [];
    }
    registryForManifest = registry;
  } catch (error) {
    fail("modules/registry.json is not valid JSON: " + error.message);
  }

  if (registry) {
    if (registry.registryVersion !== 1) fail("modules registryVersion must be 1");
    if (!Array.isArray(registry.defaultRemovalOrder) || registry.defaultRemovalOrder.length < 4) fail("defaultRemovalOrder must be defined");
    if (!Array.isArray(registry.modules) || registry.modules.length === 0) {
      fail("modules/registry.json must contain a non-empty modules array");
    }

    const ids = new Set();
    const byId = new Map();
    const knownSurfaces = new Set(["site","panel","bot","plugin","contracts","supabase","public-api","notifications"]);
    const ownedContracts = new Map();

    for (const module of registry.modules ?? []) {
      if (!module || typeof module !== "object") {
        fail("module entries must be objects");
        continue;
      }

      const id = module.id;
      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id ?? "")) {
        fail("invalid module id: " + String(id));
      }
      if (ids.has(id)) fail("duplicate module id: " + id);
      ids.add(id);
      byId.set(id, module);

      if (!["planned","active","deprecated"].includes(module.status)) {
        fail(id + ": invalid status " + String(module.status));
      }
      if (!module.owner) fail(id + ": owner is required");
      if (!Array.isArray(module.dependsOn)) fail(id + ": dependsOn must be an array");
      if (!Array.isArray(module.surfaces) || module.surfaces.length === 0) {
        fail(id + ": surfaces must be a non-empty array");
      }
      for (const surface of (Array.isArray(module.surfaces) ? module.surfaces : [])) {
        if (!knownSurfaces.has(surface)) fail(id + ": unknown surface " + surface);
      }

      if (!Array.isArray(module.contractNamespaces)) {
        fail(id + ": contractNamespaces must be an array");
      }
      for (const name of (Array.isArray(module.contractNamespaces) ? module.contractNamespaces : [])) {
        if (typeof name !== "string" || !/^[A-Z][A-Z0-9_]*$/.test(name)) {
          fail(id + ": invalid contract namespace: " + String(name));
          continue;
        }
        if (ownedContracts.has(name)) {
          fail(`contract namespace ${name} is owned by both ${ownedContracts.get(name)} and ${id}`);
        } else {
          ownedContracts.set(name, id);
        }
      }

      if (module.sourceRoots != null && !Array.isArray(module.sourceRoots)) {
        fail(id + ": sourceRoots must be an array");
      }
      for (const rootPath of (Array.isArray(module.sourceRoots) ? module.sourceRoots : [])) {
        if (typeof rootPath !== "string" || rootPath.length === 0) {
          fail(id + ": sourceRoots entries must be non-empty strings");
          continue;
        }
        if (!fs.existsSync(path.join(root, rootPath))) {
          fail(`${id}: source root does not exist: ${rootPath}`);
        }
      }

      if (module.status !== "planned" && module.runtimeManaged !== true) {
        fail(id + ": active/deprecated module must set runtimeManaged=true");
      }

      if (module.status !== "planned") {
        const removal = module.removal;
        const removalRecord = removal && typeof removal === "object" && !Array.isArray(removal)
          ? removal
          : {};
        if (Object.keys(removalRecord).length === 0) {
          fail(id + ": active/deprecated module needs removal metadata");
        }
        for (const key of ["entrypoints","contracts","database","acl"]) {
          if (!(key in removalRecord)) fail(id + ": removal." + key + " is required");
        }
      }

      if (module.uses != null && !Array.isArray(module.uses)) {
        fail(id + ": uses must be an array");
      }
      const contractUses = Array.isArray(module.uses) ? module.uses : [];
      for (const used of contractUses) {
        if (typeof used !== "string") fail(id + ": every uses entry must be a string");
      }
    }

    for (const module of registry.modules ?? []) {
      if (!module || typeof module !== "object") continue;
      for (const dependency of (Array.isArray(module.dependsOn) ? module.dependsOn : [])) {
        if (typeof dependency !== "string") {
          fail(module.id + ": dependency entries must be strings");
          continue;
        }
        if (!byId.has(dependency)) fail(module.id + ": unknown dependency " + dependency);
        if (dependency === module.id) fail(module.id + ": self-dependency is not allowed");
      }
    }

    const visiting = new Set();
    const visited = new Set();
    const visit = (id, chain = []) => {
      if (visiting.has(id)) {
        fail("module dependency cycle: " + [...chain, id].join(" -> "));
        return;
      }
      if (visited.has(id)) return;
      visiting.add(id);
      const dependencies = byId.get(id)?.dependsOn;
      for (const dep of (Array.isArray(dependencies) ? dependencies : [])) {
        if (byId.has(dep)) visit(dep, [...chain, id]);
      }
      visiting.delete(id);
      visited.add(id);
    };
    for (const id of byId.keys()) visit(id);

    if (fs.existsSync(contractsPath) && fs.existsSync(generatedContractsPath)) {
      const contracts = fs.readFileSync(contractsPath, "utf8");
      const generatedContracts = fs.readFileSync(generatedContractsPath, "utf8");
      const exportedConstNames = [...contracts.matchAll(/^export const ([A-Z0-9_]+)(?:\s*:[^=]+)?\s*=/gm)].map((m) => m[1]);
      const generatedConstNames = [...generatedContracts.matchAll(/^export const ([A-Z0-9_]+)(?:\s*:[^=]+)?\s*=/gm)].map((m) => m[1]);
      const moduleIdsMatch = generatedContracts.match(/export const MODULE_IDS = \[([\s\S]*?)\] as const;/m);
      if (!moduleIdsMatch) {
        fail("shared contracts: MODULE_IDS export is missing");
      } else {
        const contractModuleIds = [...moduleIdsMatch[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
        const registryModuleIds = (registry.modules ?? []).map((module) => module && typeof module === "object" ? module.id : undefined);
        if (JSON.stringify(contractModuleIds) !== JSON.stringify(registryModuleIds)) {
          fail("MODULE_IDS must exactly match modules/registry.json module ordering");
        }
      }
      const generatedNames = [...generatedContracts.matchAll(/^export const ([A-Z0-9_]+)(?:\s*:[^=]+)?\s*=/gm)].map((m) => m[1]);
      for (const name of [...new Set([...exportedConstNames, ...generatedNames])]) {
        if (!ownedContracts.has(name)) {
          fail("shared contract export is not registered in a module: " + name);
        }
      }
      for (const requiredNamespace of ["MODULE_IDS","MODULE_METADATA","MODULE_STATE_RPC","STAFF_MODULE_RPC"]) {
        if (![...new Set([...exportedConstNames, ...generatedNames])].includes(requiredNamespace)) fail("shared contract export is missing: " + requiredNamespace);
      }
      for (const [name, owner] of ownedContracts) {
        const pattern = new RegExp(String.raw`^export const ${name}(?:\s*:[^=]+)?\s*=`, "m");
        if (!pattern.test(contracts + "\n" + generatedContracts)) {
          fail(owner + ": registered contract namespace does not exist: " + name);
        }
      }
      for (const module of registry.modules ?? []) {
        if (!module || typeof module !== "object") continue;
        for (const used of (Array.isArray(module.uses) ? module.uses : [])) {
          if (!ownedContracts.has(used) && !exportedConstNames.includes(used)) {
            fail(module.id + ": referenced contract namespace does not exist: " + used);
          }
        }
      }
    } else if (!fs.existsSync(contractsPath)) {
      fail("packages/contracts/src/index.ts is missing");
    }
  }
}

if (fs.existsSync(generatedContractsPath)) {
  const generatedManifest = fs.readFileSync(generatedContractsPath, "utf8");
  if (generatedManifest !== renderGeneratedManifest(registryForManifest)) {
    fail("modules.generated.ts is out of sync with modules/registry.json; run scripts/sync-module-contracts.mjs");
  }
}

const runtimeMigration = fs.existsSync(runtimeMigrationPath) ? fs.readFileSync(runtimeMigrationPath, "utf8") : "";
const runtimeGuard = fs.existsSync(runtimeGuardMigrationPath) ? fs.readFileSync(runtimeGuardMigrationPath, "utf8") : "";
const runtimeHelper = fs.existsSync(runtimeHelperPath) ? fs.readFileSync(runtimeHelperPath, "utf8") : "";
if (!runtimeHelper.includes("if (states[current] !== true) return false;")) {
  fail("module runtime helper must fail closed when a module state is missing or not enabled");
}
for (const needle of [
  "public.prisma_module_states",
  "get_public_module_state",
  "get_public_module_states",
  "staff_get_module_states",
  "staff_set_module_state",
  "modules.view",
  "modules.manage",
]) {
  if (!runtimeMigration.includes(needle)) fail("runtime migration missing contract marker: " + needle);
}
for (const needle of ["PROTECTED_MODULE", "using (false)", "with check (false)"]) {
  if (!runtimeGuard.includes(needle)) fail("runtime guard migration missing safety marker: " + needle);
}
const protectedModuleIds = registryForManifest.modules
  .filter((module) => module && typeof module === "object" && module.runtimeToggleProtected === true)
  .map((module) => module.id);
for (const id of protectedModuleIds) {
  if (!runtimeGuard.includes("'" + id + "'")) {
    fail("runtime guard does not protect registry module marked runtimeToggleProtected: " + id);
  }
}

const guardedMutationRoutes = new Map([
  ["site/src/app/api/clans/action/route.ts", "clans"],
  ["site/src/app/api/applications/route.ts", "applications"],
  ["site/src/app/api/profile/update/route.ts", "players"],
  ["site/src/app/api/notifications/read/route.ts", "notifications"],
  ["site/src/app/api/settings/notifications/route.ts", "notifications"],
  ["site/src/app/api/clans/create/route.ts", "clans"],
  ["site/src/app/api/events/register/route.ts", "events"],
  ["site/src/app/api/market/route.ts", "market"],
  ["site/src/app/api/polls/vote/route.ts", "voting"],
  ["site/src/app/api/reports/route.ts", "reports"],
  ["site/src/app/api/battles/route.ts", "battles"],
  ["site/src/app/api/appeals/route.ts", "appeals"],
  ["site/src/app/api/profile/social/route.ts", "social"],
  ["site/src/app/api/profile/social-visibility/route.ts", "social"],
]);
const guardedReadPages = new Map([
  ["site/src/app/apply/page.tsx", "applications"],
  ["site/src/app/live/page.tsx", "events"],
  ["site/src/app/app/application/page.tsx", "applications"],
  ["site/src/app/app/notifications/page.tsx", "notifications"],
  ["site/src/app/app/clan/page.tsx", "clans"],
  ["site/src/app/app/battles/page.tsx", "battles"],
  ["site/src/app/app/appeals/page.tsx", "appeals"],
  ["site/src/app/app/voting/page.tsx", "voting"],
  ["site/src/app/app/reports/page.tsx", "reports"],
  ["site/src/app/app/reports/[id]/page.tsx", "reports"],
  ["site/src/app/market/page.tsx", "market"],
  ["site/src/app/events/page.tsx", "events"],
  ["site/src/app/events/[slug]/page.tsx", "events"],
  ["site/src/app/app/calendar/page.tsx", "events"],
  ["site/src/app/app/map/page.tsx", "map"],
  ["site/src/app/app/minecraft/page.tsx", "minecraft"],
  ["site/src/app/app/profile/page.tsx", "players"],
  ["site/src/app/clans/page.tsx", "clans"],
  ["site/src/app/clans/[id]/page.tsx", "clans"],
  ["site/src/app/clans/compare/page.tsx", "clans"],
  ["site/src/app/clan/[tag]/page.tsx", "clans"],
  ["site/src/app/commands/page.tsx", "minecraft"],
  ["site/src/app/history/page.tsx", "analytics"],
  ["site/src/app/news/page.tsx", "public-content"],
  ["site/src/app/news/[id]/page.tsx", "public-content"],
  ["site/src/app/wiki/page.tsx", "public-content"],
  ["site/src/app/wiki/[slug]/page.tsx", "public-content"],
  ["site/src/app/players/page.tsx", "players"],
  ["site/src/app/players/[nickname]/page.tsx", "players"],
  ["site/src/app/rankings/page.tsx", "players"],
  ["site/src/app/server/page.tsx", "minecraft"],
  ["site/src/app/map/page.tsx", "map"],
  ["site/src/app/map/history/page.tsx", "map"],
  ["site/src/app/timeline/page.tsx", "analytics"],
  ["site/src/app/awards/page.tsx", "public-content"],
  ["site/src/app/media/page.tsx", "public-content"],
  ["site/src/app/calendar/page.tsx", "events"],
  ["site/src/app/seasons/page.tsx", "public-content"],
  ["site/src/app/seasons/[slug]/page.tsx", "public-content"],
]);
const guardedReadRoutes = new Map([
  ["site/src/app/api/v1/players/route.ts", "players"],
  ["site/src/app/api/v1/player/[nickname]/route.ts", "players"],
  ["site/src/app/api/v1/server/route.ts", "minecraft"],
]);
const guardedConditionalPages = new Map([
  ["site/src/app/app/settings/page.tsx", { moduleIds: ["notifications"], markers: ["enabledModules.notifications"] }],
  ["site/src/app/page.tsx", {
    moduleIds: ["minecraft", "clans", "events", "players", "market", "public-content", "applications"],
    markers: ["const tiles = TILES.filter((tile) => enabledModules[tile.moduleId]);", 'enabledModules["public-content"] ?', "enabledModules.applications ? ("],
  }],
  ["site/src/app/search/page.tsx", {
    moduleIds: ["players", "clans", "public-content", "market"],
    markers: ["groups.filter(([moduleId])=>enabledModules[moduleId])"],
  }],
  ["site/src/components/SiteHeader.tsx", {
    moduleIds: ["minecraft", "map", "market", "public-content", "events", "applications"],
    markers: ["const nav = sourceNav.filter(([href, , moduleId]) =>", "(!moduleId || enabledModules[moduleId]) &&"],
  }],
  ["site/src/app/app/profile/page.tsx", {
    moduleIds: ["players", "social", "minecraft"],
    markers: ["enabledModules.social && social ?", "enabledModules.minecraft ? (", "if (!enabledModules.players) notFound();"],
  }],
  ["site/src/app/players/[nickname]/page.tsx", {
    moduleIds: ["players", "social", "battles"],
    markers: ["enabledModules.social && viewerSocial &&", "enabledModules.battles ?", "if (!enabledModules.players) notFound();"],
  }],
]);
const accessHelper = read("site/src/lib/access.ts");
for (const marker of [
  "export async function requireModule(id: ModuleId)",
  "export async function requireModuleUser(id: ModuleId)",
  "export async function requireModuleMember(id: ModuleId)",
  "if (!(await isPublicModuleEnabled(id))) notFound();",
]) {
  if (!accessHelper.includes(marker)) {
    fail("site/src/lib/access.ts: canonical module access helper is missing " + marker);
  }
}

function hasModuleRuntimeGate(source, moduleId) {
  const quotedModule = `["\']${moduleId}["\']`;
  const callArguments = String.raw`\s*\(\s*${quotedModule}\s*\)`;
  return new RegExp(String.raw`isPublicModuleEnabled${callArguments}`).test(source) ||
    new RegExp(String.raw`requireModule(?:User|Member)?${callArguments}`).test(source);
}

const registeredModuleIds = new Set(registryForManifest.modules
  .filter((module) => module && typeof module === "object")
  .map((module) => module.id));
for (const [route, moduleId] of guardedMutationRoutes) {
  const absolutePath = path.join(root, route);
  if (!registeredModuleIds.has(moduleId)) {
    fail(route + ": runtime gate references an unregistered module: " + moduleId);
    continue;
  }
  if (!fs.existsSync(absolutePath)) {
    fail("guarded mutation route is missing: " + route);
    continue;
  }
  const source = fs.readFileSync(absolutePath, "utf8");
  if (!hasModuleRuntimeGate(source, moduleId)) {
    fail(route + ": missing effective runtime gate for module " + moduleId);
  }
}


for (const [route, moduleId] of guardedReadRoutes) {
  const absolutePath = path.join(root, route);
  if (!registeredModuleIds.has(moduleId)) {
    fail(route + ": read API references an unregistered module: " + moduleId);
    continue;
  }
  if (!fs.existsSync(absolutePath)) {
    fail("guarded read API route is missing: " + route);
    continue;
  }
  const source = fs.readFileSync(absolutePath, "utf8");
  if (!hasModuleRuntimeGate(source, moduleId)) {
    fail(route + ": missing effective runtime gate for module " + moduleId);
  }
}
for (const [surface, config] of guardedConditionalPages) {
  const absolutePath = path.join(root, surface);
  const moduleIds = config.moduleIds ?? [config.moduleId];
  const markers = config.markers ?? [config.marker];
  const unregisteredModule = moduleIds.find((moduleId) => !registeredModuleIds.has(moduleId));
  if (unregisteredModule) {
    fail(surface + ": conditional module gate references an unregistered module: " + unregisteredModule);
    continue;
  }
  if (!fs.existsSync(absolutePath)) {
    fail("guarded conditional surface is missing: " + surface);
    continue;
  }
  const source = fs.readFileSync(absolutePath, "utf8");
  if (!source.includes("getPublicModuleAvailability") || !markers.every((marker) => source.includes(marker))) {
    fail(surface + ": must conditionally hide module-owned content when its modules are disabled");
  }
}

for (const [page, moduleId] of guardedReadPages) {
  const absolutePath = path.join(root, page);
  if (!registeredModuleIds.has(moduleId)) {
    fail(page + ": runtime gate references an unregistered module: " + moduleId);
    continue;
  }
  if (!fs.existsSync(absolutePath)) {
    fail("guarded read page is missing: " + page);
    continue;
  }
  const source = fs.readFileSync(absolutePath, "utf8");
  const directGate = hasModuleRuntimeGate(source, moduleId);
  const availabilityGate = source.includes("getPublicModuleAvailability") &&
    (source.includes("enabledModules." + moduleId) || source.includes('enabledModules["' + moduleId + '"]'));
  if (!directGate && !availabilityGate) {
    fail(page + ": missing effective runtime gate for module " + moduleId);
  }
  const directNotFound = source.includes("notFound(");
  const helperNotFound = source.includes("requireModule(") ||
    source.includes("requireModuleUser(") ||
    source.includes("requireModuleMember(");
  if (!directNotFound && !helperNotFound) {
    fail(page + ": disabled module page must use a notFound-backed module guard");
  }
  if (/notFound\s*\(/.test(source) && !/import\s*\{[^}]*\bnotFound\b[^}]*\}\s*from\s*["']next\/navigation["']/.test(source)) {
    fail(page + ": notFound() must be imported from next/navigation");
  }
}

if (failures.length) {
  console.error("PRISMA module registry verification failed:");
  console.error(failures.map((failure) => `- ${failure}`).join("\n"));
  process.exit(1);
}

console.log(`PRISMA module registry passed: ${registryForManifest.modules.length} modules, centralized ownership, dependency graph, and runtime entrypoint gates valid`);
