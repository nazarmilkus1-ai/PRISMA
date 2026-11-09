import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

execFileSync(process.execPath, [path.join(root, "scripts/verify-modules.mjs")], { stdio: "inherit" });

// PRISMA architecture checks below intentionally stay in this file so existing
// release CI keeps one canonical architecture gate.

function filesUnder(relative) {
  const base = path.join(root, relative);
  if (!fs.existsSync(base)) return [];
  const out = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.(ts|tsx|py|java)$/.test(entry.name)) out.push(path.relative(root, full));
    }
  };
  walk(base);
  return out;
}

const failures = [];

const botModuleGateMain = read("bot/main.py");
const botModuleRuntime = read("bot/utils/module_runtime.py");
const botRpcGateway = read("bot/db/rpc.py");
const botNotificationWorker = read("bot/services/notifications.py");
for (const marker of [
  'from utils.module_runtime import attach_module_dispatch_gate, attach_module_gate',
  '(application.router, "applications")',
  '(profile.router, "players")',
  '(reports.router, "reports")',
  '(polls.router, "voting")',
  '(clans.router, "clans")',
  '(news.router, "public-content")',
  '(social.router, "social")',
  '(market.router, "market")',
  '(minecraft_commands.router, "minecraft")',
  '(moderation.router, "moderation")',
  '(automod.router, "moderation")',
]) {
  if (!botModuleGateMain.includes(marker)) failures.push("bot main is missing runtime module gate: " + marker);
}
if (!botModuleRuntime.includes("MODULE_STATE_CACHE") && !botModuleRuntime.includes("_STATE_CACHE")) {
  failures.push("bot module runtime must cache module states to avoid an RPC for every update");
}

for (const marker of [
  "class ModuleDispatchMiddleware",
  "def attach_module_dispatch_gate(",
  "self.command_modules.get(command)",
  "self.text_patterns",
  "event.answer(notice)",
  "event.answer(notice, show_alert=True)",
]) {
  if (!botModuleRuntime.includes(marker)) {
    failures.push("bot dispatch-level module gate is missing required behavior: " + marker);
  }
}
for (const marker of [
  "attach_module_dispatch_gate(",
  "player.router,",
  "chat_commands.router,",
  "admin.router,",
  '"battle": "battles"',
  '"app_approve": "applications"',
  '"admin:reports": "reports"',
  '"admin:server": "minecraft"',
  '"event:reg:*": "events"',
  '"клан": "clans"',
  '"брак": "social"',
  'r"^клан',
]) {
  if (!botModuleGateMain.includes(marker)) {
    failures.push("mixed bot router is missing feature module dispatch gate: " + marker);
  }
}
for (const marker of [
  "get_public_module_states",
  "dependsOn",
  "states.get(current) is not True",
  "return False",
]) {
  if (!botModuleRuntime.includes(marker)) failures.push("bot module runtime must fail closed and honor dependencies: " + marker);
}
if (!botRpcGateway.includes('call_rpc_async("get_public_module_states", {})')) {
  failures.push("bot module state reads must use the centralized RPC gateway");
}
if (!botNotificationWorker.includes('is_module_effectively_enabled("notifications")')) {
  failures.push("bot notification worker must honor the notifications module state");
}

const migrationFiles = fs.existsSync(path.join(root, "supabase/migrations"))
  ? fs.readdirSync(path.join(root, "supabase/migrations")).filter((file) => /^\d{14}_.+\.sql$/.test(file))
  : [];
const migrationVersions = new Map();
for (const file of migrationFiles) {
  const version = file.slice(0, 14);
  const existing = migrationVersions.get(version) ?? [];
  existing.push(file);
  migrationVersions.set(version, existing);
}
for (const [version, files] of migrationVersions) {
  if (files.length > 1) {
    failures.push(`duplicate Supabase migration version ${version}: ${files.join(", ")}`);
  }
}

const migrationPaths = fs.readdirSync(path.join(root, "supabase/migrations"))
  .filter((file) => /^\d{14}_.+\.sql$/.test(file))
  .sort();
const triggerGuardVersion = "20260928153000";
for (const file of migrationPaths) {
  const version = file.slice(0, 14);
  if (version <= triggerGuardVersion) continue;
  const source = fs.readFileSync(path.join(root, "supabase/migrations", file), "utf8");
  const publicFunctionNames = [...source.matchAll(/(?:create|replace)\s+(?:or\s+replace\s+)?function\s+public\.([a-zA-Z0-9_]+)/gi)]
    .map((match) => match[1]);
  for (const name of new Set(publicFunctionNames)) {
    const access = new RegExp(`(?:grant|revoke)\\s+(?:(?:execute|all)\\s+)?on\\s+function\\s+public\\.${name}\\b`, "i");
    if (!access.test(source)) {
      failures.push(`${file}: public function ${name} must explicitly declare EXECUTE ACL after the global function guard`);
    }
    const blockMatch = source.match(new RegExp(`(?:create\\s+or\\s+replace|create|replace)\\s+function\\s+public\\.${name}\\b[\\s\\S]*?(?=\\n\\s*(?:create\\s+or\\s+replace|create|replace)\\s+function\\s+public\\.|$)`, "i"));
    const functionBlock = blockMatch?.[0] ?? "";
    const hasEmptySearchPath = /search_path\s*(?:=|to)\s*''/i.test(functionBlock);
    const laterDefinitionPinsSearchPath = hasEmptySearchPath || migrationPaths.some((laterFile) => {
      if (laterFile.slice(0, 14) <= version) return false;
      const laterSource = fs.readFileSync(path.join(root, "supabase/migrations", laterFile), "utf8");
      const declaration = "function public." + name.toLowerCase() + "(";
      const declarationIndex = laterSource.toLowerCase().indexOf(declaration);
      if (declarationIndex < 0) return false;
      const terminators = ["$function$;", "$$;"]
        .map((terminator) => laterSource.indexOf(terminator, declarationIndex))
        .filter((index) => index >= 0);
      if (!terminators.length) return false;
      const laterFunctionBlock = laterSource.slice(declarationIndex, Math.min(...terminators) + 11);
      return /security\s+definer/i.test(laterFunctionBlock) &&
        /search_path\s*(?:=|to)\s*''/i.test(laterFunctionBlock);
    });
    if (/security\s+definer/i.test(functionBlock) && !hasEmptySearchPath && !laterDefinitionPinsSearchPath) {
      failures.push(`${file}: SECURITY DEFINER public function ${name} must pin search_path to an empty path`);
    }
  }
}

const publicFunctionGuard = read("supabase/migrations/20260928153000_prisma_public_function_execute_guard.sql");
if (!publicFunctionGuard.includes("CREATE EVENT TRIGGER") && !publicFunctionGuard.includes("create event trigger")) {
  failures.push("public function execute guard migration must create a DDL event trigger");
}
if (!publicFunctionGuard.includes("REVOKE EXECUTE ON FUNCTION") && !publicFunctionGuard.includes("revoke execute on function")) {
  failures.push("public function execute guard migration must revoke implicit EXECUTE");
}

const mapHistoryGateway = read("supabase/migrations/20260928165750_prisma_staff_map_history_gateway.sql");
if (!mapHistoryGateway.includes("staff_get_map_history") ||
    !mapHistoryGateway.includes("map.history.view") ||
    !mapHistoryGateway.includes("revoke all on function public.staff_get_map_history(integer)")) {
  failures.push("staff map history gateway must be an authenticated RBAC RPC with explicit EXECUTE ACL");
}

const mapHistoryPage = read("site/src/app/map/history/page.tsx");
if (mapHistoryPage.includes(".from(") || mapHistoryPage.includes(".select(") || !mapHistoryPage.includes("STAFF_RPC.mapHistory")) {
  failures.push("site map history page must use the canonical STAFF_RPC.mapHistory gateway");
}

const privateSchemaLockdown = read("supabase/migrations/20260928164254_prisma_private_schema_acl_reassert.sql");
if (!privateSchemaLockdown.includes("revoke usage on schema private from authenticated, anon") ||
    !privateSchemaLockdown.includes("revoke all on all functions in schema private from authenticated, anon")) {
  failures.push("private schema ACL reassertion must revoke client-role schema usage and function privileges");
}

const privatePermissionHelperGrant = read("supabase/migrations/20260928171217_prisma_private_permission_helper_runtime_grant.sql");
for (const statement of [
  "grant usage on schema private to authenticated",
  "grant execute on function private.has_permission(text) to authenticated",
  "revoke usage on schema private from anon",
  "revoke execute on function private.has_permission(text) from anon",
]) {
  if (!privatePermissionHelperGrant.toLowerCase().includes(statement)) {
    failures.push("private permission helper runtime grant is missing required: " + statement);
  }
}

const marketCountFix = read("supabase/migrations/20260928164012_prisma_market_close_listing_count_fix.sql");
if (!marketCountFix.includes("select stats.closed_count") || !marketCountFix.includes("from closed") || !marketCountFix.includes("inquiries_closed")) {
  failures.push("market close-listing migration must return the number of inquiries actually closed");
}

const triggerFunctionAclLockdown = read("supabase/migrations/20260928160000_prisma_trigger_function_execute_lockdown.sql");
for (const fn of [
  "chat_logs_activity_after_insert",
  "prevent_audit_mutation",
  "prisma_clear_legacy_mojang_uuid",
]) {
  const revoke = `revoke execute on function public.${fn}()`;
  if (!triggerFunctionAclLockdown.toLowerCase().includes(revoke)) {
    failures.push(`trigger-only function ${fn} must have direct EXECUTE lockdown`);
  }
}

const playerStatsTask = read("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/PlayerStatsTask.java");
for (const marker of [
  "pendingWrites.compute(playerUuid",
  "previous.handle((ignored, failure) -> null)",
  "pendingWrites.remove(playerUuid, next)",
  "!cache.hasStatsBaseline(playerUuid)",
  "awaitPendingWrites(UUID playerUuid)",
  "persistQuitSnapshot(Player player)",
  "pendingWrites.compute(snapshot.playerUuid()",
  "persistQuitSnapshotAttempt(QuitSnapshot snapshot, int attempt)",
  "snapshot.userId() == null || snapshot.userId().isBlank()",
  "RpcNames.GET_MINECRAFT_USER_V2, identityRequest",
  'identityRequest.addProperty("p_minecraft_uuid", snapshot.playerUuid().toString())',
  'stringField(user, "id")',
  "private static String stringField(JsonObject obj, String key)",
  "retryQuitSnapshot(QuitSnapshot snapshot, int attempt, CompletableFuture<Void> result)",
  "safeAdd(long left, long right)",
  "MAX_QUIT_SNAPSHOT_RETRIES = 12",
  "boolean baselineLoaded",
  "if (snapshot.baselineLoaded())",
  "final quit snapshot write failed",
  "attempt >= MAX_QUIT_SNAPSHOT_RETRIES",
  "retryDisposition(int attempt)",
]) {
  if (!playerStatsTask.includes(marker)) {
    failures.push("PlayerStatsTask must serialize per-player snapshots and clean up completed writes: " + marker);
  }
}
if (!playerStatsTask.includes("enqueueWrite(playerUuid, nickname, statisticsPayload(")) {
  failures.push("PlayerStatsTask must enqueue the captured statistics payload through the per-player write queue");
}
const compactPlayerStatsTask = playerStatsTask.replace(/\s+/g, " ");
for (const [name, signature] of [
  ["persistQuitPayloadWithRetry", "persistQuitPayloadWithRetry( QuitSnapshot snapshot, JsonObject payload, int attempt, CompletableFuture<Void> result )"],
  ["retryQuitPayload", "retryQuitPayload( QuitSnapshot snapshot, JsonObject payload, int attempt, CompletableFuture<Void> result )"],
]) {
  if (!compactPlayerStatsTask.includes(signature)) {
    failures.push("PlayerStatsTask must implement the quit snapshot retry stage: " + name);
  }
}
if (playerStatsTask.includes('player.getName() + ": " + error.getMessage()')) {
  failures.push("PlayerStatsTask must not access Bukkit Player objects from async database callbacks");
}
if (!read("minecraft-plugin/src/main/java/team/prisma/plugin/cache/PlayerStateCache.java").includes("markStatsBaselineLoaded(UUID playerUuid)")) {
  failures.push("PlayerStateCache must expose explicit player-stat baseline readiness");
}
const joinQuitListener = read("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/JoinQuitListener.java");
const prismaPlugin = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");

