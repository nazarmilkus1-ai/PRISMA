package team.prisma.plugin.modules;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.bukkit.command.CommandSender;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Level;

/**
 * Cached, dependency-aware module state shared by Minecraft plugin entrypoints.
 * Network refreshes run asynchronously; command and event checks are in-memory only.
 */
public final class ModuleStateCache implements Runnable {
    private static final long STALE_AFTER_NANOS = Duration.ofSeconds(45).toNanos();
    private static final long WARNING_INTERVAL_NANOS = Duration.ofSeconds(60).toNanos();

    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final Map<String, List<String>> dependencies;
    private final AtomicLong lastWarningAt = new AtomicLong(0L);

    private volatile Map<String, Boolean> states = Map.of();
    private volatile long lastSuccessfulRefreshNanos = 0L;

    public ModuleStateCache(JavaPlugin plugin, SupabaseClient supabase) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.dependencies = loadDependencies();
    }

    public void start() {
        // First refresh runs asynchronously; feature gates remain closed until it succeeds.
        plugin.getServer().getScheduler().runTaskTimerAsynchronously(plugin, this, 0L, 20L * 15L);
    }

    @Override
    public void run() {
        try {
            JsonElement payload = supabase.postRpcJsonSync(RpcNames.GET_PUBLIC_MODULE_STATES, new JsonObject());
            if (payload == null || !payload.isJsonArray()) {
                throw new IllegalStateException("module state RPC did not return an array");
            }

            Map<String, Boolean> next = new HashMap<>();
            for (JsonElement element : payload.getAsJsonArray()) {
                if (!element.isJsonObject()) continue;
                JsonObject row = element.getAsJsonObject();
                if (!row.has("module_id") || row.get("module_id").isJsonNull()
                    || !row.has("enabled") || !row.get("enabled").isJsonPrimitive()
                    || !row.get("enabled").getAsJsonPrimitive().isBoolean()) {
                    continue;
                }
                next.put(row.get("module_id").getAsString(), row.get("enabled").getAsBoolean());
            }
            if (next.isEmpty()) {
                throw new IllegalStateException("module state RPC returned no valid rows");
            }

            states = Map.copyOf(next);
            lastSuccessfulRefreshNanos = System.nanoTime();
        } catch (Exception error) {
            warnRateLimited("Module state refresh failed; dependent Minecraft features will fail closed: "
                + error.getMessage());
        }
    }

    public boolean hasFreshState() {
        long lastSuccess = lastSuccessfulRefreshNanos;
        return lastSuccess != 0L && System.nanoTime() - lastSuccess <= STALE_AFTER_NANOS;
    }

    public boolean isEnabled(String moduleId) {
        if (dependencies.isEmpty() || !hasFreshState()) return false;
        return isEnabled(moduleId, states, new HashSet<>());
    }

    public boolean allow(CommandSender sender, String... moduleIds) {
        for (String moduleId : moduleIds) {
            if (!isEnabled(moduleId)) {
                sender.sendMessage("§cЭта функция PRISMA временно недоступна: модуль «"
                    + moduleId + "» отключён или состояние не подтверждено.");
                return false;
            }
        }
        return true;
    }

    private boolean isEnabled(String moduleId, Map<String, Boolean> snapshot, Set<String> visiting) {
        List<String> required = dependencies.get(moduleId);
        if (required == null || !Boolean.TRUE.equals(snapshot.get(moduleId)) || !visiting.add(moduleId)) {
            return false;
        }
        for (String dependency : required) {
            if (!isEnabled(dependency, snapshot, visiting)) {
                visiting.remove(moduleId);
                return false;
            }
        }
        visiting.remove(moduleId);
        return true;
    }

    private Map<String, List<String>> loadDependencies() {
        try (InputStream stream = plugin.getResource("prisma/registry.json")) {
            if (stream == null) throw new IllegalStateException("missing prisma/registry.json in plugin JAR");
            try (InputStreamReader reader = new InputStreamReader(stream, StandardCharsets.UTF_8)) {
                JsonObject registry = JsonParser.parseReader(reader).getAsJsonObject();
                JsonArray modules = registry.getAsJsonArray("modules");
                Map<String, List<String>> result = new HashMap<>();
                for (JsonElement element : modules) {
                    if (!element.isJsonObject()) continue;
                    JsonObject module = element.getAsJsonObject();
                    if (!module.has("id") || module.get("id").isJsonNull()) continue;
                    String id = module.get("id").getAsString();
                    List<String> required = new ArrayList<>();
                    if (module.has("dependsOn") && module.get("dependsOn").isJsonArray()) {
                        for (JsonElement dependency : module.getAsJsonArray("dependsOn")) {
                            if (dependency.isJsonPrimitive()) required.add(dependency.getAsString());
                        }
                    }
                    result.put(id, List.copyOf(required));
                }
                if (result.isEmpty()) throw new IllegalStateException("module registry contains no modules");
                return Map.copyOf(result);
            }
        } catch (Exception error) {
            plugin.getLogger().log(Level.SEVERE,
                "Unable to load module registry; all module-gated features will remain disabled", error);
            return Map.of();
        }
    }

    private void warnRateLimited(String message) {
        long now = System.nanoTime();
        long previous = lastWarningAt.get();
        if (now - previous >= WARNING_INTERVAL_NANOS && lastWarningAt.compareAndSet(previous, now)) {
            plugin.getLogger().warning(message);
        }
    }
}
