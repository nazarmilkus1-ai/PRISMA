import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const failures = [];

try {
  execFileSync(process.execPath, ["scripts/verify-rpc-contracts.mjs"], { cwd: root, stdio: "inherit" });
} catch (error) {
  failures.push(`RPC contract gate failed: ${error.message}`);
}

try {
  execFileSync(process.execPath, ["scripts/verify-modules.mjs"], { cwd: root, stdio: "inherit" });
} catch (error) {
  failures.push(`Module registry gate failed: ${error.message}`);
}
function read(relative) {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

function requirePath(relative) {
  if (!fs.existsSync(path.join(root, relative))) {
    failures.push(`Missing release-critical path: ${relative}`);
    return false;
  }
  return true;
}

function requireText(relative, needle) {
  const source = read(relative);
  if (!source.includes(needle)) {
    failures.push(`${relative}: missing expected release contract ${JSON.stringify(needle)}`);
  }
}

const expected = read("VERSION").trim();
if (!/^2\.1\.0$/.test(expected)) {
  failures.push(`Unsupported release version: ${expected}`);
}

const packageExpectations = [
  ["panel/package.json", "@prisma-eco/admin", ["typecheck", "build"]],
  ["site/package.json", "@prisma-eco/site", ["typecheck", "build"]],
  ["packages/contracts/package.json", "@prisma-eco/contracts", []],
  ["packages/ui/package.json", "@prisma-eco/ui", []],
];

for (const [file, expectedName, requiredScripts] of packageExpectations) {
  if (!requirePath(file)) continue;

  let pkg;
  try {
    pkg = JSON.parse(read(file));
  } catch (error) {
    failures.push(`${file}: invalid JSON (${error.message})`);
    continue;
  }

  if (pkg.version !== expected) {
    failures.push(`${file}: version ${pkg.version} != release ${expected}`);
  }
  if (pkg.name !== expectedName) {
    failures.push(`${file}: package name ${pkg.name} != expected ${expectedName}`);
  }
  for (const script of requiredScripts) {
    if (typeof pkg.scripts?.[script] !== "string") {
      failures.push(`${file}: missing npm script ${script}`);
    }
  }
}

const vercelConfigPath = "vercel.json";
if (requirePath(vercelConfigPath)) {
  try {
    const config = JSON.parse(read(vercelConfigPath));
    const services = config.services ?? {};

    for (const [name, expected] of [
      ["site", { root: "site", framework: "nextjs" }],
      ["panel", { root: "panel", framework: "nextjs" }],
    ]) {
      const service = services[name];
      if (!service) {
        failures.push(`vercel.json: missing service ${name}`);
        continue;
      }
      for (const [key, value] of Object.entries(expected)) {
        if (service[key] !== value) {
          failures.push(`vercel.json: service ${name} must set ${key}=${value}`);
        }
      }
    }

    if (services.bot) {
      failures.push("vercel.json: Telegram bot must stay on Render, not Vercel");
    }

    const rewriteSources = new Set((config.rewrites ?? []).map((entry) => entry.source));
    for (const source of ["/admin", "/admin/:path*", "/(.*)"]) {
      if (!rewriteSources.has(source)) {
        failures.push(`vercel.json: missing rewrite ${source}`);
      }
    }

    if ((config.crons ?? []).length) {
      failures.push("vercel.json: Vercel Cron must not host bot background workers");
    }
  } catch (error) {
    failures.push(`vercel.json: invalid JSON (${error.message})`);
  }
}

for (const file of ["panel/package.json", "site/package.json"]) {
  const pkg = JSON.parse(read(file));
  if (pkg.engines?.node !== "24.x") {
    failures.push(`${file}: Node engine must stay pinned to 24.x`);
  }
}

for (const file of [
  "panel/.env.example",
  "site/.env.example",
  "bot/.env.example",
  "bot/requirements.txt",
  "bot/main.py",
  "vercel.json",
  "docs/VERCEL_SERVICES.md",
  "minecraft-plugin/build.gradle.kts",
  "minecraft-plugin/src/main/resources/plugin.yml",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/MinecraftCommandCatalogCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/PrismaHelpCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/maze/MazeRunnerController.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerHomeCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/homes/PlayerHomesStore.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/SpawnCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerJourneyCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/journey/PlayerJourneyStore.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/listeners/PlayerJourneyListener.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/ModerationCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/tasks/MinecraftChatBridgeTask.java",
  "bot/services/minecraft_bridge.py",
  "supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql",
  "supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql",
  "supabase/migrations/20261024143000_prisma_minecraft_telegram_identity_binding.sql",
  "modules/registry.json",
  "minecraft-plugin/src/main/java/team/prisma/plugin/graves/GraveStore.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/listeners/GraveListener.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/commands/GraveCommand.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/spawn/SpawnPointsStore.java",
  "minecraft-plugin/src/main/java/team/prisma/plugin/staff/PlayerRoleDisplay.java",
  "packages/contracts/minecraft-commands.json",
  "packages/contracts/src/minecraft-commands.ts",
  "site/src/app/commands/page.tsx",
  "site/src/app/app/commands/page.tsx",
  "bot/handlers/minecraft_commands.py",
  "bot/utils/minecraft_commands.py",
  "minecraft-plugin/gradlew",
  "minecraft-plugin/gradlew.bat",
  "supabase/migrations",
]) {
  requirePath(file);
}

if (fs.existsSync(path.join(root, "supabase/PRISMA_RELEASE.sql"))) {
  failures.push("Stale one-shot supabase/PRISMA_RELEASE.sql must not exist; production schema changes are migration-first");
}


const gradle = read("minecraft-plugin/build.gradle.kts");
const derivesFromVersionFile =
  /^version\s*=\s*rootProject\.file\("\.\.\/VERSION"\)\.readText\(\)\.trim\(\)$/m.test(gradle);
if (!derivesFromVersionFile) {
  failures.push("minecraft-plugin/build.gradle.kts: plugin version must derive from the canonical root VERSION file");
}
if (!/toolchain\s*\{\s*languageVersion\.set\(JavaLanguageVersion\.of\(25\)\)/s.test(gradle)) {
  failures.push("minecraft-plugin/build.gradle.kts: Java toolchain must target Java 25");
}
if (!/options\.release\.set\(25\)/.test(gradle)) {
  failures.push("minecraft-plugin/build.gradle.kts: Java bytecode release must target 25");
}
if (!/paper-api:26\.3\.build\.195-stable/.test(gradle)) {
  failures.push("minecraft-plugin/build.gradle.kts: Paper API must pin the stable Paper 26.3 API build");
}
if (!/gradle-9\.4\.0-bin\.zip/.test(read("minecraft-plugin/gradle/wrapper/gradle-wrapper.properties"))) {
  failures.push("Minecraft plugin Gradle wrapper must use Gradle 9.4.0 for Java 25");
}
if (!/api-version:\s*['"]26\.3['"]/.test(read("minecraft-plugin/src/main/resources/plugin.yml"))) {
  failures.push("minecraft-plugin/src/main/resources/plugin.yml: api-version must be 26.3");
}

const pluginYml = read("minecraft-plugin/src/main/resources/plugin.yml");
if (!/version:\s*['"]\$\{version\}['"]/.test(pluginYml)) {
  failures.push("minecraft-plugin/src/main/resources/plugin.yml: version must be expanded from Gradle project version");
}
if (!/main:\s*team\.prisma\.plugin\.PrismaPlugin/.test(pluginYml)) {
  failures.push("minecraft-plugin/src/main/resources/plugin.yml: PrismaPlugin main class is missing");
}

const catalog = JSON.parse(read("packages/contracts/minecraft-commands.json"));
if (catalog.release !== expected) {
  failures.push("packages/contracts/minecraft-commands.json: catalog release does not match VERSION");
}
if (!catalog.commands.some((command) => command.command === "/maze")) {
  failures.push("Minecraft command catalog: /maze is missing");
}
if (!catalog.commands.some((command) => command.command === "/prismacommands")) {
  failures.push("Minecraft command catalog: /prismacommands is missing");
}
if (catalog.commands.some((command) => command.command === "/back")) {
  failures.push("Minecraft command catalog: legacy /back command is forbidden");
}
const prismaAuth = catalog.authentication.find((entry) => entry.name === "PRISMA Auth");
if (!prismaAuth || prismaAuth.platform !== "JAVA") {
  failures.push("Minecraft authentication catalog: PRISMA Auth must be JAVA-only");
}
if (prismaAuth && prismaAuth.commands?.some(([command]) => String(command).toLowerCase().includes("simplelogin"))) {
  failures.push("Minecraft authentication catalog: SimpleLogin commands must not return to the PRISMA contract");
}
const floodgate = catalog.authentication.find((entry) => entry.name === "Floodgate");
if (!floodgate || floodgate.platform !== "BEDROCK") {
  failures.push("Minecraft authentication catalog: Floodgate must be BEDROCK-only");
}

const requiredMigrations = [
  "20260928140000_prisma_moderation_plugin_claim_lease.sql",
  "20261024120000_prisma_mc_staff_moderation_commands.sql",
  "20261024133000_prisma_minecraft_telegram_chat_bridge.sql",
  "20261024140000_prisma_minecraft_chat_bridge_hardening.sql",
  "20261024143000_prisma_minecraft_telegram_identity_binding.sql",
  "20261024150000_prisma_minecraft_gameplay_toggles.sql",
  "20260928150000_prisma_public_function_default_acl_lockdown.sql",
  "20260928153000_prisma_public_function_execute_guard.sql",
  "20260928160000_prisma_trigger_function_execute_lockdown.sql",
  "20260928170000_prisma_participant_dashboard_gateway.sql",
  "20260928172000_prisma_participant_notifications_read_gateway.sql",
  "20260928173000_prisma_participant_application_read_gateway.sql",
  "20260928174000_prisma_participant_reports_read_gateways.sql",
  "20260928175000_prisma_participant_battle_read_gateway.sql",
  "20260928176000_prisma_participant_notification_preferences_gateway.sql",
  "20260928177000_prisma_participant_market_listing_read_gateway.sql",
  "20260928178000_prisma_staff_live_events_gateway.sql",
  "20260928179000_prisma_participant_current_user_gateway.sql",
  "20260928180000_prisma_participant_unread_notification_count_gateway.sql",
  "20260928181000_prisma_participant_current_user_privacy.sql",
  "20260928182000_prisma_participant_current_user_privacy_telegram.sql",
  "20260928183000_prisma_auth_rate_limit_search_path_hardening.sql",
  "20260928184000_prisma_public_schema_create_acl_hardening.sql",
  "20260928170658_prisma_public_read_rpc_acl_hardening.sql",
  "20260928170811_prisma_public_default_privileges_lockdown.sql",
  "20260928171217_prisma_private_permission_helper_runtime_grant.sql",
    "20260928163556_prisma_bot_login_code_search_path_hardening.sql",
  "20260928164012_prisma_market_close_listing_count_fix.sql",
  "20260928164254_prisma_private_schema_acl_reassert.sql",
  "20260928165750_prisma_staff_map_history_gateway.sql",
  "20260929062000_prisma_public_content_read_gateways.sql",
  "20260929074500_prisma_public_read_authenticated_acl_lockdown.sql",
  "20260930140140_prisma_server_roles_and_identity.sql",
  "20260930154151_prisma_minecraft_identity_hardening.sql",
  "20260930163127_prisma_minecraft_identity_binding.sql",
  "20260930163440_prisma_minecraft_identity_search_path_hardening.sql",
  "20260930170000_prisma_automod_rpc_reproducibility.sql",
  "20260930171000_prisma_automod_punishment_search_path_hardening.sql",
  "20261001085000_prisma_module_runtime_control.sql",
  "20261001090000_prisma_module_runtime_guardrails.sql",
  "20261001100000_prisma_mc_list_active_villages_reassert.sql",
];

for (const migration of requiredMigrations) {
  requirePath(path.join("supabase/migrations", migration));
}

const migrationFiles = fs.readdirSync(path.join(root, "supabase/migrations"))
  .filter((file) => /^\d{14}_.+\.sql$/.test(file))
  .sort();

const seenVersions = new Map();
for (const file of migrationFiles) {
  const version = file.slice(0, 14);
  const existing = seenVersions.get(version) ?? [];
  existing.push(file);
  seenVersions.set(version, existing);
}
for (const [version, files] of seenVersions) {
  if (files.length > 1) {
    failures.push(`Duplicate Supabase migration version ${version}: ${files.join(", ")}`);
  }
}

const tracked = execFileSync("git", ["ls-files"], { cwd: root, encoding: "utf8" })
  .split(/\r?\n/)
  .filter(Boolean);

for (const file of tracked) {
  if (/(^|\/)\.env(?:\.[^/]+)?$/.test(file) && !/\.example$/.test(file)) {
    failures.push(`Tracked environment secret file: ${file}`);
  }
  if (/(^|\/)(?:config\.yml|config\.yaml)$/.test(file) && file.startsWith("minecraft-plugin/")) {
    failures.push(`Tracked Minecraft plugin runtime config: ${file}`);
  }
}

requireText("site/src/lib/rate-limit.ts", "AUTH_RATE_LIMIT_RPC.consume");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/staff/PlayerRoleDisplay.java", "player.setPlayerListName(decorated)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/staff/PlayerRoleDisplay.java", "player.setCustomName(decorated)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/staff/PlayerRoleDisplay.java", "PermissionAttachment");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "softdepend: [Geyser-Spigot, floodgate]");
requireText("packages/contracts/minecraft-commands.json", `"release": "${expected}"`);
requireText("packages/contracts/minecraft-commands.json", `"name": "PRISMA Auth"`);
requireText("packages/contracts/minecraft-commands.json", `"platform": "BEDROCK"`);
requireText("site/src/app/commands/page.tsx", "MINECRAFT_AUTHENTICATION");
requireText("bot/handlers/minecraft_commands.py", 'commands={"commands", "mc_commands"}');
requireText("site/src/lib/rate-limit.ts", "return false;");
requireText("panel/src/lib/rate-limit.ts", "AUTH_RATE_LIMIT_RPC.consume");
requireText("panel/src/lib/rate-limit.ts", "return false;");
requireText("site/src/app/api/health/route.ts", "PUBLIC_RPC.serverStatus");
requireText("bot/main.py", "dp.start_polling(bot)");
requireText("bot/main.py", "run_notification_worker");
requireText("bot/main.py", "run_onboarding_reminder_worker");
requireText("bot/requirements.txt", "aiogram==");
requireText("panel/next.config.ts", 'basePath: "/admin"');
requireText("site/src/app/api/health/route.ts", "createSupabasePublicClient");
requireText("docs/MINECRAFT_AUTH.md", "PRISMA Auth");
requireText("packages/contracts/src/index.ts", "export const STAFF_RPC");
const gameplayToggleMigration = read("supabase/migrations/20261024150000_prisma_minecraft_gameplay_toggles.sql");
if (!gameplayToggleMigration.includes("('minecraft-maze-runner', false)")) {
  failures.push("Maze Runner must remain disabled until the map is configured");
}
requireText("minecraft-plugin/src/main/resources/plugin.yml", "  maze:");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/maze/MazeRunnerController.java", "preventGrieverDamageInGlade");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/maze/MazeRunnerController.java", "dropCompassForManagedGriever");
for (const moduleId of [
  "minecraft-teleport-requests", "minecraft-homes", "minecraft-spawns", "minecraft-journey",
  "minecraft-graves", "minecraft-hud", "minecraft-moderation", "minecraft-tpall",
  "minecraft-staff-teleport", "minecraft-clan-commands", "minecraft-village-commands",
  "minecraft-village-protection", "minecraft-chat-bridge",
]) {
  if (!gameplayToggleMigration.includes("('" + moduleId + "', true)")) {
    failures.push("Minecraft gameplay toggle migration must seed enabled state for " + moduleId);
  }
}
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", "public final class RpcNames");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", "GET_STAFF_IDENTITY");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", "BIND_MINECRAFT_IDENTITY");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", 'MC_BRIDGE_ENQUEUE_FROM_MINECRAFT = "mc_bridge_enqueue_from_minecraft"');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", 'MC_BRIDGE_CLAIM_FOR_MINECRAFT = "mc_bridge_claim_for_minecraft"');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", 'MC_BRIDGE_FINISH_MESSAGE = "mc_bridge_finish_message"');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/ChatListener.java", "RpcNames.MC_BRIDGE_ENQUEUE_FROM_MINECRAFT");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/ChatListener.java", "EventPriority.MONITOR");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/ChatListener.java", "Bukkit.getScheduler().runTask(plugin, () -> {");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/ChatListener.java", "player.getWorld().getName()");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java", "new ChatListener(this, supabase, cache, modules)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/MinecraftChatBridgeTask.java", "Bukkit.broadcast(line)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/MinecraftChatBridgeTask.java", "RECENT_DELIVERY_TTL_MILLIS");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/MinecraftChatBridgeTask.java", 'stringField(row, "lease_token")');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/MinecraftChatBridgeTask.java", 'body.addProperty("p_lease_token", leaseToken)');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/MinecraftChatBridgeTask.java", "modules.isEnabled(\"minecraft-chat-bridge\")");
requireText("bot/services/minecraft_bridge.py", "class MinecraftChatBridge(BaseMiddleware)");
requireText("bot/services/minecraft_bridge.py", "bot_bridge_enqueue_from_telegram");
requireText("bot/services/minecraft_bridge.py", "bot_bridge_claim_for_telegram");
requireText("bot/services/minecraft_bridge.py", "await self._refresh_community_chat_id()");
requireText("bot/services/minecraft_bridge.py", 'str(row.get("lease_token") or "")');
requireText("bot/services/minecraft_bridge.py", "html.escape(body)");
requireText("bot/main.py", "dp.message.outer_middleware(minecraft_chat_bridge)");
requireText("bot/main.py", "minecraft_chat_bridge.run(bot, worker_stop)");
requireText("bot/db/rpc.py", 'call_rpc_async("bot_bridge_enqueue_from_telegram"');
requireText("bot/db/rpc.py", "retries=2, retry_delay_seconds=0.5");
requireText("bot/db/rpc.py", 'call_rpc_async("mc_bridge_claim_for_telegram"');
requireText("bot/db/rpc.py", 'async def bot_bridge_finish_message(message_id, lease_token, status');
requireText("bot/db/rpc.py", '"p_lease_token": lease_token');
requireText("supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql", "alter table public.minecraft_chat_bridge_queue enable row level security");
requireText("supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql", "revoke all on table public.minecraft_chat_bridge_queue from public,anon,authenticated,service_role");
requireText("supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql", "public.bot_get_community_chat_id()");
requireText("supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql", "MESSAGE_EXPIRED");
requireText("supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql", "pg_advisory_xact_lock");
requireText("supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql", "return json_build_object('success',true,'id',queue_id,'duplicate',true);");
requireText("supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql", "add column if not exists lease_token uuid");
requireText("supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql", "u.minecraft_uuid=p_minecraft_uuid");
requireText("supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql", "pg_advisory_xact_lock");
requireText("supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql", "BRIDGE_LEASE_NOT_HELD");
requireText("supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql", "mc_bridge_finish_message(uuid,text,text,integer)");
requireText("supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql", "mc_bridge_finish_message(uuid,uuid,text,text,integer) to service_role");
requireText("supabase/migrations/20261024143000_prisma_minecraft_telegram_identity_binding.sql", "BRIDGE_TELEGRAM_IDENTITY_UNBOUND");
requireText("supabase/migrations/20261024143000_prisma_minecraft_telegram_identity_binding.sql", "u.telegram_id is not null");
requireText("supabase/migrations/20261024143000_prisma_minecraft_telegram_identity_binding.sql", "u.minecraft_uuid=p_minecraft_uuid");
requireText("supabase/migrations/20261024143000_prisma_minecraft_telegram_identity_binding.sql", "FOR SHARE");
requireText("packages/contracts/src/index.ts", "export const MINECRAFT_CHAT_BRIDGE_RPC");
requireText("modules/registry.json", "MINECRAFT_CHAT_BRIDGE_RPC");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", 'MC_STAFF_APPLY_MODERATION = "mc_staff_apply_moderation"');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", 'MC_STAFF_LIFT_MODERATION = "mc_staff_lift_moderation"');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java", 'MC_STAFF_MODERATION_HISTORY = "mc_staff_moderation_history"');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/ModerationCommand.java", "supabase.postRpcAsync(rpc, body)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/ModerationCommand.java", "PlayerCommandPreprocessEvent");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/ModerationCommand.java", "MAX_DURATION_MINUTES = 43_200");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/ModerationCommand.java", "friendlyError(detail)");
requireText("minecraft-plugin/build.gradle.kts", 'rootProject.file("../packages/contracts/minecraft-commands.json")');
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prismacommands");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PrismaHelpCommand.java", "Краткая справка");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PrismaHelpCommand.java", 'if (sender.hasPermission("prisma.command.ptp") && modules.isEnabled("minecraft-staff-teleport")) {');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PrismaHelpCommand.java", 'if (sender.hasPermission("prisma.command.tpall") && modules.isEnabled("minecraft-tpall")) {');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "CONFIRMATION_WINDOW_MILLIS = 20_000L");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "[TPALL] Результат");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "RpcNames.RECORD_MINECRAFT_EVENT");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "supabase.postRpcAsync(RpcNames.RECORD_MINECRAFT_EVENT, body)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "RpcNames.GET_STAFF_IDENTITY");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "authorizesTpAll(identity)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "Актуальные права не подтверждены. Телепортация отменена.");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java", "body.addProperty(\"p_event_type\", \"COMMAND\")");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prisma.command.tpall");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/staff/PlayerRoleDisplay.java", '"content_maker".equals(role)');
requireText("minecraft-plugin/src/main/resources/plugin.yml", "usage: /help [перемещение|кланы|авторизация|персонал]");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/homes/PlayerHomesStore.java", "MAX_HOMES = 2");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerHomeCommand.java", "player.teleportAsync(target)");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prisma.command.homes");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/spawn/SpawnPointsStore.java", "MAX_CUSTOM_SPAWN_ID = 999");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/SpawnCommand.java", "player.teleportAsync(target)");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prisma.command.spawnmanage");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prisma.command.journey");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prisma.command.hud");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java", "player.sendActionBar(");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java", "player.sendPlayerListHeaderAndFooter(");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java", "player.getPing()");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java", "Bukkit.getServer().getTPS()");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java", "Component.text(\"/help\", NamedTextColor.YELLOW)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java", "public void onQuit(PlayerQuitEvent event)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/graves/GraveStore.java", "TTL_MILLIS = TimeUnit.MINUTES.toMillis(10)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/graves/GraveStore.java", "StandardCopyOption.ATOMIC_MOVE");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/graves/GraveStore.java", "State.CLAIMING");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/GraveListener.java", "event.getDrops().clear()");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/GraveListener.java", "player.saveData()");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/GraveListener.java", "PersistentDataType.STRING");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/GraveCommand.java", "MAX_DISTANCE_SQUARED = 25.0d");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java", "new GraveStore(this)");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prisma.command.grave.admin");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "prisma.command.moderation");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "usage: /tempban <ник> <длительность> <причина>");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/staff/PlayerRoleDisplay.java", '"prisma.command.grave.admin"');
requireText("packages/contracts/minecraft-commands.json", '"command": "/grave"');
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java", "registerEvents(serverHud, this)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java", "new ServerHudTask(this, cache, modules)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java", "runTaskTimer(this, serverHud, 20L, 40L)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/journey/PlayerJourneyStore.java", "MAX_CHECKPOINTS = 5");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/journey/PlayerJourneyStore.java", "writer.execute");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/journey/PlayerJourneyStore.java", "StandardCopyOption.ATOMIC_MOVE");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerJourneyCommand.java", "case \"coords\" -> coords(player, args)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerJourneyCommand.java", "case \"lastdeath\" -> lastDeath(player, args)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerJourneyCommand.java", "case \"checkpoint\" -> checkpoint(player, args)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerJourneyCommand.java", "player.teleportAsync(target)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/PlayerJourneyListener.java", "PlayerDeathEvent");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/PlayerJourneyListener.java", "journey.recordDeath");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java", "new PlayerJourneyListener(this, journeyStore, modules)");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java", "if (journeyStore != null) journeyStore.close();");
requireText("minecraft-plugin/src/main/resources/plugin.yml", "usage: /spawn [0–999]");
requireText("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/WhitelistListener.java", "RpcNames.BIND_MINECRAFT_IDENTITY");
requireText("bot/utils/commands.py", 'BotCommand(command="help", description="Все команды")');
requireText("bot/main.py", "minecraft_commands.router");
requireText("site/src/components/SiteHeader.tsx", '["/commands", "Команды", "minecraft"]');
requireText("scripts/verify-architecture.mjs", "PRISMA architecture gate passed");