if (!playerStatsTask.includes("if (player == null || !player.isOnline()) return;")) {
  failures.push("PlayerStatsTask live synchronization must only read Bukkit Player state while the player is online");
}
for (const marker of [
  "baselineLoaded ? blocksPlaced : 0L",
  "baselineLoaded ? blocksBroken : 0L",
  "baselineLoaded ? mobsKilled : 0L",
  "player, userId == null ? \"\" : userId,",
  "persistQuitPayloadWithRetry(snapshot, snapshot.payload(), attempt, result)",
  "persistQuitPayloadWithRetry(snapshot, payload, attempt, result)",
  "retryQuitPayload(snapshot, payload, attempt, result)",
]) {
  if (!playerStatsTask.includes(marker)) {
    failures.push("PlayerStatsTask quit snapshots must be captured once and retry frozen payloads idempotently: " + marker);
  }
}

for (const [source, markers, label] of [
  [playerStatsTask, ["public void sync(Player player)", "RpcNames.UPSERT_PLAYER_STATS"], "PlayerStatsTask"],
  [joinQuitListener, ["PlayerStatsTask playerStatsTask", "runTask(plugin, () -> {", "playerStatsTask.sync(player);"], "JoinQuitListener"],
  [prismaPlugin, ["PlayerStatsTask playerStatsTask = new PlayerStatsTask", "playerStatsTask,", "long statsInitialDelayTicks = 30L * 20L", "statsTicks"], "PrismaPlugin"],
]) {
  for (const marker of markers) {
    if (!source.includes(marker)) {
      failures.push(label + ": missing player-stats runtime contract " + marker);
    }
  }
}

// Protect the persistence baseline: only sync after GET_PLAYER_STATS completed and on the main thread.
const onQuitIndex = joinQuitListener.indexOf("public void onQuit(PlayerQuitEvent event)");
const joinBootstrap = onQuitIndex < 0 ? joinQuitListener : joinQuitListener.slice(0, onQuitIndex);
const quitHandler = onQuitIndex < 0 ? "" : joinQuitListener.slice(onQuitIndex);
const bootstrapSyncCalls = (joinBootstrap.match(/playerStatsTask\.sync\(player\);/g) ?? []).length;
const statsLoadIndex = joinBootstrap.indexOf("supabase.postRpcAsync(RpcNames.GET_PLAYER_STATS");
const statsSyncIndex = joinBootstrap.indexOf("playerStatsTask.sync(player);");
const statsSyncGuardIndex = joinBootstrap.lastIndexOf(
  "if (!isCurrentSession(player, playerUuid, userId, sessionToken)",
  statsSyncIndex,
);
const statsBaselineReadyIndex = joinBootstrap.indexOf("cache.markStatsBaselineLoaded(playerUuid);");
if (bootstrapSyncCalls !== 1) {
  failures.push("JoinQuitListener must sync statistics exactly once after loading the persisted baseline");
}
if (statsLoadIndex < 0 || statsSyncIndex < statsLoadIndex ||
    statsSyncGuardIndex < statsLoadIndex || statsBaselineReadyIndex < statsLoadIndex ||
    statsSyncIndex < statsBaselineReadyIndex) {
  failures.push("JoinQuitListener must await the persisted baseline, validate the active session, and mark readiness before syncing");
}
const identityLookupStart = joinQuitListener.indexOf("private void requestIdentityLookup(");
const identityRetryStart = joinQuitListener.indexOf("private void scheduleIdentityRetry(", identityLookupStart);
const identityLookupMethod = identityLookupStart < 0 || identityRetryStart < 0
  ? ""
  : joinQuitListener.slice(identityLookupStart, identityRetryStart);
if (!identityLookupMethod.includes("catch (RuntimeException lookupError)") ||
    !identityLookupMethod.includes("scheduleIdentityRetry(player, playerUuid, nickname, worldName, sessionToken);")) {
  failures.push("JoinQuitListener must retry identity lookup when starting the RPC throws before an async future is returned");
}

for (const marker of [
  "scheduleStatsBaselineRetry",
  "STATS_BASELINE_RETRY_BASE_TICKS = 20L * 30L",
  "STATS_BASELINE_RETRY_MAX_TICKS = 20L * 60L * 5L",
  "MAX_STATS_BASELINE_BACKOFF_STAGE = 4",
  "statsBaselineRetryStages.getOrDefault(playerUuid, 0)",
  "statsBaselineRetryStages.remove(playerUuid)",
  "STATS_BASELINE_RETRY_BASE_TICKS * (1L << boundedStage)",
  "Math.min(exponentialDelay, STATS_BASELINE_RETRY_MAX_TICKS)",
  "runTaskLater(plugin,",
  'hasNonNegativeCount(stats, "blocks_placed")',
  "playerSessions.put(playerUuid, sessionToken)",
  "playerSessions.remove(playerUuid)",
  "isCurrentConnection(player, playerUuid, sessionToken)",
  "private boolean isCurrentConnection(Player player, UUID playerUuid, Object sessionToken)",
  "requestIdentityLookup(player, playerUuid, nickname, worldName, sessionToken)",
  "private void requestIdentityLookup(Player player, UUID playerUuid, String nickname, String worldName, Object sessionToken)",
  "scheduleIdentityRetry(player, playerUuid, nickname, worldName, sessionToken)",
  "private void scheduleIdentityRetry(Player player, UUID playerUuid, String nickname, String worldName, Object sessionToken)",
  'user == null || user.has("error")',
  "MAX_IDENTITY_LOOKUP_RETRIES = 12",
  "IDENTITY_RETRY_DELAY_TICKS",
  "identityRetryAttempts.getOrDefault(playerUuid, 0)",
  "identityRetryAttempts.put(playerUuid, attempts + 1)",
  "identityRetryAttempts.remove(playerUuid)",
]) {
  if (!joinQuitListener.includes(marker)) {
    failures.push("JoinQuitListener must retry failed baseline loads and ignore stale connection callbacks: " + marker);
  }
}
if (!joinQuitListener.includes("awaitPendingWrites(playerUuid)") || !joinQuitListener.includes("cache.markStatsBaselineLoaded(playerUuid)")) {
  failures.push("JoinQuitListener must wait for previous writes and mark the persisted baseline loaded before syncing");
}
if (!quitHandler.includes("playerStatsTask.persistQuitSnapshot(player);") ||
    quitHandler.indexOf("playerStatsTask.persistQuitSnapshot(player);") > quitHandler.indexOf("cache.onQuit(playerUuid)")) {
  failures.push("JoinQuitListener must persist a final statistics snapshot before clearing the player cache");
}
if (!playerStatsTask.includes("cache.hasStatsBaseline(playerUuid)") ||
    !playerStatsTask.includes("snapshot.blocksPlacedDelta()") ||
    !playerStatsTask.includes("snapshot.blocksBrokenDelta()") ||
    !playerStatsTask.includes("snapshot.mobsKilledDelta()")) {
  failures.push("PlayerStatsTask must save quit-time stat deltas against the DB baseline if baseline loading is pending");
}
if (!playerStatsTask.includes("pendingWrites.compute(snapshot.playerUuid()") ||
    !playerStatsTask.includes("return ready.thenCompose(ignored -> persistQuitSnapshotAttempt(snapshot, 0))")) {
  failures.push("PlayerStatsTask must reserve the full quit baseline-read/write operation in the per-player queue");
}
if (!read("minecraft-plugin/src/main/java/team/prisma/plugin/cache/PlayerStateCache.java").includes("blocksPlaced.merge(playerUuid, Math.max(0L, initialBlocksPlaced), Long::sum)")) {
  failures.push("PlayerStateCache must not discard block placements received during async identity bootstrap");
}

const staffPermissionCache = read("minecraft-plugin/src/main/java/team/prisma/plugin/staff/StaffPermissionCache.java");
if (!staffPermissionCache.includes("runOnMain(() -> callback.accept(allowed))")
    || !staffPermissionCache.includes("runOnMain(() -> callback.accept(false))")) {
  failures.push("StaffPermissionCache callbacks must return to Bukkit's main thread");
}
if (!staffPermissionCache.includes("PERMISSION_TTL_NANOS")
    || !staffPermissionCache.includes("System.nanoTime() - entry.checkedAtNanos() > PERMISSION_TTL_NANOS")
    || !staffPermissionCache.includes("put(playerUuid, permission, false)")) {
  failures.push("StaffPermissionCache must expire stale grants and fail closed when permission checks fail");
}
const roleDisplay = read("minecraft-plugin/src/main/java/team/prisma/plugin/staff/PlayerRoleDisplay.java");
if (!roleDisplay.includes("applyOnlinePlayer(playerUuid, identity)")
    || !roleDisplay.includes("Player online = Bukkit.getPlayer(playerUuid)")) {
  failures.push("PlayerRoleDisplay must resolve and mutate players on Bukkit's main thread");
}

const villageManager = read("minecraft-plugin/src/main/java/team/prisma/plugin/clans/VillageManager.java");
if (!villageManager.includes("private volatile Map<UUID, Village> villages = Map.of();")
    || !villageManager.includes("villages = Map.copyOf(next)")
    || villageManager.includes("villages.clear()")
    || villageManager.includes("villages.putAll(next)")) {
  failures.push("VillageManager must publish an atomic immutable snapshot for territory protection");
}
if (!villageManager.includes("refreshInFlight.compareAndSet(false, true)")
    || !villageManager.includes("refreshInFlight.set(false)")
    || !villageManager.includes("keeping the last known-good snapshot")) {
  failures.push("VillageManager must serialize refreshes and preserve the last good village snapshot on malformed responses");
}

