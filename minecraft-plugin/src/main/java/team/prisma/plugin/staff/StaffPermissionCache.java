package team.prisma.plugin.staff;

import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;

import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

public final class StaffPermissionCache {
    private static final long PERMISSION_TTL_NANOS = Duration.ofSeconds(60).toNanos();

    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final Map<UUID, Map<String, PermissionEntry>> permissions = new ConcurrentHashMap<>();

    public StaffPermissionCache(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
    }

    public void start() {
        refresh();
        Bukkit.getScheduler().runTaskTimer(plugin, this::refresh, 20L * 10L, 20L * 20L);
    }

    private void refresh() {
        var onlineIds = Bukkit.getOnlinePlayers().stream()
            .map(Player::getUniqueId)
            .collect(java.util.stream.Collectors.toSet());
        permissions.keySet().removeIf(playerUuid -> !onlineIds.contains(playerUuid));

        for (Player player : Bukkit.getOnlinePlayers()) {
            UUID playerUuid = player.getUniqueId();
            String userId = cache.userIdOf(playerUuid);
            if (userId == null) {
                put(playerUuid, "clan.manage", false);
                continue;
            }
            check(playerUuid, userId, "clan.manage");
        }
    }

    private void check(UUID playerUuid, String userId, String permission) {
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_permission_key", permission);
        supabase.postRpcAsync(RpcNames.GET_STAFF_PERMISSION, body).thenAccept(result -> {
            boolean allowed = parseAllowed(result);
            put(playerUuid, permission, allowed);
        }).exceptionally(error -> {
            put(playerUuid, permission, false);
            Bukkit.getLogger().warning("[StaffPermission] refresh failed for " + playerUuid + ": " + error.getMessage());
            return null;
        });
    }

    /**
     * Resolves a permission asynchronously, but always invokes the callback on Bukkit's main thread.
     * A failed refresh overwrites cached access with deny, rather than keeping old grants.
     */
    public void checkNow(Player player, String permission, java.util.function.Consumer<Boolean> callback) {
        UUID playerUuid = player.getUniqueId();
        String userId = cache.userIdOf(playerUuid);
        if (userId == null || userId.isBlank()) {
            put(playerUuid, permission, false);
            runOnMain(() -> callback.accept(false));
            return;
        }

        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_permission_key", permission);
        supabase.postRpcAsync(RpcNames.GET_STAFF_PERMISSION, body).thenAccept(result -> {
            boolean allowed = parseAllowed(result);
            put(playerUuid, permission, allowed);
            runOnMain(() -> callback.accept(allowed));
        }).exceptionally(error -> {
            put(playerUuid, permission, false);
            Bukkit.getLogger().warning("[StaffPermission] check failed for " + playerUuid + ": " + error.getMessage());
            runOnMain(() -> callback.accept(false));
            return null;
        });
    }

    private static boolean parseAllowed(JsonObject result) {
        if (result == null || !result.isJsonObject()) return false;
        if (result.has("allowed") && !result.get("allowed").isJsonNull()) {
            return result.get("allowed").getAsBoolean();
        }
        return result.has("success")
            && !result.get("success").isJsonNull()
            && result.get("success").getAsBoolean();
    }

    private void put(UUID playerUuid, String permission, boolean allowed) {
        permissions.computeIfAbsent(playerUuid, ignored -> new ConcurrentHashMap<>())
            .put(permission, new PermissionEntry(allowed, System.nanoTime()));
    }

    private void runOnMain(Runnable action) {
        if (Bukkit.isPrimaryThread()) {
            action.run();
        } else {
            Bukkit.getScheduler().runTask(plugin, action);
        }
    }

    public boolean has(UUID player, String permission) {
        PermissionEntry entry = permissions.getOrDefault(player, Map.of()).get(permission);
        if (entry == null) return false;
        if (System.nanoTime() - entry.checkedAtNanos() > PERMISSION_TTL_NANOS) return false;
        return entry.allowed();
    }

    public void clear(UUID player) {
        permissions.remove(player);
    }

    private record PermissionEntry(boolean allowed, long checkedAtNanos) {}
}