const workflowContracts = [
  [".github/workflows/prisma-ci.yml", true],
  [".github/workflows/participant-site.yml", false],
  [".github/workflows/plugin-artifact.yml", false],
  [".github/workflows/release.yml", false],
];

for (const workflow of [
  ".github/workflows/prisma-ci.yml",
  ".github/workflows/participant-site.yml",
  ".github/workflows/plugin-artifact.yml",
  ".github/workflows/release.yml",
]) {
  const source = read(workflow);
  if (!source.includes("runs-on: ubuntu-24.04")) {
    failures.push(workflow + ": GitHub-hosted jobs must pin ubuntu-24.04 for deterministic runner selection");
  }
  if (source.includes("runs-on: ubuntu-latest")) {
    failures.push(workflow + ": ubuntu-latest is forbidden in release CI; pin the runner image");
  }
}
for (const [workflow, shouldHavePrTrigger] of workflowContracts) {
  if (!requirePath(workflow)) continue;
  const source = read(workflow);
  const hasPrTrigger = source.includes("  pull_request:");
  if (hasPrTrigger !== shouldHavePrTrigger) {
    failures.push(`${workflow}: pull_request trigger contract violated`);
  }
}

const prismaCi = read(".github/workflows/prisma-ci.yml");
for (const requiredPath of [
  ".github/workflows/**",
  "VERSION",
  "bot/**",
  "minecraft-plugin/**",
  "packages/**",
  "panel/**",
  "scripts/**",
  "site/**",
  "supabase/**",
]) {
  if (!prismaCi.includes(`      - "${requiredPath}"`)) {
    failures.push(`.github/workflows/prisma-ci.yml: PR path filter is missing ${requiredPath}`);
  }
}
if (prismaCi.includes("site-diagnostics:")) {
  failures.push(".github/workflows/prisma-ci.yml: duplicated site-diagnostics job is forbidden");
}