const moderationPoll = read("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ModerationPollTask.java");
if (moderationPoll.includes("RpcNames.GET_PENDING_MODERATION")) {
  failures.push("ModerationPollTask must use the atomic mc_claim_pending_moderation lease gateway");
}
if (!moderationPoll.includes("RpcNames.CLAIM_PENDING_MODERATION")) {
  failures.push("ModerationPollTask is missing the atomic moderation claim gateway");
}

const pluginFiles = filesUnder("minecraft-plugin/src/main/java")
  .filter((file) => file.endsWith(".java"));

if (!pluginFiles.length) {
  failures.push("minecraft-plugin source scan returned no Java files");
}

for (const file of pluginFiles) {
  const source = read(file);
  if (/\.(postAsync|patchAsync|deleteAsync|getSync|patchSync|postSync|getAsync)\(\s*"\//.test(source)) {
    failures.push(`${file}: Minecraft plugin must use RPC gateways instead of direct REST CRUD`);
  }
}

const supabaseClient = read("minecraft-plugin/src/main/java/team/prisma/plugin/http/SupabaseClient.java");
if (/public\s+(?:void|JsonArray|CompletableFuture<[^>]+>)\s+(?:getSync|patchSync|postSync|getAsync|patchAsync|postAsync|deleteAsync)\s*\(/.test(supabaseClient)) {
  failures.push("SupabaseClient.java: legacy direct REST CRUD methods must not exist");
}
if (!/public JsonObject postRpcSync\(/.test(supabaseClient) || !/public CompletableFuture<JsonObject> postRpcAsync\(/.test(supabaseClient)) {
  failures.push("SupabaseClient.java: canonical RPC transport methods are missing");
}

const pluginRpcFiles = filesUnder("minecraft-plugin/src/main/java").filter((file) => file.endsWith(".java"));
const rpcRegistry = read("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java");
if (!rpcRegistry.includes("public final class RpcNames")) {  failures.push("Minecraft plugin RPC registry class is missing");
}
for (const file of pluginRpcFiles) {
  const source = read(file);
  if (/postRpc(?:Sync|Async)\(\s*"[^"]+"/.test(source)) {
    failures.push(file + ": plugin RPC transport must use RpcNames constants");
  }
  if (/\/rpc\/[A-Za-z0-9_]+/.test(source)) {
    failures.push(file + ": plugin RPC endpoint paths must not be hardcoded");
  }
  if (/\bcall\(\s*[^,]+,\s*"[^"]+"/.test(source)) {
    failures.push(file + ": plugin generic call() must use RpcNames constants");
  }
}
if (!rpcRegistry.includes('BIND_MINECRAFT_IDENTITY = "mc_bind_minecraft_identity"')) {
  failures.push("plugin RPC registry is missing BIND_MINECRAFT_IDENTITY");
}
if (!rpcRegistry.includes('GET_MINECRAFT_USER = "get_minecraft_user"')) {
  failures.push("plugin RPC registry is missing GET_MINECRAFT_USER");
}
if (!rpcRegistry.includes('CLAIM_PENDING_MODERATION = "mc_claim_pending_moderation"')) {
  failures.push("plugin RPC registry is missing CLAIM_PENDING_MODERATION");
}
if (!rpcRegistry.includes('UPSERT_PLAYER_STATS = "mc_upsert_player_stats"')) {
  failures.push("plugin RPC registry is missing UPSERT_PLAYER_STATS");
}
if (!rpcRegistry.includes('UPSERT_SERVER_HEARTBEAT = "upsert_server_heartbeat"')) {
  failures.push("plugin RPC registry is missing UPSERT_SERVER_HEARTBEAT");
}

for (const file of filesUnder("bot/db").concat(filesUnder("bot/services"))) {
  const source = read(file);
  if (/supabase\.table\(|supabase\.from\(|\.insert\(|\.update\(|\.delete\(/.test(source)) {
    failures.push(`${file}: direct Supabase CRUD is forbidden in bot DB/service layers`);
  }
}

for (const file of filesUnder("panel/src/app/dashboard")) {
  if (!file.endsWith("page.tsx")) continue;
  const source = read(file);
  if (!/requireAdmin(Context)?\(/.test(source)) {
    failures.push(`${file}: dashboard page must enforce a permission guard`);
  }
}

const requireAdmin = read("panel/src/lib/require-admin.ts");
if (requireAdmin.includes("createSupabaseAdminClient")) {
  failures.push("panel/src/lib/require-admin.ts: service-role RBAC access is forbidden");
}

const panelRateLimit = read("panel/src/lib/rate-limit.ts");
if (!panelRateLimit.includes("AUTH_RATE_LIMIT_RPC.consume")) {
  failures.push("panel rate-limit helper must use shared consume_login_rate_limit contract");
}
if (panelRateLimit.includes('rpc("consume_login_rate_limit"')) {
  failures.push("panel rate-limit helper must not hardcode consume_login_rate_limit");
}
if (!panelRateLimit.includes("return false;")) {
  failures.push("panel rate-limit helper must fail closed when the limiter RPC fails");
}

const panelTelegramVerify = read("panel/src/app/api/auth/telegram/verify/route.ts");
for (const marker of [
  'consumeAuthRateLimit("telegram-verify-ip:"',
  'consumeAuthRateLimit("telegram-verify-session:"',
  '.eq("status", "sent")',
  '.eq("code", row.code)',
  '.update({ status: "verified" })',
]) {
  if (!panelTelegramVerify.includes(marker)) {
    failures.push("panel Telegram verification must include atomic/session-scoped auth hardening marker " + marker);
  }
}
if (panelTelegramVerify.includes('rpc("consume_login_rate_limit"')) {
  failures.push("panel Telegram verification must not hardcode auth rate-limit RPC");
}

const siteTelegramVerify = read("site/src/app/api/auth/telegram/verify/route.ts");
for (const marker of [
  'consumeAuthRateLimit("site-telegram-verify-ip:"',
  'consumeAuthRateLimit("site-telegram-verify-session:"',
  '.eq("status", "sent")',
  '.eq("code", row.code)',
  '.update({ status: "verified" })',
]) {
  if (!siteTelegramVerify.includes(marker)) {
    failures.push("site Telegram verification must include atomic/session-scoped auth hardening marker " + marker);
  }
}
if (siteTelegramVerify.includes('rpc("consume_login_rate_limit"')) {
  failures.push("site Telegram verification must not hardcode auth rate-limit RPC");
}

const exportApi = read("panel/src/app/api/export/route.ts");
if (!exportApi.includes('resource === "users" ? "player.view"')) {
  failures.push("panel export of player_360 must require player.view");
}
const notify = read("panel/src/lib/notify.ts");
if (notify.includes("createSupabaseAdminClient") || /\.from\("notifications"\)|\.insert\(/.test(notify)) {
  failures.push("panel/src/lib/notify.ts: direct notification queue mutation is forbidden");
}


const panelRpcContractFiles = filesUnder("panel/src/app/api")
  .concat(filesUnder("panel/src/app/dashboard"))
  .concat(filesUnder("panel/src/lib"));
for (const file of panelRpcContractFiles) {
  if (!file.endsWith(".ts") && !file.endsWith(".tsx")) continue;
  const source = read(file);
  if (/(?:db|supabase|userClient)\.rpc(\s*\(\s*)["']staff_[^"']+["']/.test(source)) {
    failures.push(file + ": panel staff RPCs must use STAFF_RPC shared contracts");
  }
}

const contractsSource = read("packages/contracts/src/index.ts");
const requiredStaffContracts = [
  ["authContext", "staff_get_auth_context"],
  ["authSecurity", "staff_get_auth_security"],
  ["dashboardOverview", "staff_get_dashboard_overview"],
  ["adminRegistry", "staff_get_admin_registry"],
  ["manageAdmin", "staff_manage_admin"],
  ["applications", "staff_list_applications"],
  ["application", "staff_get_application"],
  ["decideApplication", "staff_decide_application"],
  ["appeals", "staff_list_appeals"],
  ["appeal", "staff_get_appeal"],
  ["manageAppeal", "staff_manage_appeal"],
  ["reports", "staff_list_reports"],
  ["report", "staff_get_report"],
  ["reportStats", "staff_report_stats"],
  ["updateReport", "staff_update_report"],
  ["players", "staff_list_players"],
  ["player360", "staff_get_player_360"],
  ["moderationSearchPlayers", "staff_search_moderation_players"],
  ["moderationPlayer", "staff_get_moderation_player"],
  ["applyModeration", "staff_apply_moderation"],
  ["revokeModeration", "staff_revoke_moderation"],
  ["clans", "staff_list_clans"],
  ["clanMemberRole", "staff_update_clan_member_role"],
  ["events", "staff_list_events"],
  ["manageEvent", "staff_manage_event"],
  ["setEventResult", "staff_set_event_result"],
  ["market", "staff_get_market"],
  ["marketInquiries", "staff_get_market_inquiries"],
  ["manageMarket", "staff_manage_market"],
  ["news", "staff_list_news"],
  ["manageNews", "staff_manage_news"],
  ["polls", "staff_list_polls"],
  ["createPoll", "staff_create_poll"],
  ["managePoll", "staff_manage_poll"],
  ["notifications", "staff_list_notifications"],
  ["monitoring", "staff_get_monitoring"],
  ["onboarding", "staff_get_onboarding"],
  ["onboardingBroadcast", "staff_broadcast_onboarding"],
  ["analytics", "staff_get_analytics"],
  ["auditLogs", "staff_get_audit_logs"],
  ["securitySnapshot", "staff_get_security_snapshot"],
  ["enqueueNotification", "staff_enqueue_notification"],
  ["communityChatId", "staff_get_community_chat_id"],
  ["chatSettings", "staff_get_chat_settings"],
  ["manageChatSettings", "staff_manage_chat_settings"],
  ["deleteChatSettings", "staff_delete_chat_settings"],
  ["mapHistory", "staff_get_map_history"],
];
for (const [field, rpc] of requiredStaffContracts) {
  if (!new RegExp(field + "\\s*:\\s*[\"']" + rpc + "[\"']").test(contractsSource)) {
    failures.push("packages/contracts/src/index.ts: STAFF_RPC." + field + " must map to " + rpc);
  }
}
if (!contractsSource.includes("export const STAFF_RPC")) {
  failures.push("packages/contracts/src/index.ts: STAFF_RPC export is missing");
}

const participantApiFiles = filesUnder("site/src/app/api")
  .filter((file) => /\.(ts|tsx)$/.test(file))
  .filter((file) => !file.startsWith("site/src/app/api/auth/"));
for (const file of participantApiFiles) {
  const source = read(file);
  if (/\.from\(\s*["'][^"']+["']/.test(source)) {
    failures.push(`${file}: participant API must read/write state through gateway/RPC contracts`);
  }
}

for (const file of filesUnder("site/src/app/api")) {
  if (file.startsWith("site/src/app/api/auth/")) continue;
  const source = read(file);

  if (/(?:db|supabase)\.rpc\(\s*["\'](?:participant_|site_submit_application)/.test(source)) {
    failures.push(`${file}: participant APIs must use shared RPC contract constants instead of raw participant RPC names`);
  }

  if (source.includes("createSupabaseAdminClient")) {
    failures.push(`${file}: participant API must not use service-role client outside auth`);
  }

  if (/\.(insert|update|delete)\(/.test(source)) {
    failures.push(`${file}: participant API must mutate state through an RPC gateway`);
  }
}

const participantAppRouteFiles = filesUnder("site/src/app/app")
  .filter((file) => file.endsWith("/page.tsx") || file === "site/src/app/app/page.tsx");

for (const file of participantAppRouteFiles) {
  const source = read(file);
  const shim = source.match(/import\s+Page\s+from\s+"@\/app\/([^"]+)"\s*;/);
  if (!shim || !/export\s+default\s+Page\s*;/.test(source)) continue;

  const targetFile = path.join("site/src/app", shim[1]);
  if (!fs.existsSync(path.join(root, targetFile))) continue;

  const targetSource = read(targetFile);
  const routePath = "/" + file
    .replace(/^site\/src\/app\/app\//, "")
    .replace(/\/page\.tsx$/, "");

  const redirectsToSameAppRoute =
    targetSource.includes('redirect("/app' + routePath + '")') ||
    targetSource.includes("redirect('/app" + routePath + "')");

  if (redirectsToSameAppRoute) {
    failures.push(
      file + ": route shim targets " + targetFile +
      ", which redirects back to " + routePath +
      "; recursive participant route detected",
    );
  }
}

const marketApi = read("site/src/app/api/market/route.ts");
if (!marketApi.includes("PARTICIPANT_MARKET_MUTATION_RPC.createListing")) {
  failures.push("site market API must use the shared create listing RPC contract");
}
for (const contractField of [
  "updateListing",
  "closeListing",
  "createInquiry",
  "respondInquiry",
  "closeInquiry",
]) {
  if (!marketApi.includes("PARTICIPANT_MARKET_MUTATION_RPC." + contractField)) {
    failures.push("site market API must use shared market mutation contract " + contractField);
  }
}
if (/db\.rpc\(\"participant_(create|update|close)_market|db\.rpc\(\"participant_(respond|create|close)_market_inquiry/.test(marketApi)) {
  failures.push("site market API must not hardcode participant market mutation RPC names");
}

const eventRegisterApi = read("site/src/app/api/events/register/route.ts");
for (const contractField of ["register", "unregister"]) {
  if (!eventRegisterApi.includes("PARTICIPANT_EVENT_MUTATION_RPC." + contractField)) {
    failures.push("site event registration API must use shared event mutation contract " + contractField);
  }
}
if (
  eventRegisterApi.includes('db.rpc("participant_register_event"') ||
  eventRegisterApi.includes('db.rpc("participant_unregister_event"')
) {
  failures.push("site event registration API must not hardcode participant event mutation RPC names");
}

const pollVoteApi = read("site/src/app/api/polls/vote/route.ts");
if (!pollVoteApi.includes("PARTICIPANT_POLL_MUTATION_RPC.voteMany")) {
  failures.push("site poll vote API must use shared participant_vote_poll_many contract");
}
if (pollVoteApi.includes('db.rpc("participant_vote_poll_many"')) {
  failures.push("site poll vote API must not hardcode participant_vote_poll_many");
}

const notificationReadApi = read("site/src/app/api/notifications/read/route.ts");
if (!notificationReadApi.includes("PARTICIPANT_NOTIFICATION_MUTATION_RPC.markRead")) {
  failures.push("site notification read API must use shared participant_mark_notification_read contract");
}
if (notificationReadApi.includes('db.rpc("participant_mark_notification_read"')) {
  failures.push("site notification read API must not hardcode participant_mark_notification_read");
}

const reportCreateApi = read("site/src/app/api/reports/route.ts");
if (!reportCreateApi.includes("PARTICIPANT_REPORT_MUTATION_RPC.create")) {
  failures.push("site report create API must use shared participant_create_report contract");
}
if (reportCreateApi.includes('db.rpc("participant_create_report"')) {
  failures.push("site report create API must not hardcode participant_create_report");
}

const battlesPage = read("site/src/app/app/battles/page.tsx");
if (!battlesPage.includes("PARTICIPANT_BATTLE_RPC.list")) {
  failures.push("site battles page must use participant_get_battles");
}
if (!battlesPage.includes("PARTICIPANT_CURRENT_USER_RPC.get")) {
  failures.push("site battles page must use participant_get_current_user contract");
}
if (battlesPage.includes('from("player_battles")')) {
  failures.push("site battles page must not directly read private player_battles table");
}

const appealsPage = read("site/src/app/app/appeals/page.tsx");
if (!appealsPage.includes("PARTICIPANT_APPEAL_RPC.list")) {
  failures.push("site appeals page must use participant_get_appeals");
}
if (appealsPage.includes('from("appeals")')) {
  failures.push("site appeals page must not directly read private appeals tables");
}

const reportsPage = read("site/src/app/app/reports/page.tsx");
if (!reportsPage.includes("PARTICIPANT_REPORT_RPC.list")) {
  failures.push("site reports page must use participant_get_reports");
}
if (reportsPage.includes('from("reports")')) {
  failures.push("site reports page must not directly read private reports table");
}

const reportDetailPage = read("site/src/app/app/reports/[id]/page.tsx");
if (!reportDetailPage.includes("PARTICIPANT_REPORT_RPC.detail")) {
  failures.push("site report detail page must use participant_get_report");
}
if (reportDetailPage.includes('from("reports")') || reportDetailPage.includes('from("report_history")')) {
  failures.push("site report detail page must not directly read private report tables");
}

const applicationPage = read("site/src/app/app/application/page.tsx");
if (!applicationPage.includes("PARTICIPANT_READ_RPC.application")) {
  failures.push("site application page must use the shared participant_get_application contract");
}
if (applicationPage.includes('db.rpc("participant_get_application"')) {
  failures.push("site application page must not hardcode participant_get_application");
}
if (applicationPage.includes('from("applications")')) {
  failures.push("site application page must not directly read private applications table");
}

const settingsPage = read("site/src/app/app/settings/page.tsx");
if (!settingsPage.includes("PARTICIPANT_NOTIFICATION_RPC.preferences")) {
  failures.push("site settings page must use participant_get_notification_preferences");
}
if (settingsPage.includes('from("notification_preferences")')) {
  failures.push("site settings page must not directly read private notification_preferences table");
}

const notificationsPage = read("site/src/app/app/notifications/page.tsx");
if (!notificationsPage.includes("db.rpc(PARTICIPANT_RPC.notifications")) {
  failures.push("site notifications page must use participant_get_notifications");
}
if (notificationsPage.includes('from("notifications")')) {
  failures.push("site notifications page must not directly read private notifications table");
}

const livePage = read("site/src/app/live/page.tsx");
if (!livePage.includes("STAFF_LIVE_RPC.events")) {
  failures.push("site live page must use staff_get_live_events");
}
if (livePage.includes('from("minecraft_events")') || livePage.includes('from("admins")')) {
  failures.push("site live page must not directly read staff-only tables");
}

const participantLayout = read("site/src/app/app/layout.tsx");
if (!participantLayout.includes("PARTICIPANT_NOTIFICATION_COUNT_RPC.unread")) {
  failures.push("participant app layout must use participant_get_unread_notification_count");
}
if (participantLayout.includes('from("notifications")')) {
  failures.push("participant app layout must not directly read private notifications table");
}

const publicLanding = read("site/src/app/page.tsx");
if (!publicLanding.includes("https://t.me/")) {
  failures.push("public landing must expose the Telegram CTA");
}
if (/server\.(version|players|maxPlayers)/.test(publicLanding)) {
  failures.push("public landing must not expose server version or player-count internals");
}
if (!publicLanding.includes('href="/apply"')) {
  failures.push("public landing must keep the direct application CTA");
}

const siteAuth = read("site/src/lib/auth.ts");
if (!siteAuth.includes("PARTICIPANT_CURRENT_USER_RPC.get")) {
  failures.push("site auth helper must resolve current user through participant_get_current_user");
}
if (/\.from\(\s*["']users["']/.test(siteAuth)) {
  failures.push("site auth helper must not directly read public.users");
}

const siteAdminClient = read("site/src/lib/supabase/admin.ts");
if (!siteAdminClient.includes('import "server-only";')) {
  failures.push("site/src/lib/supabase/admin.ts must be explicitly server-only");
}

for (const file of filesUnder("site/src")) {
  if (!/\.(ts|tsx)$/.test(file)) continue;
  const source = read(file);
  if (!source.includes("createSupabaseAdminClient")) continue;

  const allowed =
    file === "site/src/lib/supabase/admin.ts" ||
    file === "site/src/lib/rate-limit.ts" ||
    file.startsWith("site/src/app/api/auth/");

  if (!allowed) {
    failures.push(
      `${file}: participant code must not import the service-role client outside server-only infrastructure or auth routes`,
    );
  }
}

const participantAppFiles = filesUnder("site/src/app/app")
  .filter((file) => /\.(ts|tsx)$/.test(file));
for (const file of participantAppFiles) {
  const source = read(file);
  if (/\.from\(\s*["'][^"']+["']/.test(source)) {
    failures.push(`${file}: participant app pages must use gateway/RPC reads instead of direct table access`);
  }
  if (/(?:db|supabase)\.rpc\(\s*["'][^"']+["']/.test(source)) {
    failures.push(`${file}: participant app pages must use shared RPC contracts instead of string literals`);
  }
}

const participantDataSource = read("site/src/lib/data.ts");
if (/(?:db|supabase)\.rpc\(\s*["'][^"']+["']/.test(participantDataSource)) {
  failures.push("site/src/lib/data.ts: RPCs must use shared contracts instead of string literals");
}
if (participantDataSource.includes('db.rpc("participant_get_')) {
  failures.push("site/src/lib/data.ts: participant read RPCs must not be hardcoded");
}

const siteData = read("site/src/lib/data.ts");
const dashboardStart = siteData.indexOf("export async function getDashboardData");
const dashboardEnd = siteData.indexOf("\nexport async function getParticipantClans", dashboardStart);
if (dashboardStart < 0 || dashboardEnd < 0) {
  failures.push("site/src/lib/data.ts: getDashboardData contract is missing");
} else {
  const dashboardSource = siteData.slice(dashboardStart, dashboardEnd);
  if (!dashboardSource.includes("db.rpc(PARTICIPANT_RPC.dashboard)")) {
    failures.push("site/src/lib/data.ts: getDashboardData must use participant_get_dashboard");
  }
  if (/db\.from\(/.test(dashboardSource)) {
    failures.push("site/src/lib/data.ts: getDashboardData must not directly read private tables");
  }
}
const panelProxyCode = read("panel/proxy.ts");
if (!panelProxyCode.includes("supabase.auth.getClaims()")) {
  failures.push("panel/proxy.ts: auth proxy must use getClaims for session refresh/verification");
}
if (panelProxyCode.includes("supabase.auth.getUser()")) {
  failures.push("panel/proxy.ts: auth proxy must not use getUser on every request");
}

const panelTelegramVerifyCode = read("panel/src/app/api/auth/telegram/verify/route.ts");
const siteTelegramVerifyCode = read("site/src/app/api/auth/telegram/verify/route.ts");
for (const [file, source] of [
  ["panel/src/app/api/auth/telegram/verify/route.ts", panelTelegramVerifyCode],
  ["site/src/app/api/auth/telegram/verify/route.ts", siteTelegramVerifyCode],
]) {
  if (!source.includes("const { data: otpData, error: verifyError }")) {
    failures.push(file + ": Telegram verification must use verifyOtp result directly");
  }
  if (source.includes("await supabase.auth.getUser()")) {
    failures.push(file + ": Telegram verification must not refresh the auth session with a second getUser call");
  }
}
const botMain = read("bot/main.py");
const socialRouterIndex = botMain.indexOf("social.router");
const marketRouterIndex = botMain.indexOf("market.router");
const menuRouterIndex = botMain.indexOf("menu.router");
if (socialRouterIndex < 0 || marketRouterIndex < 0 || menuRouterIndex < 0 ||
    socialRouterIndex > menuRouterIndex || marketRouterIndex > menuRouterIndex) {
  failures.push("bot/main.py: private social and market routers must precede menu catch-all callbacks");
}
if (botMain.includes("dp.include_router(social.router)") || botMain.includes("dp.include_router(market.router)")) {
  failures.push("bot/main.py: social/market routers must not be registered after the private catch-all router");
}


const panelApiFiles = filesUnder("panel/src/app/api");
const panelMutationExceptions = [
  "panel/src/app/api/auth/",
  "panel/src/app/api/export/",
];

for (const file of panelApiFiles) {
  const source = read(file);
  const exempt = panelMutationExceptions.some((prefix) => file.startsWith(prefix));

  if (!exempt && source.includes("createSupabaseAdminClient")) {
    failures.push(`${file}: business API route must not use the service-role client`);
  }

  if (!exempt && /\.(insert|update|delete)\(/.test(source)) {
    failures.push(`${file}: business API route must mutate state through an RPC gateway`);
  }
}

const requiredContracts = [
  "supabase/migrations/20260927200001_prisma_fix_authenticated_permission_helper_acl.sql",
  "supabase/migrations/20260927205500_prisma_bot_lift_ban_contract.sql",
  "supabase/migrations/20260927214500_prisma_appeal_notification_domain_pipeline.sql",
  "supabase/migrations/20260927223000_prisma_canonical_appeal_domain.sql",
  "supabase/migrations/20260927271000_prisma_application_decision_final_reconcile.sql",
  "supabase/migrations/20260928103000_prisma_market_update_contract_reconcile.sql",
  "supabase/migrations/20260928110000_prisma_bot_runtime_acl_reconcile.sql",
  "supabase/migrations/20260928113000_prisma_public_rpc_security_regression_guard.sql",
  "supabase/migrations/20260928120000_prisma_player_profile_role_join_fix.sql",
  "supabase/migrations/20260928132000_prisma_minecraft_rpc_acl_reconcile.sql",
  "supabase/migrations/20260928140000_prisma_moderation_plugin_claim_lease.sql",
  "supabase/migrations/20261024120000_prisma_mc_staff_moderation_commands.sql",
  "supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql",
  "supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql",
  "supabase/migrations/20261024143000_prisma_minecraft_telegram_identity_binding.sql",
  "supabase/migrations/20261024150000_prisma_minecraft_gameplay_toggles.sql",
  "supabase/migrations/20260928150000_prisma_public_function_default_acl_lockdown.sql",
  "supabase/migrations/20260928153000_prisma_public_function_execute_guard.sql",
  "supabase/migrations/20260928160000_prisma_trigger_function_execute_lockdown.sql",
  "supabase/migrations/20260928170000_prisma_participant_dashboard_gateway.sql",
  "supabase/migrations/20260928172000_prisma_participant_notifications_read_gateway.sql",
  "supabase/migrations/20260928173000_prisma_participant_application_read_gateway.sql",
  "supabase/migrations/20260928174000_prisma_participant_reports_read_gateways.sql",
  "supabase/migrations/20260928175000_prisma_participant_battle_read_gateway.sql",
  "supabase/migrations/20260928176000_prisma_participant_notification_preferences_gateway.sql",
  "supabase/migrations/20260928177000_prisma_participant_market_listing_read_gateway.sql",
  "supabase/migrations/20260928178000_prisma_staff_live_events_gateway.sql",
  "supabase/migrations/20260928179000_prisma_participant_current_user_gateway.sql",
  "supabase/migrations/20260928180000_prisma_participant_unread_notification_count_gateway.sql",
  "supabase/migrations/20260928181000_prisma_participant_current_user_privacy.sql",
  "supabase/migrations/20260928182000_prisma_participant_current_user_privacy_telegram.sql",
  "supabase/migrations/20260928183000_prisma_auth_rate_limit_search_path_hardening.sql",
  "supabase/migrations/20260928184000_prisma_public_schema_create_acl_hardening.sql",
  "supabase/migrations/20260928163556_prisma_bot_login_code_search_path_hardening.sql",
];

for (const file of requiredContracts) {
  if (!fs.existsSync(path.join(root, file))) {
    failures.push(`missing release-critical contract migration: ${file}`);
  }
}

const minecraftCatalog = read("packages/contracts/minecraft-commands.json");
const gameplayToggleMigration = read("supabase/migrations/20261024150000_prisma_minecraft_gameplay_toggles.sql");
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

if (!gameplayToggleMigration.includes("('minecraft-maze-runner', false)")) {
  failures.push("Maze Runner must remain disabled by default until the map is configured");
}
const mazeRunnerController = read("minecraft-plugin/src/main/java/team/prisma/plugin/maze/MazeRunnerController.java");
for (const marker of [
  'modules.isEnabled("minecraft-maze-runner")',
  'settings.getBoolean("run-enabled", false)',
  'EntityType.SPIDER',
  "preventGrieverDamageInGlade",
  "dropCompassForManagedGriever",
  'new File(plugin.getDataFolder(), "maze-runner.yml")',
]) {
  if (!mazeRunnerController.includes(marker)) {
    failures.push("Maze Runner runtime is missing required safety/configuration contract: " + marker);
  }
}
if (!minecraftCatalog.includes('"command": "/maze"')) {
  failures.push("Minecraft command catalog must contain the Maze Runner staff command");
}

const publicContentGatewayMigration = read("supabase/migrations/20260929062000_prisma_public_content_read_gateways.sql");
for (const fn of [
  "get_public_news",
  "get_public_clans",
  "get_public_seasons",
  "get_public_events",
  "get_public_wiki",
  "get_public_media",
  "get_public_awards",
]) {
  if (!new RegExp(`create or replace function public\\.${fn}\\b`).test(publicContentGatewayMigration)) {
    failures.push("public content gateway missing function " + fn);
  }
  if (!new RegExp(`grant execute on function public\\.${fn}`).test(publicContentGatewayMigration)) {
    failures.push("public content gateway missing explicit EXECUTE grant for " + fn);
  }
  if (!new RegExp(`security definer[\\s\\S]*?set search_path=''`, "i").test(publicContentGatewayMigration)) {
    failures.push("public content gateway migration must pin SECURITY DEFINER search_path");
  }
}

const identityBindingMigration = migrationFiles.find((file) => file.endsWith("_prisma_minecraft_identity_binding.sql"));
if (!identityBindingMigration) {
  failures.push("Minecraft identity binding migration is missing");
}
const pluginBuild = read("minecraft-plugin/build.gradle.kts");
const pluginYaml = read("minecraft-plugin/src/main/resources/plugin.yml");
const botMinecraftCommands = read("bot/handlers/minecraft_commands.py");

if (minecraftCatalog !== minecraftCatalog.trim() + "\n") {
  failures.push("Minecraft command catalog should have a stable trailing newline");
}
const releaseVersion = read("VERSION").trim();
if (!minecraftCatalog.includes(`"release": "${releaseVersion}"`)) {
  failures.push(`Minecraft command catalog must target release ${releaseVersion}`);
}
if (!minecraftCatalog.includes('"platform": "JAVA"')) {
  failures.push("Minecraft command catalog must define Java-only authentication");
}
if (!minecraftCatalog.includes('"platform": "BEDROCK"')) {
  failures.push("Minecraft command catalog must define Bedrock authentication");
}
if (minecraftCatalog.includes('"command": "/back"')) {
  failures.push("Legacy /back command must not be present in the Minecraft command catalog");
}
if (!pluginBuild.includes('rootProject.file("../VERSION").readText().trim()')) {
  failures.push("Minecraft plugin version must derive from root VERSION");
}
if (!pluginBuild.includes('packages/contracts/minecraft-commands.json')) {
  failures.push("Minecraft plugin must package the canonical command catalog");
}
if (!pluginYaml.includes("prismacommands")) {
  failures.push("Minecraft plugin command catalog command is missing");
}
if (!roleDisplay.includes("setPlayerListName") || !roleDisplay.includes("setDisplayName")) {
  failures.push("Minecraft role display must update chat and tab presentation");
}

const playerHomeCommand = read("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerHomeCommand.java");
const playerHomesStore = read("minecraft-plugin/src/main/java/team/prisma/plugin/homes/PlayerHomesStore.java");
const playerHomeEntrypoint = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
for (const marker of [
  "MAX_HOMES = 2",
  "ATOMIC_MOVE",
  "storageHealthy = false",
  "Files.deleteIfExists(temporaryFile)",
]) {
  if (!playerHomesStore.includes(marker)) {
    failures.push("Personal home storage must preserve data integrity: " + marker);
  }
}
for (const marker of [
  'case "sethome" -> setHome(player, args)',
  'case "home" -> goHome(player, args)',
  'case "homes" -> listHomes(player, args)',
  'case "delhome" -> deleteHome(player, args)',
  "player.teleportAsync(target)",
]) {
  if (!playerHomeCommand.includes(marker)) {
    failures.push("Personal home command implementation is incomplete: " + marker);
  }
}
for (const marker of [
  "new PlayerHomesStore(this)",
  'new String[]{"sethome", "home", "homes", "delhome"}',
  'bindGatedCommand(home, homeCommand, homeCommand, modules, "minecraft-homes")',
]) {
  if (!playerHomeEntrypoint.includes(marker)) {
    failures.push("Personal home commands must be wired behind the Minecraft module gate: " + marker);
  }
}
if (!pluginYaml.includes("prisma.command.homes") ||
    !roleDisplay.includes('"prisma.command.homes",') ||
    !roleDisplay.includes('"prisma.command.spawns",') ||
    !roleDisplay.includes('"prisma.command.spawnmanage",')) {
  failures.push("Personal home/spawn commands must use the role-derived permission contract");
}

const prismaHelpCommand = read("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PrismaHelpCommand.java");
const helpEntrypoint = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
for (const marker of [
  'section.equals("основное")',
  'case "перемещение", "телепортация"',
  'case "кланы"',
  'case "авторизация"',
  'case "персонал"',
]) {
  if (!prismaHelpCommand.includes(marker)) {
    failures.push("Categorized Russian help is incomplete: " + marker);
  }
}
if (!prismaHelpCommand.includes("/prismacommands 1")) {
  failures.push("Categorized Russian help must link to the paginated command catalog");
}
if (!pluginYaml.includes("  help:") || !pluginYaml.includes("aliases: [prismahelp]") ||
    !helpEntrypoint.includes('getCommand("help")') ||
    !helpEntrypoint.includes('new PrismaHelpCommand(cache, modules)')) {
  failures.push("PRISMA help must be registered as /help and wired to its command handler");
}

const journeyCommand = read("minecraft-plugin/src/main/java/team/prisma/plugin/commands/PlayerJourneyCommand.java");
const journeyStore = read("minecraft-plugin/src/main/java/team/prisma/plugin/journey/PlayerJourneyStore.java");
const journeyListener = read("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/PlayerJourneyListener.java");
const journeyEntrypoint = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
for (const marker of [
  "MAX_CHECKPOINTS = 5",
  "CompletableFuture<MutationResult> recordDeath(",
  "CompletableFuture<MutationResult> setCheckpoint(",
  "CompletableFuture<MutationResult> deleteCheckpoint(",
  "writer.execute",
  "persist(snapshot)",
  "StandardCopyOption.ATOMIC_MOVE",
  "awaitTermination(5, TimeUnit.SECONDS)",
]) {
  if (!journeyStore.includes(marker)) {
    failures.push("Journey storage must be persistent, serialized and fail-safe: " + marker);
  }
}
for (const marker of [
  'case "coords" -> coords(player, args)',
  'case "lastdeath" -> lastDeath(player, args)',
  'case "checkpoint" -> checkpoint(player, args)',
  'Bukkit.broadcastMessage("§7[Координаты]',
  'player.teleportAsync(target)',
  'if (now - last < 15_000L)',
]) {
  if (!journeyCommand.includes(marker)) {
    failures.push("Journey command implementation is incomplete: " + marker);
  }
}
if (!journeyStore.includes("LIMIT_REACHED") || !journeyCommand.includes("case LIMIT_REACHED ->")) {
  failures.push("Journey command must handle the checkpoint limit result returned by its store");
}
for (const marker of [
  "PlayerDeathEvent",
  'modules.isEnabled("minecraft-journey")',
  "Point.capture(player.getLocation().clone()",
  "journey.recordDeath(player.getUniqueId(), point)",
]) {
  if (!journeyListener.includes(marker)) {
    failures.push("Last-death listener must capture and persist the player location safely: " + marker);
  }
}
for (const marker of [
  "new PlayerJourneyStore(this)",
  "new PlayerJourneyListener(this, journeyStore, modules)",
  'new String[]{"coords", "lastdeath", "checkpoint"}',
  'bindGatedCommand(journey, journeyCommand, journeyCommand, modules, "minecraft-journey")',
  "if (journeyStore != null) journeyStore.close();",
]) {
  if (!journeyEntrypoint.includes(marker)) {
    failures.push("Journey commands/listener must be wired and storage drained on shutdown: " + marker);
  }
}
if (!pluginYaml.includes("prisma.command.journey") ||
    !roleDisplay.includes('"prisma.command.journey"')) {
  failures.push("Journey commands must be restricted to identity-synced PRISMA participants");
}
for (const command of ["/coords", "/lastdeath", "/checkpoint"]) {
  if (!minecraftCatalog.includes('"command": "' + command + '"')) {
    failures.push("Minecraft command catalogue is missing " + command);
  }
}

const serverHudTask = read("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerHudTask.java");
const hudEntrypoint = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
for (const marker of [
  "player.sendActionBar(",
  "player.sendPlayerListHeaderAndFooter(",
  "player.getPing()",
  "Bukkit.getServer().getTPS()",
  "disabledPlayers.removeIf",
  "public void onQuit(PlayerQuitEvent event)",
  "disabledPlayers.remove(event.getPlayer().getUniqueId())",
  "updateTab(player, Bukkit.getOnlinePlayers().size()",
  'case "on", "вкл" ->',
  'case "off", "выкл" ->',
  'case "status", "статус" ->',
  'Component.text("/help", NamedTextColor.YELLOW)',
]) {
  if (!serverHudTask.includes(marker)) {
    failures.push("HUD/TAB implementation is incomplete: " + marker);
  }
}
for (const marker of [
  "new ServerHudTask(this, cache, modules)",
  'getCommand("hud")',
  'bindGatedCommand(hud, serverHud, null, modules, "minecraft-hud")',
  "runTaskTimer(this, serverHud, 20L, 40L)",
  "registerEvents(serverHud, this)",
]) {
  if (!hudEntrypoint.includes(marker)) {
    failures.push("HUD must be registered and scheduled behind the Minecraft module gate: " + marker);
  }
}
if (!pluginYaml.includes("prisma.command.hud") ||
    !pluginYaml.includes("  hud:") ||
    !roleDisplay.includes('"prisma.command.hud"') ||
    !minecraftCatalog.includes('"command": "/hud"')) {
  failures.push("HUD command must have an approved-player permission and a shared catalogue entry");
}


const graveStore = read("minecraft-plugin/src/main/java/team/prisma/plugin/graves/GraveStore.java");
const graveListener = read("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/GraveListener.java");
const graveCommand = read("minecraft-plugin/src/main/java/team/prisma/plugin/commands/GraveCommand.java");
const graveEntrypoint = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
for (const marker of [
  "TTL_MILLIS = TimeUnit.MINUTES.toMillis(10)",
  "StandardCopyOption.ATOMIC_MOVE",
  "State.CLAIMING",
  "completeClaim(",
  "rollbackClaim(",
  "storageHealthy = false",
  "MAX_ITEMS_PER_GRAVE = 256",
]) {
  if (!graveStore.includes(marker)) failures.push("Grave storage must be durable and fail-closed: " + marker);
}
for (const marker of [
  "event.getDrops().clear()",
  "store.create(",
  "marker.addScoreboardTag(",
  "PersistentDataType.STRING",
  "player.saveData()",
  "store.completeClaim(",
  "store.claimingFor(player.getUniqueId())",
  "onChunkLoad(ChunkLoadEvent event)",
]) {
  if (!graveListener.includes(marker)) failures.push("Grave recovery/marker handler is incomplete: " + marker);
}
for (const marker of [
  'case "claim", "restore" -> claim(player, args)',
  "MAX_DISTANCE_SQUARED = 25.0d",
  'player.hasPermission("prisma.command.grave.admin")',
  "listener.deliverClaim(player, operation.grave(), true)",
]) {
  if (!graveCommand.includes(marker)) failures.push("Grave command is incomplete: " + marker);
}
for (const marker of [
  "new GraveStore(this)",
  "new GraveListener(this, graveStore, modules)",
  'getCommand("grave")',
  'bindGatedCommand(grave, graveCommand, graveCommand, modules, "minecraft-graves")',
  "graveListener.initialize()",
]) {
  if (!graveEntrypoint.includes(marker)) failures.push("Grave system must be wired behind the Minecraft module gate: " + marker);
}
if (!pluginYaml.includes("prisma.command.grave") ||
    !pluginYaml.includes("prisma.command.grave.admin") ||
    !roleDisplay.includes('"prisma.command.grave"') ||
    !roleDisplay.includes('"prisma.command.grave.admin"') ||
    !roleDisplay.includes('case "prisma.command.grave.admin"')) {
  failures.push("Graves must require synced participant access and a separate admin permission");
}
if (!minecraftCatalog.includes('"command": "/grave"') ||
    !minecraftCatalog.includes('"/graves"')) {
  failures.push("Minecraft command catalogue is missing /grave or its /graves alias");
}


const moderationCommand = read("minecraft-plugin/src/main/java/team/prisma/plugin/commands/ModerationCommand.java");
const moderationEntrypoint = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
for (const marker of [
  "RpcNames.MC_STAFF_APPLY_MODERATION",
  "RpcNames.MC_STAFF_LIFT_MODERATION",
  "RpcNames.MC_STAFF_MODERATION_HISTORY",
  "supabase.postRpcAsync(rpc, body)",
  "PlayerCommandPreprocessEvent",
  "parseRequiredDuration(",
  "friendlyError(detail)",
]) {
  if (!moderationCommand.includes(marker)) failures.push("Minecraft moderation command implementation is incomplete: " + marker);
}
for (const marker of [
  "new ModerationCommand(this, supabase, cache)",
  "registerEvents(moderationCommand, this)",
  'new String[]{"warn", "mute", "unmute", "kick", "ban", "tempban", "unban", "history"}',
  'bindGatedCommand(moderation, moderationCommand, moderationCommand, modules, "minecraft-moderation")',
]) {
  if (!moderationEntrypoint.includes(marker)) failures.push("Minecraft moderation commands must be wired behind both runtime module gates: " + marker);
}
for (const rpc of [
  'MC_STAFF_APPLY_MODERATION = "mc_staff_apply_moderation"',
  'MC_STAFF_LIFT_MODERATION = "mc_staff_lift_moderation"',
  'MC_STAFF_MODERATION_HISTORY = "mc_staff_moderation_history"',
]) {
  if (!rpcRegistry.includes(rpc)) failures.push("Minecraft moderation RPC registry missing " + rpc);
}
for (const command of ["/warn", "/mute", "/unmute", "/kick", "/ban", "/tempban", "/unban", "/history"]) {
  if (!minecraftCatalog.includes('"command": "' + command + '"')) failures.push("Minecraft command catalogue is missing " + command);
}
if (!pluginYaml.includes("prisma.command.moderation") ||
    !roleDisplay.includes('"prisma.command.moderation"')) {
  failures.push("Minecraft moderation commands must be restricted to synchronized PRISMA staff");
}


const minecraftBridgeTask = read("minecraft-plugin/src/main/java/team/prisma/plugin/tasks/MinecraftChatBridgeTask.java");
const minecraftChatListener = read("minecraft-plugin/src/main/java/team/prisma/plugin/listeners/ChatListener.java");
const telegramBridgeService = read("bot/services/minecraft_bridge.py");
const telegramBridgeEntrypoint = read("bot/main.py");
const telegramBridgeRpc = read("bot/db/rpc.py");
const bridgeSql = read("supabase/migrations/20261024133000_prisma_minecraft_telegram_chat_bridge.sql");
const bridgeHardeningSql = read("supabase/migrations/20261024140000_prisma_minecraft_chat_bridge_hardening.sql");
const bridgeIdentitySql = read("supabase/migrations/20261024143000_prisma_minecraft_telegram_identity_binding.sql");
const bridgeContractSource = read("packages/contracts/src/index.ts");
const bridgeModuleRegistry = read("modules/registry.json");

for (const marker of [
  "RpcNames.MC_BRIDGE_CLAIM_FOR_MINECRAFT",
  "RpcNames.MC_BRIDGE_FINISH_MESSAGE",
  "Bukkit.broadcast(line)",
  "RECENT_DELIVERY_TTL_MILLIS",
  'stringField(row, "lease_token")',
  'body.addProperty("p_lease_token", leaseToken)',
  'modules.isEnabled("minecraft-chat-bridge")',
]) {
  if (!minecraftBridgeTask.includes(marker)) failures.push("Minecraft Telegram bridge consumer is incomplete: " + marker);
}
for (const marker of [
  "RpcNames.MC_BRIDGE_ENQUEUE_FROM_MINECRAFT",
  'bridge.addProperty("p_minecraft_uuid"',
  'bridge.addProperty("p_user_id"',
  "EventPriority.MONITOR",
  "Bukkit.getScheduler().runTask(plugin, () -> {",
  "player.getWorld().getName()",
]) {
  if (!minecraftChatListener.includes(marker)) failures.push("Minecraft chat bridge source is incomplete: " + marker);
}
for (const marker of [
  "class MinecraftChatBridge(BaseMiddleware)",
  "bot_bridge_enqueue_from_telegram",
  "bot_bridge_claim_for_telegram",
  "bot_bridge_finish_message",
  'str(row.get("lease_token") or "")',
  "await self._refresh_community_chat_id()",
  "_looks_like_group_command",
  "sender.is_bot",
  "html.escape(body)",
  'is_module_effectively_enabled("chat")',
  'is_module_effectively_enabled("minecraft")',
]) {
  if (!telegramBridgeService.includes(marker)) failures.push("Telegram Minecraft bridge worker/middleware is incomplete: " + marker);
}
for (const marker of [
  "from services.minecraft_bridge import MinecraftChatBridge",
  "dp.message.outer_middleware(minecraft_chat_bridge)",
  "minecraft_chat_bridge.run(bot, worker_stop)",
  "minecraft_chat_bridge_task.cancel()",
]) {
  if (!telegramBridgeEntrypoint.includes(marker)) failures.push("Telegram Minecraft bridge must be registered, supervised and shut down: " + marker);
}
for (const marker of [
  'call_rpc_async("bot_bridge_enqueue_from_telegram"',
  "retries=2, retry_delay_seconds=0.5",
  'call_rpc_async("mc_bridge_claim_for_telegram"',
  'call_rpc_async("mc_bridge_finish_message"',
  '"p_lease_token": lease_token',
]) {
  if (!telegramBridgeRpc.includes(marker)) failures.push("Bot RPC gateway is missing a Minecraft bridge function: " + marker);
}
for (const marker of [
  "create table if not exists public.minecraft_chat_bridge_queue",
  "enable row level security",
  "revoke all on table public.minecraft_chat_bridge_queue from public,anon,authenticated,service_role",
  "public.mc_bridge_enqueue_from_minecraft(",
  "public.bot_bridge_enqueue_from_telegram(",
  "public.mc_bridge_claim_for_telegram(",
  "public.mc_bridge_claim_for_minecraft(",
  "public.mc_bridge_finish_message(",
  "public.bot_get_community_chat_id()",
  "BRIDGE_RATE_LIMITED",
  "MESSAGE_EXPIRED",
  "pg_advisory_xact_lock",
  "return json_build_object('success',true,'id',queue_id,'duplicate',true);",
  "pg_advisory_xact_lock",
]) {
  if (!bridgeSql.includes(marker)) failures.push("Minecraft Telegram bridge database contract/security is incomplete: " + marker);
}
for (const marker of [
  "add column if not exists lease_token uuid",
  "u.minecraft_uuid=p_minecraft_uuid",
  "pg_advisory_xact_lock",
  "BRIDGE_LEASE_NOT_HELD",
  "revoke all on function public.mc_bridge_finish_message(uuid,text,text,integer)",
  "from public,anon,authenticated,service_role",
  "mc_bridge_finish_message(uuid,uuid,text,text,integer) to service_role",
]) {
  if (!bridgeHardeningSql.includes(marker)) failures.push("Minecraft bridge lease-token hardening is incomplete: " + marker);
}
const telegramIdentityFunctionStart = bridgeIdentitySql.indexOf("create or replace function public.bot_bridge_enqueue_from_telegram(");
const telegramDuplicateGuard = bridgeIdentitySql.indexOf("if queue_id is not null then", telegramIdentityFunctionStart);
const telegramRateLimitGuard = bridgeIdentitySql.indexOf("if recent_count>=6 then", telegramIdentityFunctionStart);
if (telegramIdentityFunctionStart < 0 || telegramDuplicateGuard < telegramIdentityFunctionStart ||
    telegramRateLimitGuard <= telegramDuplicateGuard) {
  failures.push("Minecraft Telegram bridge must deduplicate retried Telegram updates before applying rate limits");
}
for (const marker of [
  "u.telegram_id is not null",
  "u.minecraft_uuid=p_minecraft_uuid",
  "u.minecraft_uuid is not null",
  "BRIDGE_TELEGRAM_IDENTITY_UNBOUND",
  "FOR SHARE",
  "pg_advisory_xact_lock",
  "on conflict (telegram_chat_id,telegram_message_id) do nothing",
  "revoke all on function public.bot_bridge_enqueue_from_telegram(bigint,bigint,bigint,text,text)",
  "grant execute on function public.bot_bridge_enqueue_from_telegram(bigint,bigint,bigint,text,text)",
  "to service_role;",
]) {
  if (!bridgeIdentitySql.includes(marker)) failures.push("Minecraft Telegram bridge identity binding is incomplete: " + marker);
}
if (!bridgeContractSource.includes("export const MINECRAFT_CHAT_BRIDGE_RPC") ||
    !bridgeModuleRegistry.includes('"MINECRAFT_CHAT_BRIDGE_RPC"')) {
  failures.push("Minecraft Telegram bridge RPCs must be in the shared contract and chat module registry");
}
if (!JSON.parse(bridgeModuleRegistry).modules.find(module => module.id === "chat")?.surfaces?.includes("plugin")) {
  failures.push("chat module registry must include the Paper plugin surface");
}

const spawnCommand = read("minecraft-plugin/src/main/java/team/prisma/plugin/commands/SpawnCommand.java");
const spawnStore = read("minecraft-plugin/src/main/java/team/prisma/plugin/spawn/SpawnPointsStore.java");
const spawnEntrypoint = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
for (const marker of [
  "MAIN_SPAWN_ID = 0",
  "MAX_CUSTOM_SPAWN_ID = 999",
  "ATOMIC_MOVE",
  "storageHealthy = false",
  "CompletableFuture<Boolean> set(",
  "CompletableFuture<Boolean> delete(",
  "writer.execute",
  "persistedSnapshot",
  "awaitTermination",
]) {
  if (!spawnStore.includes(marker)) {
    failures.push("Spawn storage must preserve data integrity and avoid synchronous disk writes: " + marker);
  }
}
for (const marker of [
  'case "spawn" -> teleport(player, args)',
  'case "spawns" -> list(player, args)',
  'case "setspawn" -> set(player, args)',
  'case "delspawn" -> delete(player, args)',
  'spawns.set(id, name, location).whenComplete',
  'spawns.delete(id).whenComplete',
  'private void main(Runnable task)',
  'Bukkit.getWorlds().get(0).getSpawnLocation()',
  "player.teleportAsync(target)",
  'player.hasPermission("prisma.command.spawnmanage")',
  "cache.userIdOf(player.getUniqueId())",
]) {
  if (!spawnCommand.includes(marker)) {
    failures.push("Spawn command implementation is incomplete: " + marker);
  }
}
for (const marker of [
  "new SpawnPointsStore(this)",
  "new SpawnCommand(this, spawnPoints, cache)",
  'new String[]{"spawn", "spawns", "setspawn", "delspawn"}',
  'bindGatedCommand(spawn, spawnCommand, spawnCommand, modules, "minecraft-spawns")',
  "private SpawnPointsStore spawnPoints",
  "if (spawnPoints != null) spawnPoints.close();",
]) {
  if (!spawnEntrypoint.includes(marker)) {
    failures.push("Spawn commands must be wired behind the Minecraft module gate: " + marker);
  }
}
if (!pluginYaml.includes("spawnmanage") || !pluginYaml.includes("  spawn:") ||
    !pluginYaml.includes("  spawns:") || !pluginYaml.includes("  setspawn:") ||
    !pluginYaml.includes("  delspawn:") ||
    !roleDisplay.includes('case "prisma.command.spawnmanage"')) {
  failures.push("Spawn commands must register player and senior-staff access nodes");
}
for (const command of ["/spawn", "/spawns", "/setspawn", "/delspawn"]) {
  if (!minecraftCatalog.includes('"command": "' + command + '"')) {
    failures.push("Minecraft command catalog is missing " + command);
  }
}

const tpAllCommand = read("minecraft-plugin/src/main/java/team/prisma/plugin/commands/TpAllCommand.java");
for (const marker of [
  "CONFIRMATION_WINDOW_MILLIS = 20_000L",
  'pending.remove(actorId)',
  'pending.remove(player.getUniqueId())',
  'player.hasPermission("prisma.command.tpall")',
  'actor.hasPermission("prisma.command.tpall")',
  "target.teleportAsync(destination.clone())",
  '"[TPALL] Подтверждено: инициатор="',
  '"[TPALL] Результат: инициатор="',
  "RpcNames.RECORD_MINECRAFT_EVENT",
  "supabase.postRpcAsync(RpcNames.RECORD_MINECRAFT_EVENT, body)",
  '"p_event_type", "COMMAND"',
]) {
  if (!tpAllCommand.includes(marker)) {
    failures.push("Confirmed /tpall implementation is missing a safety/audit contract: " + marker);
  }
}
const tpAllConfirm = tpAllCommand.slice(
  tpAllCommand.indexOf("private void confirm("),
  tpAllCommand.indexOf("private boolean authorizesTpAll(")
);
if (!tpAllConfirm.includes("UUID actorId = actor.getUniqueId();") ||
    !tpAllConfirm.includes("pending.remove(actorId)")) {
  failures.push("Confirmed /tpall must consume the pending request for the confirming actor");
}
for (const marker of [
  '"prisma.command.tpall"',
  'case "prisma.command.tpall" ->',
  '"admin".equals(role)',
  '"head_admin".equals(role)',
  '"owner".equals(role)',
  '"content_maker".equals(role)',
  'case "content_maker" -> "§5[КМ] §f"',
]) {
  if (!roleDisplay.includes(marker)) {
    failures.push("The /tpall permission contract must allow the admin hierarchy and Content Maker: " + marker);
  }
}
const tpAllPermissionStart = roleDisplay.indexOf('case "prisma.command.tpall" ->');
const tpAllPermissionEnd = tpAllPermissionStart < 0 ? -1 : roleDisplay.indexOf(";", tpAllPermissionStart);
const tpAllPermissionBody = tpAllPermissionEnd < 0
  ? ""
  : roleDisplay.slice(tpAllPermissionStart, tpAllPermissionEnd);
if (!tpAllPermissionBody ||
    tpAllPermissionBody.includes('"head_staff"') ||
    !tpAllPermissionBody.includes('"content_maker".equals(role)') ||
    !tpAllPermissionBody.includes('"head_admin".equals(role)') ||
    !tpAllPermissionBody.includes('"owner".equals(role)') ||
    !tpAllPermissionBody.includes('"moderation".equals(branch) && priority >= 60')) {
  failures.push("/tpall must be limited to high-level admins and Content Maker; staff roles outside that allowlist are forbidden");
}
for (const marker of [
  "RpcNames.GET_STAFF_IDENTITY",
  "authorizesTpAll(identity)",
  "private boolean authorizesTpAll(JsonObject identity)",
  "priority >= 60",
  "Актуальные права не подтверждены. Телепортация отменена.",
]) {
  if (!tpAllCommand.includes(marker)) {
    failures.push("/tpall must fail closed unless its current canonical PRISMA role is confirmed: " + marker);
  }
}
if (!pluginYaml.includes("prisma.command.tpall") || !pluginYaml.includes("  tpall:") ||
    !spawnEntrypoint.includes('new TpAllCommand(this, cache, supabase)') ||
    !spawnEntrypoint.includes('getCommand("tpall")') ||
    !spawnEntrypoint.includes('bindGatedCommand(tpall, tpAllCommand, tpAllCommand, modules, "minecraft-tpall")')) {
  failures.push("The confirmed /tpall command must be registered and gated by the Minecraft module");
}
if (!minecraftCatalog.includes('"command": "/tpall"') ||
    !minecraftCatalog.includes('"confirm"') ||
    !minecraftCatalog.includes("Подтвердить запрос в течение 20 секунд") ||
    !minecraftCatalog.includes('"cancel"')) {
  failures.push("Minecraft command catalog must document /tpall and its confirmation/cancel flow");
}
if (!botMinecraftCommands.includes('"mc_commands"') || !botMinecraftCommands.includes("render_catalog(platform)")) {
  failures.push("Telegram bot must expose the Minecraft command catalog");
}

const publicSiteData = read("site/src/lib/data.ts");
for (const table of [
  "news",
  "clans",
  "seasons",
  "events",
  "wiki_pages",
  "media_items",
  "awards",
]) {
  if (new RegExp(`\\.from\\(\\\"${table}\\\"\\)`).test(publicSiteData)) {
    failures.push(`site/src/lib/data.ts: public table ${table} must be read through an RPC gateway`);
  }
}
for (const field of [
  "PUBLIC_RPC.news",
  "PUBLIC_RPC.clans",
  "PUBLIC_RPC.seasons",
  "PUBLIC_RPC.events",
  "PUBLIC_RPC.wiki",
  "PUBLIC_RPC.media",
  "PUBLIC_RPC.awards",
]) {
  if (!publicSiteData.includes(field)) {
    failures.push("site/src/lib/data.ts: missing public gateway consumer " + field);
  }
}

const newsDetailPage = read("site/src/app/news/[id]/page.tsx");
if (newsDetailPage.includes('.from("news")') || !newsDetailPage.includes("PUBLIC_RPC.news")) {
  failures.push("site news detail page must use the public news RPC gateway");
}

const publicSchemaAclMigration = read("supabase/migrations/20260928184000_prisma_public_schema_create_acl_hardening.sql");
if (!publicSchemaAclMigration.toLowerCase().includes("revoke create on schema public from public, anon, authenticated")) {
  failures.push("public schema ACL hardening must revoke CREATE from public, anon, and authenticated");
}

const publicDefaultPrivilegeLockdown = read("supabase/migrations/20260928170811_prisma_public_default_privileges_lockdown.sql").toLowerCase();
for (const statement of [
  "revoke select, insert, update, delete on tables from anon, authenticated, service_role",
  "revoke usage, select, update on sequences from anon, authenticated, service_role",
  "revoke execute on functions from public, anon, authenticated, service_role",
]) {
  if (!publicDefaultPrivilegeLockdown.includes(statement)) {
    failures.push("public default privilege lockdown is missing required: " + statement);
  }
}

const authRateLimitMigration = read("supabase/migrations/20260928183000_prisma_auth_rate_limit_search_path_hardening.sql");
const botLoginCodeHardening = read("supabase/migrations/20260928163556_prisma_bot_login_code_search_path_hardening.sql");
if (!/create or replace function public\.bot_consume_login_code\([\s\S]*?security definer\s+set search_path = ''/i.test(botLoginCodeHardening)) {
  failures.push("bot login-code gateway must use SECURITY DEFINER with an empty search_path");
}
if (!botLoginCodeHardening.includes("revoke execute on function public.bot_consume_login_code(text, bigint) from public, anon, authenticated")) {
  failures.push("bot login-code gateway must revoke EXECUTE from client roles");
}
if (!botLoginCodeHardening.includes("grant execute on function public.bot_consume_login_code(text, bigint) to service_role")) {
  failures.push("bot login-code gateway must grant EXECUTE to service_role");
}
if (!/create or replace function public\.consume_login_rate_limit\([\s\S]*?security definer\s+set search_path = ''/i.test(authRateLimitMigration)) {
  failures.push("auth rate-limit gateway must use SECURITY DEFINER with an empty search_path");
}
if (!authRateLimitMigration.includes("from public.login_rate_limits")) {
  failures.push("auth rate-limit gateway must schema-qualify login_rate_limits");
}
if (!authRateLimitMigration.includes("pg_catalog.make_interval")) {
  failures.push("auth rate-limit gateway must schema-qualify make_interval");
}
if (!authRateLimitMigration.includes("grant execute on function public.consume_login_rate_limit(text, integer, integer) to service_role")) {
  failures.push("auth rate-limit gateway must grant EXECUTE only to service_role");
}

const rateLimitSource = read("site/src/lib/rate-limit.ts");
if (!rateLimitSource.includes("AUTH_RATE_LIMIT_RPC.consume")) {
  failures.push("site rate-limit helper must use shared consume_login_rate_limit contract");
}
if (rateLimitSource.includes('rpc("consume_login_rate_limit"')) {
  failures.push("site rate-limit helper must not hardcode consume_login_rate_limit");
}
if (!rateLimitSource.includes('return false;')) {
  failures.push("site rate-limit helper must fail closed when the limiter RPC fails");
}

const healthApiSource = read("site/src/app/api/health/route.ts");
if (healthApiSource.includes("SUPABASE_SERVICE_ROLE_KEY")) {
  failures.push("site health endpoint must not depend on the service-role secret");
}
if (healthApiSource.includes("NEXT_PUBLIC_BOT_USERNAME")) {
  failures.push("site health endpoint must not depend on unrelated bot configuration");
}

const publicRpcConsumers = [
  ["site/src/app/api/health/route.ts", "PUBLIC_RPC.serverStatus"],
  ["site/src/lib/data.ts", "PUBLIC_RPC.serverStatus"],
  ["site/src/lib/data.ts", "PUBLIC_RPC.polls"],
  ["site/src/lib/data.ts", "PUBLIC_RPC.mapData"],
];
for (const [file, contractRef] of publicRpcConsumers) {
  const source = read(file);
  if (!source.includes(contractRef)) {
    failures.push(file + ": public RPC consumer must use " + contractRef);
  }
}

for (const [file, rpcName] of [
  ["site/src/app/api/health/route.ts", "get_public_server_status"],
  ["site/src/lib/data.ts", "get_public_server_status"],
  ["site/src/lib/data.ts", "get_public_polls"],
  ["site/src/lib/data.ts", "get_public_map_data"],
]) {
  const source = read(file);
  if (source.includes('db.rpc("' + rpcName + '"')) {
    failures.push(file + ": public RPC " + rpcName + " must not be hardcoded");
  }
}

const pluginModuleGate = read("minecraft-plugin/src/main/java/team/prisma/plugin/modules/ModuleStateCache.java");
const pluginModuleMain = read("minecraft-plugin/src/main/java/team/prisma/plugin/PrismaPlugin.java");
const pluginModuleBuild = read("minecraft-plugin/build.gradle.kts");
const pluginModuleRpcNames = read("minecraft-plugin/src/main/java/team/prisma/plugin/http/RpcNames.java");
const pluginModuleRpcTransport = read("minecraft-plugin/src/main/java/team/prisma/plugin/http/SupabaseClient.java");
for (const marker of [
  'plugin.getResource("prisma/registry.json")',
  'RpcNames.GET_PUBLIC_MODULE_STATES',
  'postRpcJsonSync',
  'lastSuccessfulRefreshNanos',
  'snapshot.get(moduleId)',
  'return false',
  'dependencies.get(moduleId)',
]) {
  if (!pluginModuleGate.includes(marker)) failures.push("Minecraft module runtime gate is missing required behavior: " + marker);
}
if (!pluginModuleBuild.includes('rootProject.file("../modules/registry.json")') ||
    !pluginModuleBuild.includes('into("prisma")')) {
  failures.push("Minecraft plugin build must bundle the canonical modules/registry.json");
}
if (!pluginModuleRpcNames.includes('GET_PUBLIC_MODULE_STATES = "get_public_module_states"') ||
    !pluginModuleRpcTransport.includes("public JsonElement postRpcJsonSync(")) {
  failures.push("Minecraft plugin must use the shared module-state RPC and preserve JSON array responses");
}
for (const marker of [
  'bindGatedCommand(clan, clanCommand, clanCommand, modules, "minecraft-clan-commands")',
  'bindGatedCommand(village, villageCommand, villageCommand, modules, "minecraft-village-commands")',
  'bindGatedCommand(commands, commandCatalog, null, modules, "minecraft")',
  'new ModerationPollTask(this, supabase, cache, modules, getLogger())',
  'new ServerMetricsTask(this, supabase, modules, getLogger())',
]) {
  if (!pluginModuleMain.includes(marker)) failures.push("Minecraft entrypoint is missing module gate wiring: " + marker);
}
for (const [file, marker] of [
  ["minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ModerationPollTask.java", 'modules.isEnabled("minecraft") || !modules.isEnabled("moderation")'],
  ["minecraft-plugin/src/main/java/team/prisma/plugin/tasks/ServerMetricsTask.java", 'modules.isEnabled("analytics")'],
  ["minecraft-plugin/src/main/java/team/prisma/plugin/tasks/PlayerStatsTask.java", 'modules.isEnabled("analytics")'],
]) {
  if (!read(file).includes(marker)) failures.push(file + ": scheduled runtime work must honor module state");
}

for (const [file, marker] of [
  ["minecraft-plugin/src/main/java/team/prisma/plugin/listeners/JoinQuitListener.java", 'modules.isEnabled("analytics")'],
  ["minecraft-plugin/src/main/java/team/prisma/plugin/listeners/ChatListener.java", 'modules.isEnabled("chat")'],
  ["minecraft-plugin/src/main/java/team/prisma/plugin/listeners/CommandListener.java", 'modules.isEnabled("analytics")'],
  ["minecraft-plugin/src/main/java/team/prisma/plugin/listeners/BlockPlaceListener.java", 'modules.isEnabled("analytics")'],
]) {
  if (!read(file).includes(marker)) failures.push(file + ": listener must honor the owning module state");
}
for (const marker of [
  'new ChatListener(this, supabase, cache, modules)',
  'new CommandListener(supabase, cache, modules)',
  'new JoinQuitListener(this, supabase, cache, playerStatsTask, roleDisplay, modules)',
  'new BlockPlaceListener(cache, modules)',
]) {
  if (!pluginModuleMain.includes(marker)) failures.push("Minecraft entrypoint is missing module-state listener wiring: " + marker);
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("PRISMA architecture gate passed");