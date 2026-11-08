package team.prisma.plugin.listeners;

import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.SupabaseClient;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.staff.PlayerRoleDisplay;
import team.prisma.plugin.tasks.PlayerStatsTask;
import team.prisma.plugin.modules.ModuleStateCache;

public final class JoinQuitListener implements Listener {
    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final PlayerStatsTask playerStatsTask;
    private final PlayerRoleDisplay roleDisplay;
    private final ModuleStateCache modules;
    // Main-thread-only identity for the current connection; stale async callbacks must not mutate a rejoined player.
    private static final int MAX_IDENTITY_LOOKUP_RETRIES = 12;
    private static final long IDENTITY_RETRY_DELAY_TICKS = 20L * 30L;
    private static final long STATS_BASELINE_RETRY_BASE_TICKS = 20L * 30L;
    private static final long STATS_BASELINE_RETRY_MAX_TICKS = 20L * 60L * 5L;
    private static final int MAX_STATS_BASELINE_BACKOFF_STAGE = 4;
    private final Map<UUID, Object> playerSessions = new HashMap<>();
    private final Map<UUID, Integer> identityRetryAttempts = new HashMap<>();
    private final Map<UUID, Integer> statsBaselineRetryStages = new HashMap<>();

    public JoinQuitListener(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache, PlayerStatsTask playerStatsTask, PlayerRoleDisplay roleDisplay, ModuleStateCache modules) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.playerStatsTask = playerStatsTask;
        this.roleDisplay = roleDisplay;
        this.modules = modules;
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        Player player = event.getPlayer();

        // Capture Bukkit-owned state while handling the join event on the main thread.
        UUID playerUuid = player.getUniqueId();
        String nickname = player.getName();
        String worldName = player.getWorld().getName();
        Object sessionToken = new Object();
        playerSessions.put(playerUuid, sessionToken);
        identityRetryAttempts.remove(playerUuid);
        statsBaselineRetryStages.remove(playerUuid);