const releaseWorkflow = read(".github/workflows/release.yml");
for (const fragment of [
  "  push:",
  "    branches: [main, \"release/**\"]",
  "  workflow_dispatch:",
]) {
  if (!releaseWorkflow.includes(fragment)) {
    failures.push(".github/workflows/release.yml: missing required release trigger " + fragment);
  }
}
if (releaseWorkflow.includes("  pull_request:")) {
  failures.push(".github/workflows/release.yml: pull_request trigger is forbidden");
}

const participantWorkflow = read(".github/workflows/participant-site.yml");
for (const fragment of [
  "  push:",
  "    branches: [main]",
  '      - "site/**"',
  '      - ".github/workflows/participant-site.yml"',
  "  workflow_dispatch:",
]) {
  if (!participantWorkflow.includes(fragment)) {
    failures.push(".github/workflows/participant-site.yml: missing required trigger/path " + fragment);
  }
}
if (participantWorkflow.includes("  pull_request:")) {
  failures.push(".github/workflows/participant-site.yml: pull_request trigger is forbidden");
}

const pluginWorkflow = read(".github/workflows/plugin-artifact.yml");
for (const fragment of [
  "  push:",
  "    branches: [main, rebuild/prisma-v3]",
  '      - "minecraft-plugin/**"',
  '      - ".github/workflows/plugin-artifact.yml"',
  "  workflow_dispatch:",
]) {
  if (!pluginWorkflow.includes(fragment)) {
    failures.push(".github/workflows/plugin-artifact.yml: missing required trigger/path " + fragment);
  }
}
if (pluginWorkflow.includes("  pull_request:")) {
  failures.push(".github/workflows/plugin-artifact.yml: pull_request trigger is forbidden");
}

