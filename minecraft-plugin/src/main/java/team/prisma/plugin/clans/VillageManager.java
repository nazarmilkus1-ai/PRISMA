package team.prisma.plugin.clans;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;

import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Logger;

public final class VillageManager {
    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final Logger logger;
    // Publish complete immutable snapshots so readers never observe a half-refreshed protection map.
    private volatile Map<UUID, Village> villages = Map.of();
    private final AtomicBoolean refreshInFlight = new AtomicBoolean(false);

    public VillageManager(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.logger = plugin.getLogger();
    }

    public void start() {
        refresh();
        Bukkit.getScheduler().runTaskTimerAsynchronously(plugin, this::refresh, 20L * 15L, 20L * 30L);
    }

    public void refresh() {
        // Avoid overlapping requests whose responses could arrive out of order.
        if (!refreshInFlight.compareAndSet(false, true)) return;

        supabase.postRpcAsync(RpcNames.LIST_ACTIVE_VILLAGES, new JsonObject())
            .thenAccept(payload -> {
                if (payload == null || !payload.has("villages") || !payload.get("villages").isJsonArray()) {
                    throw new IllegalStateException("list-active-villages RPC returned an invalid payload");
                }

                Map<UUID, Village> next = new HashMap<>();
                var villageRows = payload.getAsJsonArray("villages");
                int invalidRows = 0;

                for (var element : villageRows) {
                    try {
                        JsonObject row = element.getAsJsonObject();
                        UUID id = UUID.fromString(row.get("id").getAsString());
                        UUID clanId = UUID.fromString(row.get("clan_id").getAsString());
                        String name = row.get("name").getAsString();
                        String world = row.get("world").getAsString();
                        double centerX = row.get("center_x").getAsDouble();
                        double centerY = row.get("center_y").getAsDouble();
                        double centerZ = row.get("center_z").getAsDouble();
                        int radius = row.get("radius").getAsInt();
                        if (name.isBlank() || world.isBlank() || radius <= 0
                            || !Double.isFinite(centerX) || !Double.isFinite(centerY) || !Double.isFinite(centerZ)) {
                            throw new IllegalArgumentException("invalid village fields");
                        }
                        next.put(id, new Village(id, clanId, name, world, centerX, centerY, centerZ, radius));
                    } catch (Exception invalidRow) {
                        invalidRows++;
                    }
                }

                // A partial snapshot could silently unprotect a territory. Keep the last known-good snapshot instead.
                if (invalidRows > 0) {
                    throw new IllegalStateException("list-active-villages RPC returned " + invalidRows
                        + " invalid row(s); keeping the last known-good snapshot");
                }

                villages = Map.copyOf(next);
            })
            .exceptionally(error -> {
                logger.warning("[Villages] refresh failed: " + error.getMessage());
                return null;
            })
            .whenComplete((ignored, error) -> refreshInFlight.set(false));
    }

    public Village at(Location location) {
        Village found = null;
        for (Village village : villages.values()) {
            if (village.contains(location)) {
                if (found == null || village.radius() < found.radius()) found = village;
            }
        }
        return found;
    }

    public List<Village> forClan(String clanId) {
        try {
            UUID id = UUID.fromString(clanId);
            return villages.values().stream().filter(v -> v.clanId().equals(id)).sorted(Comparator.comparing(Village::name)).toList();
        } catch (IllegalArgumentException e) {
            return List.of();
        }
    }

    public Village byName(String clanId, String name) {
        return forClan(clanId).stream().filter(v -> v.name().equalsIgnoreCase(name)).findFirst().orElse(null);
    }

    public JsonArray rawSnapshot() {
        JsonArray result = new JsonArray();
        for (Village v : villages.values()) {
            JsonObject row = new JsonObject();
            row.addProperty("id", v.id().toString());
            row.addProperty("clan_id", v.clanId().toString());
            row.addProperty("name", v.name());
            row.addProperty("world", v.world());
            row.addProperty("center_x", v.centerX());
            row.addProperty("center_y", v.centerY());
            row.addProperty("center_z", v.centerZ());
            row.addProperty("radius", v.radius());
            result.add(row);
        }
        return result;
    }
}