        requestIdentityLookup(player, playerUuid, nickname, worldName, sessionToken);
    }

    private void requestIdentityLookup(Player player, UUID playerUuid, String nickname, String worldName, Object sessionToken) {
        if (!plugin.isEnabled() || !isCurrentConnection(player, playerUuid, sessionToken)) return;

        JsonObject lookup = new JsonObject();
        lookup.addProperty("p_nickname", nickname);
        lookup.addProperty("p_minecraft_uuid", playerUuid.toString());

        try {
            supabase.postRpcAsync(RpcNames.GET_MINECRAFT_USER_V2, lookup)
                .thenAccept(user -> {
                    if (user == null || user.has("error")) {
                        scheduleIdentityRetry(player, playerUuid, nickname, worldName, sessionToken);
                        return;
                    }

                    String userId = field(user, "id");
                    if (userId == null || userId.isBlank()) {
                        scheduleIdentityRetry(player, playerUuid, nickname, worldName, sessionToken);
                        return;
                    }

                    String clanId = field(user, "clan_id");
                    String platform = field(user, "platform");
                    String mutedUntilRaw = field(user, "muted_until");
                    boolean muted = user.has("is_muted")
                        && !user.get("is_muted").isJsonNull()
                        && user.get("is_muted").getAsBoolean();
                    Instant muteExpiry = mutedUntilRaw != null ? Instant.parse(mutedUntilRaw) : null;

                    plugin.getServer().getScheduler().runTask(plugin, () -> {
                        if (!isCurrentConnection(player, playerUuid, sessionToken)) return;

                        identityRetryAttempts.remove(playerUuid);
                        cache.onJoin(playerUuid, userId, platform, clanId, muted ? muteExpiry : null, 0L);
                        if (muted && muteExpiry == null) cache.onJoinMutedForever(playerUuid);

                        roleDisplay.refresh(player);

                        if (modules.isEnabled("analytics")) {
                            JsonObject eventBody = new JsonObject();
                            eventBody.addProperty("p_user_id", userId);
                            eventBody.addProperty("p_event_type", "JOIN");
                            eventBody.addProperty("p_nickname", nickname);
                            eventBody.addProperty("p_world", worldName);
                            supabase.postRpcAsync(RpcNames.RECORD_MINECRAFT_EVENT, eventBody)
                                .exceptionally(error -> {
                                    Bukkit.getLogger().warning("[Events] JOIN record failed for " + nickname + ": " + error.getMessage());
                                    return null;
                                });

                            recordSessionActivity(userId);
                        }

                        loadStatsBaseline(player, playerUuid, userId, nickname, sessionToken);
                    });
                })
                .exceptionally(error -> {
                    Bukkit.getLogger().warning("[Join] player identity lookup failed for " + nickname + ": " + error.getMessage());
                    scheduleIdentityRetry(player, playerUuid, nickname, worldName, sessionToken);
                    return null;
                });
        } catch (RuntimeException lookupError) {
            // postRpcAsync can fail before a CompletableFuture exists; preserve the same retry path.
            Bukkit.getLogger().warning("[Join] player identity lookup could not start for " + nickname + ": " + lookupError.getMessage());
            scheduleIdentityRetry(player, playerUuid, nickname, worldName, sessionToken);
        }
    }

    private void scheduleIdentityRetry(Player player, UUID playerUuid, String nickname, String worldName, Object sessionToken) {
        if (!plugin.isEnabled()) return;
        try {
            plugin.getServer().getScheduler().runTask(plugin, () -> {
                if (!isCurrentConnection(player, playerUuid, sessionToken)) return;

                int attempts = identityRetryAttempts.getOrDefault(playerUuid, 0);
                if (attempts >= MAX_IDENTITY_LOOKUP_RETRIES) {
                    Bukkit.getLogger().warning("[Join] identity lookup retries exhausted for " + nickname
                        + "; reconnect after fixing the PRISMA identity binding");
                    return;
                }
                identityRetryAttempts.put(playerUuid, attempts + 1);

                try {
                    plugin.getServer().getScheduler().runTaskLater(plugin, () -> {
                        if (isCurrentConnection(player, playerUuid, sessionToken)) {
                            requestIdentityLookup(player, playerUuid, nickname, worldName, sessionToken);
                        }
                    }, IDENTITY_RETRY_DELAY_TICKS);
                } catch (RuntimeException schedulingError) {
                    identityRetryAttempts.remove(playerUuid);
                    Bukkit.getLogger().warning("[Join] identity retry could not be scheduled for " + nickname + ": " + schedulingError.getMessage());
                }
            });
        } catch (RuntimeException schedulingError) {
            Bukkit.getLogger().warning("[Join] identity retry could not be queued for " + nickname + ": " + schedulingError.getMessage());
        }
    }

    private static final int MC_SESSION_POINTS = 5;

    private void recordSessionActivity(String userId) {
        if (!modules.isEnabled("analytics")) return;
        JsonObject rpc = new JsonObject();
        rpc.addProperty("p_user_id", userId);
        rpc.addProperty("p_source", "MC_SESSION");
        rpc.addProperty("p_points", MC_SESSION_POINTS);
        rpc.add("p_metadata", new JsonObject());
        supabase.postRpcAsync(RpcNames.RECORD_ACTIVITY_EVENT, rpc)
            .exceptionally(error -> {
                Bukkit.getLogger().warning("[Activity] record failed for " + userId + ": " + error.getMessage());
                return null;
            });
    }

    private void loadStatsBaseline(Player player, UUID playerUuid, String userId, String nickname, Object sessionToken) {
        if (!plugin.isEnabled()) return;

        JsonObject statsBody = new JsonObject();
        statsBody.addProperty("p_user_id", userId);

        playerStatsTask.awaitPendingWrites(playerUuid)
            .thenCompose(ignored -> supabase.postRpcAsync(RpcNames.GET_PLAYER_STATS, statsBody))
            .thenAccept(stats -> {
                if (stats == null || stats.has("error")
                    || !hasNonNegativeCount(stats, "blocks_placed")
                    || !hasNonNegativeCount(stats, "blocks_broken")
                    || !hasNonNegativeCount(stats, "mobs_killed")) {
                    Bukkit.getLogger().warning("[Stats] baseline response invalid for " + nickname + "; retrying with bounded backoff");
                    scheduleStatsBaselineRetry(player, playerUuid, userId, nickname, sessionToken);
                    return;
                }

                long persistedBlocksPlaced = longField(stats, "blocks_placed");
                long persistedBlocksBroken = longField(stats, "blocks_broken");
                long persistedMobsKilled = longField(stats, "mobs_killed");

                plugin.getServer().getScheduler().runTask(plugin, () -> {
                    if (!isCurrentSession(player, playerUuid, userId, sessionToken)
                        || cache.hasStatsBaseline(playerUuid)) return;

                    cache.mergeBlocksPlacedBaseline(playerUuid, persistedBlocksPlaced);
                    cache.mergeBlocksBrokenBaseline(playerUuid, persistedBlocksBroken);
                    cache.mergeMobsKilledBaseline(playerUuid, persistedMobsKilled);
                    cache.markStatsBaselineLoaded(playerUuid);
                    statsBaselineRetryStages.remove(playerUuid);
                    playerStatsTask.sync(player);
                });
            })
            .exceptionally(error -> {
                Bukkit.getLogger().warning("[Stats] baseline load failed for " + nickname + ": " + error.getMessage() + "; retrying with bounded backoff");
                scheduleStatsBaselineRetry(player, playerUuid, userId, nickname, sessionToken);
                return null;
            });
    }

    private void scheduleStatsBaselineRetry(Player player, UUID playerUuid, String userId, String nickname, Object sessionToken) {
        if (!plugin.isEnabled()) return;
        plugin.getServer().getScheduler().runTask(plugin, () -> {
            if (!isCurrentSession(player, playerUuid, userId, sessionToken)
                || cache.hasStatsBaseline(playerUuid)) return;

            int stage = Math.min(
                statsBaselineRetryStages.getOrDefault(playerUuid, 0),
                MAX_STATS_BASELINE_BACKOFF_STAGE
            );
            statsBaselineRetryStages.put(playerUuid, Math.min(stage + 1, MAX_STATS_BASELINE_BACKOFF_STAGE));
            long retryDelayTicks = statsBaselineRetryDelayTicks(stage);

            plugin.getServer().getScheduler().runTaskLater(plugin, () -> {
                if (isCurrentSession(player, playerUuid, userId, sessionToken)
                    && !cache.hasStatsBaseline(playerUuid)) {
                    loadStatsBaseline(player, playerUuid, userId, nickname, sessionToken);
                }
            }, retryDelayTicks);
        });
    }

    private static long statsBaselineRetryDelayTicks(int stage) {
        int boundedStage = Math.max(0, Math.min(stage, MAX_STATS_BASELINE_BACKOFF_STAGE));
        long exponentialDelay = STATS_BASELINE_RETRY_BASE_TICKS * (1L << boundedStage);
        return Math.min(exponentialDelay, STATS_BASELINE_RETRY_MAX_TICKS);
    }

    private boolean isCurrentConnection(Player player, UUID playerUuid, Object sessionToken) {
        return playerSessions.get(playerUuid) == sessionToken
            && player.isOnline()
            && playerUuid.equals(player.getUniqueId());
    }

    private boolean isCurrentSession(Player player, UUID playerUuid, String userId, Object sessionToken) {
        return isCurrentConnection(player, playerUuid, sessionToken)
            && userId.equals(cache.userIdOf(playerUuid));
    }

    private static boolean hasNonNegativeCount(JsonObject obj, String key) {
        if (!obj.has(key) || obj.get(key).isJsonNull() || !obj.get(key).isJsonPrimitive()
            || !obj.getAsJsonPrimitive(key).isNumber()) return false;
        try {
            return obj.get(key).getAsLong() >= 0L;
        } catch (NumberFormatException | UnsupportedOperationException e) {
            return false;
        }
    }


    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        Player player = event.getPlayer();
        UUID playerUuid = player.getUniqueId();
        playerSessions.remove(playerUuid);
        identityRetryAttempts.remove(playerUuid);
        statsBaselineRetryStages.remove(playerUuid);
        String nickname = player.getName();
        String worldName = player.getWorld().getName();
        String userId = cache.userIdOf(playerUuid);

        if (userId != null && modules.isEnabled("analytics")) {
            JsonObject eventBody = new JsonObject();
            eventBody.addProperty("p_user_id", userId);
            eventBody.addProperty("p_event_type", "QUIT");
            eventBody.addProperty("p_nickname", nickname);
            eventBody.addProperty("p_world", worldName);
            supabase.postRpcAsync(RpcNames.RECORD_MINECRAFT_EVENT, eventBody)
                .exceptionally(error -> {
                    Bukkit.getLogger().warning("[Events] QUIT record failed for " + nickname + ": " + error.getMessage());
                    return null;
                });
        }

        // Capture a final stats snapshot before clearing per-player cached counters.
        playerStatsTask.persistQuitSnapshot(player);
        cache.onQuit(playerUuid);
        roleDisplay.clear(playerUuid);
    }


    private static String field(JsonObject obj, String key) {
        return obj.has(key) && !obj.get(key).isJsonNull() ? obj.get(key).getAsString() : null;
    }

    private static long longField(JsonObject obj, String key) {
        if (!obj.has(key) || obj.get(key).isJsonNull()) return 0L;
        try {
            return Math.max(0L, obj.get(key).getAsLong());
        } catch (NumberFormatException | UnsupportedOperationException e) {
            return 0L;
        }
    }
}