const expensiveReleaseGuard = "if: startsWith(github.ref, 'refs/heads/release/') || github.event_name == 'workflow_dispatch'";
for (const stepName of [
  "Install participant site dependencies",
  "Build participant site",
  "Install panel dependencies",
  "Build panel",
  "Setup Python",
  "Setup Java",
  "Setup Gradle",
  "Build Minecraft plugin",
]) {
  const stepStart = releaseWorkflow.indexOf("      - name: " + stepName);
  if (stepStart < 0) {
    failures.push(".github/workflows/release.yml: missing step " + stepName);
    continue;
  }
  const nextStep = releaseWorkflow.indexOf("\n      - ", stepStart + 1);
  const block = releaseWorkflow.slice(stepStart, nextStep < 0 ? releaseWorkflow.length : nextStep);
  if (!block.includes(expensiveReleaseGuard)) {
    failures.push(".github/workflows/release.yml: " + stepName + " must be gated to release branches/manual dispatch");
  }
}

const ciWorkflow = prismaCi;
if (ciWorkflow.includes("  push:")) {
  failures.push(".github/workflows/prisma-ci.yml: push trigger is forbidden; PR validation must stay PR-only");
}

for (const [job, output] of [
  ["site", "site"],
  ["panel", "panel"],
  ["bot", "bot"],
  ["minecraft-plugin", "plugin"],
]) {
  const jobPattern = new RegExp(`  ${job}:\\n`);
  if (!jobPattern.test(ciWorkflow)) {
    failures.push(`.github/workflows/prisma-ci.yml: missing ${job} job`);
    continue;
  }
  const expectedCondition = job === "minecraft-plugin"
    ? "if: always() && (needs.changes.outputs.plugin == 'true' || needs.changes.result != 'success')"
    : `if: needs.changes.outputs.${output} == 'true'`;
  if (!ciWorkflow.includes(`needs: changes`) || !ciWorkflow.includes(expectedCondition)) {
    failures.push(`.github/workflows/prisma-ci.yml: ${job} job has an invalid change-detection condition`);
  }
}
if (!/  changes:\n/.test(ciWorkflow) ||
    !ciWorkflow.includes("steps.filter.outputs.site") ||
    !ciWorkflow.includes("steps.filter.outputs.panel") ||
    !ciWorkflow.includes("steps.filter.outputs.bot") ||
    !ciWorkflow.includes("steps.filter.outputs.plugin")) {
  failures.push(".github/workflows/prisma-ci.yml: component change-detection job is incomplete");
}
if (!ciWorkflow.includes('gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" --jq') ||
    !ciWorkflow.includes("GH_TOKEN: ${{ github.token }}") ||
    !ciWorkflow.includes("plugin=true") ||
    !ciWorkflow.includes("workflow_dispatch:")) {
  failures.push(".github/workflows/prisma-ci.yml: component detection must use PR file metadata and fail open for the Minecraft build");
}
if (!ciWorkflow.includes("needs.changes.result != 'success'")) {
  failures.push(".github/workflows/prisma-ci.yml: Minecraft plugin build must run when change detection fails before producing outputs");
}

