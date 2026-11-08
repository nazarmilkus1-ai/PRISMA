package team.prisma.plugin.tasks;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.modules.ModuleStateCache;

import java.lang.management.ManagementFactory;
import java.util.logging.Logger;

/** Publishes server health and liveness to the PRISMA control plane. */
public final class ServerMetricsTask implements Runnable {
    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final ModuleStateCache modules;
    private final Logger logger;
    private final long startedAt = ManagementFactory.getRuntimeMXBean().getStartTime();

    public ServerMetricsTask(JavaPlugin plugin, SupabaseClient supabase, ModuleStateCache modules, Logger logger) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.modules = modules;
        this.logger = logger;
    }

    @Override
    public void run() {
        if (!modules.isEnabled("analytics")) return;
        String serverName = plugin.getConfig().getString("server-name", "primary");
        JsonObject body = new JsonObject();
        body.addProperty("p_node_id", serverName);
        body.addProperty("p_display_name", serverName);
        body.addProperty("p_version", Bukkit.getVersion());
        body.addProperty("p_online_players", Bukkit.getOnlinePlayers().size());
        body.addProperty("p_max_players", Bukkit.getMaxPlayers());
        body.addProperty("p_tps", currentTps());
        body.addProperty("p_memory_used_mb", (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()) / (1024L * 1024L));
        body.addProperty("p_memory_max_mb", Runtime.getRuntime().maxMemory() / (1024L * 1024L));
        body.addProperty("p_uptime_seconds", Math.max(0, (System.currentTimeMillis() - startedAt) / 1000L));
        if (!Bukkit.getWorlds().isEmpty()) body.addProperty("p_world", Bukkit.getWorlds().get(0).getName());

        JsonArray names = new JsonArray();
        Bukkit.getOnlinePlayers().forEach(player -> names.add(player.getName()));
        body.add("p_metadata", new JsonObject());

        supabase.postRpcAsync(RpcNames.UPSERT_SERVER_HEARTBEAT, body).thenRun(() -> {
            JsonObject playersBody = new JsonObject();
            playersBody.add("p_nicknames", names);
            supabase.postRpcAsync(RpcNames.TOUCH_ONLINE_PLAYERS, playersBody).exceptionally(error -> {
                logger.warning("[Players] heartbeat failed: " + error.getMessage());
                return null;
            });
        }).exceptionally(error -> {
            logger.warning("[Metrics] heartbeat failed: " + error.getMessage());
            return null;
        });
    }

    private static double currentTps() {
        try {
            double value = Bukkit.getServer().getTPS()[0];
            return Math.round(Math.min(20.0, Math.max(0.0, value)) * 100.0) / 100.0;
        } catch (Exception ignored) {
            return 20.0;
        }
    }
}
