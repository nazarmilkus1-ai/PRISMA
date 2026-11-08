package team.prisma.plugin.tasks;

import com.google.gson.JsonObject;
import org.bukkit.Statistic;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.modules.ModuleStateCache;

import com.google.gson.JsonElement;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.logging.Logger;

/** Periodically mirrors vanilla Minecraft statistics into the PRISMA player_stats table. */
public final class PlayerStatsTask implements Runnable {
    private static final int MAX_QUIT_SNAPSHOT_RETRIES = 12;
    private static final long QUIT_SNAPSHOT_RETRY_DELAY_TICKS = 20L * 30L;
    private record QuitSnapshot(
        UUID playerUuid,
        String userId,
        String nickname,
        JsonObject payload,
        boolean baselineLoaded,
        long blocksPlacedDelta,
        long blocksBrokenDelta,
        long mobsKilledDelta
    ) {}

    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;
    private final Logger logger;
    // Serialize each player's snapshots so a slower old write can never overwrite a newer one.
    private final Map<UUID, CompletableFuture<Void>> pendingWrites = new ConcurrentHashMap<>();

    public PlayerStatsTask(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache, ModuleStateCache modules, Logger logger) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.modules = modules;
        this.logger = logger;
    }

    @Override
    public void run() {
        if (!modules.isEnabled("analytics")) return;
        for (Player player : plugin.getServer().getOnlinePlayers()) {
            sync(player);
        }
    }

    /**
     * Mirrors one player's Bukkit statistics into PRISMA.
     * Must be invoked on the Bukkit main thread because it reads Player statistics.
     */
    public void sync(Player player) {
        if (!modules.isEnabled("analytics")) return;
        if (player == null || !player.isOnline()) return;

        UUID playerUuid = player.getUniqueId();
        String nickname = player.getName();
        String userId = cache.userIdOf(playerUuid);
        if (userId == null || userId.isBlank() || !cache.hasStatsBaseline(playerUuid)) return;

        long blocksPlaced = cache.blocksPlaced(playerUuid);
        long blocksBroken = cache.blocksBroken(playerUuid);
        long mobsKilled = cache.mobsKilled(playerUuid);

        enqueueWrite(playerUuid, nickname, statisticsPayload(player, userId, blocksPlaced, blocksBroken, mobsKilled));
    }


    /**
     * Captures a final quit snapshot on the Bukkit thread. If the persisted baseline was not
     * loaded yet, it saves the vanilla snapshot plus local block/mob deltas after reading the DB.
     */
    public void persistQuitSnapshot(Player player) {
        if (!modules.isEnabled("analytics") || player == null) return;

        UUID playerUuid = player.getUniqueId();
        String nickname = player.getName();
        String userId = cache.userIdOf(playerUuid);
        long blocksPlaced = cache.blocksPlaced(playerUuid);
        long blocksBroken = cache.blocksBroken(playerUuid);
        long mobsKilled = cache.mobsKilled(playerUuid);
        boolean baselineLoaded = userId != null && !userId.isBlank() && cache.hasStatsBaseline(playerUuid);
        JsonObject payload = statisticsPayload(
            player, userId == null ? "" : userId,
            baselineLoaded ? blocksPlaced : 0L,
            baselineLoaded ? blocksBroken : 0L,
            baselineLoaded ? mobsKilled : 0L
        );

        if (baselineLoaded) {
            // Final quit writes need retry semantics too; never drop a final snapshot after clearing cache.
            persistQuitSnapshotAfterBaseline(new QuitSnapshot(
                playerUuid, userId, nickname, payload, true,
                blocksPlaced, blocksBroken, mobsKilled
            ));
            return;
        }

        // If identity or baseline loading was still in flight, persist the already-captured local deltas.
        // The queued async path resolves identity and DB baseline only after the Player object is no longer needed.
        persistQuitSnapshotAfterBaseline(new QuitSnapshot(
            playerUuid, userId, nickname, payload, false,
            blocksPlaced, blocksBroken, mobsKilled
        ));
    }

    private JsonObject statisticsPayload(Player player, String userId, long blocksPlaced, long blocksBroken, long mobsKilled) {
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_kills", safe(player, Statistic.PLAYER_KILLS));
        body.addProperty("p_deaths", safe(player, Statistic.DEATHS));
        body.addProperty("p_playtime_minutes", safe(player, Statistic.PLAY_ONE_MINUTE) / 1200L);
        body.addProperty("p_blocks_placed", blocksPlaced);
        body.addProperty("p_blocks_broken", blocksBroken);
        body.addProperty("p_mobs_killed", mobsKilled);
        body.addProperty("p_distance_walked", safe(player, Statistic.WALK_ONE_CM) / 100L);
        body.addProperty("p_damage_dealt", safe(player, Statistic.DAMAGE_DEALT));
        body.addProperty("p_damage_taken", safe(player, Statistic.DAMAGE_TAKEN));
        return body;
    }

    private void persistQuitSnapshotAfterBaseline(QuitSnapshot snapshot) {
        if (!plugin.isEnabled()) return;

        // Reserve the whole read-baseline -> merge-deltas -> write operation in the same per-player
        // queue as ordinary stats writes. A reconnect must wait for this full operation, not just the final upsert.
        CompletableFuture<Void> next = pendingWrites.compute(snapshot.playerUuid(), (uuid, previous) -> {
            CompletableFuture<Void> ready = previous == null
                ? CompletableFuture.completedFuture(null)
                : previous.handle((ignored, failure) -> null);
            return ready.thenCompose(ignored -> persistQuitSnapshotAttempt(snapshot, 0));
        });
        next.whenComplete((ignored, error) -> {
            if (error != null) {
                logger.warning("[Stats] quit snapshot could not be persisted for " + snapshot.nickname()
                    + ": " + error.getMessage());
            }
            pendingWrites.remove(snapshot.playerUuid(), next);
        });
    }

    private CompletableFuture<Void> persistQuitSnapshotAttempt(QuitSnapshot snapshot, int attempt) {
        if (!plugin.isEnabled()) {
            return CompletableFuture.failedFuture(new IllegalStateException("plugin is shutting down"));
        }

        CompletableFuture<Void> result = new CompletableFuture<>();

        if (snapshot.userId() == null || snapshot.userId().isBlank()) {
            JsonObject identityRequest = new JsonObject();
            identityRequest.addProperty("p_nickname", snapshot.nickname());
            identityRequest.addProperty("p_minecraft_uuid", snapshot.playerUuid().toString());
            try {
                supabase.postRpcAsync(RpcNames.GET_MINECRAFT_USER_V2, identityRequest).whenComplete((user, identityError) -> {
                    String resolvedUserId = stringField(user, "id");
                    if (identityError != null || user == null || user.has("error")
                        || resolvedUserId == null || resolvedUserId.isBlank()) {
                        String detail = identityError != null ? identityError.getMessage() : "player identity not available";
                        logger.warning("[Stats] quit identity lookup failed for " + snapshot.nickname()
                            + ": " + detail + retryDisposition(attempt));
                        retryQuitSnapshot(snapshot, attempt, result);
                        return;
                    }

                    JsonObject identifiedPayload = snapshot.payload().deepCopy();
                    identifiedPayload.addProperty("p_user_id", resolvedUserId);
                    QuitSnapshot identified = new QuitSnapshot(
                        snapshot.playerUuid(), resolvedUserId, snapshot.nickname(), identifiedPayload,
                        snapshot.baselineLoaded(),
                        snapshot.blocksPlacedDelta(), snapshot.blocksBrokenDelta(), snapshot.mobsKilledDelta()
                    );
                    persistQuitSnapshotAttempt(identified, attempt).whenComplete((ignored, error) -> {
                        if (error == null) result.complete(null);
                        else result.completeExceptionally(error);
                    });
                });
            } catch (RuntimeException identityError) {
                logger.warning("[Stats] quit identity request could not start for " + snapshot.nickname()
                    + ": " + identityError.getMessage() + retryDisposition(attempt));
                retryQuitSnapshot(snapshot, attempt, result);
            }
            return result;
        }

        if (snapshot.baselineLoaded()) {
            // Retry the exact same absolute snapshot; re-reading baseline after an ambiguous timeout
            // could count the same deltas twice if the database committed the first write.
            persistQuitPayloadWithRetry(snapshot, snapshot.payload(), attempt, result);
            return result;
        }

        JsonObject request = new JsonObject();
        request.addProperty("p_user_id", snapshot.userId());

        try {
            supabase.postRpcAsync(RpcNames.GET_PLAYER_STATS, request).whenComplete((stats, readError) -> {
                if (readError != null || !hasNonNegativeCount(stats, "blocks_placed")
                    || !hasNonNegativeCount(stats, "blocks_broken")
                    || !hasNonNegativeCount(stats, "mobs_killed")) {
                    String detail = readError == null ? "invalid baseline response" : readError.getMessage();
                    logger.warning("[Stats] quit baseline attempt failed for " + snapshot.nickname()
                        + ": " + detail + retryDisposition(attempt));
                    retryQuitSnapshot(snapshot, attempt, result);
                    return;
                }

                JsonObject payload = snapshot.payload().deepCopy();
                payload.addProperty("p_blocks_placed", safeAdd(longField(stats, "blocks_placed"), snapshot.blocksPlacedDelta()));
                payload.addProperty("p_blocks_broken", safeAdd(longField(stats, "blocks_broken"), snapshot.blocksBrokenDelta()));
                payload.addProperty("p_mobs_killed", safeAdd(longField(stats, "mobs_killed"), snapshot.mobsKilledDelta()));

                // Freeze the absolute payload after the baseline read. Every write retry reuses
                // these exact values, preventing duplicate deltas on ambiguous network failures.
                persistQuitPayloadWithRetry(snapshot, payload, attempt, result);
            });
        } catch (RuntimeException readError) {
            logger.warning("[Stats] quit baseline request could not start for " + snapshot.nickname()
                + ": " + readError.getMessage() + retryDisposition(attempt));
            retryQuitSnapshot(snapshot, attempt, result);
        }
        return result;
    }

    private void persistQuitPayloadWithRetry(
        QuitSnapshot snapshot,
        JsonObject payload,
        int attempt,
        CompletableFuture<Void> result
    ) {
        if (!plugin.isEnabled()) {
            result.completeExceptionally(new IllegalStateException("plugin is shutting down; quit stats remain unsaved"));
            return;
        }

        try {
            supabase.postRpcAsync(RpcNames.UPSERT_PLAYER_STATS, payload).whenComplete((writeResult, writeError) -> {
                if (writeError == null) {
                    result.complete(null);
                    return;
                }
                logger.warning("[Stats] final quit snapshot write failed for " + snapshot.nickname()
                    + ": " + writeError.getMessage() + retryDisposition(attempt));
                retryQuitPayload(snapshot, payload, attempt, result);
            });
        } catch (RuntimeException writeError) {
            logger.warning("[Stats] final quit snapshot write could not start for " + snapshot.nickname()
                + ": " + writeError.getMessage() + retryDisposition(attempt));
            retryQuitPayload(snapshot, payload, attempt, result);
        }
    }

    private void retryQuitPayload(
        QuitSnapshot snapshot,
        JsonObject payload,
        int attempt,
        CompletableFuture<Void> result
    ) {
        if (attempt >= MAX_QUIT_SNAPSHOT_RETRIES) {
            result.completeExceptionally(new IllegalStateException(
                "quit snapshot write retries exhausted for " + snapshot.nickname()));
            return;
        }
        if (!plugin.isEnabled()) {
            result.completeExceptionally(new IllegalStateException("plugin is shutting down; quit stats remain unsaved"));
            return;
        }

        try {
            plugin.getServer().getScheduler().runTask(plugin, () -> {
                if (!plugin.isEnabled()) {
                    result.completeExceptionally(new IllegalStateException("plugin is shutting down; quit stats remain unsaved"));
                    return;
                }
                try {
                    plugin.getServer().getScheduler().runTaskLater(plugin, () ->
                        persistQuitPayloadWithRetry(snapshot, payload, attempt + 1, result),
                        QUIT_SNAPSHOT_RETRY_DELAY_TICKS
                    );
                } catch (RuntimeException schedulingError) {
                    result.completeExceptionally(schedulingError);
                }
            });
        } catch (RuntimeException schedulingError) {
            result.completeExceptionally(schedulingError);
        }
    }

    private static String retryDisposition(int attempt) {
        return attempt >= MAX_QUIT_SNAPSHOT_RETRIES
            ? "; retry limit reached, giving up"
            : "; retrying in 30 seconds";
    }

    private void retryQuitSnapshot(QuitSnapshot snapshot, int attempt, CompletableFuture<Void> result) {
        if (attempt >= MAX_QUIT_SNAPSHOT_RETRIES) {
            result.completeExceptionally(new IllegalStateException(
                "quit snapshot retries exhausted for " + snapshot.nickname()));
            return;
        }
        if (!plugin.isEnabled()) {
            result.completeExceptionally(new IllegalStateException("plugin is shutting down; quit stats remain unsaved"));
            return;
        }

        try {
            plugin.getServer().getScheduler().runTask(plugin, () -> {
                if (!plugin.isEnabled()) {
                    result.completeExceptionally(new IllegalStateException("plugin is shutting down; quit stats remain unsaved"));
                    return;
                }
                try {
                    plugin.getServer().getScheduler().runTaskLater(plugin, () -> {
                        persistQuitSnapshotAttempt(snapshot, attempt + 1)
                            .whenComplete((ignored, error) -> {
                                if (error == null) result.complete(null);
                                else result.completeExceptionally(error);
                            });
                    }, QUIT_SNAPSHOT_RETRY_DELAY_TICKS);
                } catch (RuntimeException schedulingError) {
                    result.completeExceptionally(schedulingError);
                }
            });
        } catch (RuntimeException schedulingError) {
            result.completeExceptionally(schedulingError);
        }
    }

    private static String stringField(JsonObject obj, String key) {
        if (obj == null || !obj.has(key) || obj.get(key).isJsonNull()) return null;
        try {
            return obj.get(key).getAsString();
        } catch (RuntimeException malformed) {
            return null;
        }
    }

    private static boolean hasNonNegativeCount(JsonObject obj, String key) {
        if (obj == null || !obj.has(key) || obj.get(key).isJsonNull()
            || !obj.get(key).isJsonPrimitive() || !obj.getAsJsonPrimitive(key).isNumber()) return false;
        try {
            return obj.get(key).getAsLong() >= 0L;
        } catch (NumberFormatException | UnsupportedOperationException e) {
            return false;
        }
    }

    private static long longField(JsonObject obj, String key) {
        JsonElement value = obj == null ? null : obj.get(key);
        if (value == null || value.isJsonNull()) return 0L;
        return Math.max(0L, value.getAsLong());
    }

    private static long safeAdd(long left, long right) {
        long a = Math.max(0L, left);
        long b = Math.max(0L, right);
        return Long.MAX_VALUE - a < b ? Long.MAX_VALUE : a + b;
    }

    /**
     * Waits for writes already queued for this identity before a reconnect reloads its DB baseline.
     * This prevents a fast rejoin from reading stale totals while the previous quit snapshot is pending.
     */
    public CompletableFuture<Void> awaitPendingWrites(UUID playerUuid) {
        CompletableFuture<Void> pending = pendingWrites.get(playerUuid);
        return pending == null
            ? CompletableFuture.completedFuture(null)
            : pending.handle((ignored, failure) -> null);
    }

    private void enqueueWrite(UUID playerUuid, String nickname, JsonObject body) {
        CompletableFuture<Void> next = pendingWrites.compute(playerUuid, (uuid, previous) -> {
            CompletableFuture<Void> ready = previous == null
                ? CompletableFuture.completedFuture(null)
                : previous.handle((ignored, failure) -> null);

            return ready.thenCompose(ignored -> {
                try {
                    return supabase.postRpcAsync(RpcNames.UPSERT_PLAYER_STATS, body)
                        .thenApply(result -> (Void) null)
                        .exceptionally(error -> {
                            logger.warning("[Stats] sync failed for " + nickname + ": " + error.getMessage());
                            return null;
                        });
                } catch (RuntimeException error) {
                    logger.warning("[Stats] sync could not start for " + nickname + ": " + error.getMessage());
                    return CompletableFuture.completedFuture(null);
                }
            });
        });
        next.whenComplete((ignored, error) -> pendingWrites.remove(playerUuid, next));
    }

    private static int safe(Player player, Statistic statistic) {
        try {
            return player.getStatistic(statistic);
        } catch (IllegalArgumentException e) {
            return 0;
        }
    }
}