if (!ciWorkflow.includes("  architecture:\n    needs: changes")) {
  failures.push(".github/workflows/prisma-ci.yml: architecture job must run after change detection");
}
if (!ciWorkflow.includes("  architecture:\n    needs: changes\n    if: always()")) {
  failures.push(".github/workflows/prisma-ci.yml: architecture gate must remain visible when component jobs are skipped");
}

const botJob = ciWorkflow.slice(ciWorkflow.indexOf("  bot:\n"), ciWorkflow.indexOf("  minecraft-plugin:\n"));
if (botJob.includes("pip install -r requirements.txt")) {
  failures.push(".github/workflows/prisma-ci.yml: bot PR check must not install dependencies; compileall is dependency-free");
}

const workflowDirectory = path.join(root, ".github/workflows");
if (fs.existsSync(workflowDirectory)) {
  for (const file of fs.readdirSync(workflowDirectory).filter((name) => /\.(yml|yaml)$/.test(name))) {
    const relative = path.join(".github/workflows", file);
    const source = read(relative);
    for (const match of source.matchAll(/^\s*uses:\s*([^\s#]+)@([^\s#]+)\s*(?:#.*)?$/gm)) {
      const action = match[1];
      const ref = match[2];
      if (action.startsWith("./")) continue;
      if (!/^[0-9a-f]{40}$/i.test(ref)) {
        failures.push(`${relative}: third-party action ${action} must be pinned to a 40-character commit SHA (found @${ref})`);
      }
    }
  }
}

const siteEnv = read("site/.env.example");
for (const key of [
  "NEXT_PUBLIC_SUPABASE_URL=",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=",
  "SUPABASE_SERVICE_ROLE_KEY=",
]) {
  if (!siteEnv.includes(key)) {
    failures.push(`site/.env.example: missing ${key}`);
  }
}

const panelEnv = read("panel/.env.example");
for (const key of [
  "NEXT_PUBLIC_SUPABASE_URL=",
  "SUPABASE_SERVICE_ROLE_KEY=",
  "ADMIN_TELEGRAM_IDS=",
]) {
  if (!panelEnv.includes(key)) {
    failures.push(`panel/.env.example: missing ${key}`);
  }
}

const botEnv = read("bot/.env.example");
for (const key of [
  "BOT_TOKEN=",
  "SUPABASE_URL=",
  "SUPABASE_SERVICE_ROLE_KEY=",
  "REDIS_URL=",
  "PRISMA_ENV=",
]) {
  if (!botEnv.includes(key)) {
    failures.push(`bot/.env.example: missing ${key}`);
  }
}

requireText("panel/src/app/api/modules/route.ts", "STAFF_MODULE_RPC.set");

if (failures.length) {
  console.error("PRISMA release verification failed:");
  console.error(failures.map((failure) => `- ${failure}`).join("\n"));
  process.exit(1);
}

console.log(`PRISMA release ${expected}: metadata, runtime contracts, migration inventory and secret-file hygiene passed`);

