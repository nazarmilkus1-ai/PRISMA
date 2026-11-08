package team.prisma.plugin.tasks;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.Bukkit;
import org.bukkit.plugin.Plugin;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.modules.ModuleStateCache;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;

/**
 * Polls Telegram-originated messages and relays them to Minecraft using a
 * leased Supabase queue. Bukkit world/player APIs are only touched on main thread.
 */
public final class MinecraftChatBridgeTask implements Runnable {
    private static final long RECENT_DELIVERY_TTL_MILLIS = 15 * 60 * 1000L;

    private final Plugin plugin;
    private final SupabaseClient supabase;
    private final ModuleStateCache modules;
    private final AtomicBoolean pollInFlight = new AtomicBoolean(false);
    private final Map<String, Long> deliveredThisSession = new ConcurrentHashMap<>();

    public MinecraftChatBridgeTask(Plugin plugin, SupabaseClient supabase, ModuleStateCache modules) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.modules = modules;
    }

    @Override
    public void run() {
        if (!modules.isEnabled("minecraft-chat-bridge")) return;
        if (!pollInFlight.compareAndSet(false, true)) return;

        pruneRecentIds();
        JsonObject request = new JsonObject();
        request.addProperty("p_limit", 25);
        try {
            supabase.postRpcAsync(RpcNames.MC_BRIDGE_CLAIM_FOR_MINECRAFT, request)
                .whenComplete((response, error) -> {
                    try {
                        if (error != null) {
                            plugin.getLogger().warning("[ChatBridge] Telegram queue claim failed: " + error.getClass().getSimpleName());
                            return;
                        }

                        JsonArray pending = response != null && response.has("data")
                            && response.get("data").isJsonArray()
                            ? response.getAsJsonArray("data") : new JsonArray();
                        for (JsonElement element : pending) {
                            if (!element.isJsonObject()) continue;
                            try {
                                deliver(element.getAsJsonObject());
                            } catch (RuntimeException deliveryError) {
                                plugin.getLogger().warning("[ChatBridge] Could not schedule Telegram message: "
                                    + deliveryError.getClass().getSimpleName());
                            }
                        }
                    } finally {
                        pollInFlight.set(false);
                    }
                });
        } catch (RuntimeException error) {
            plugin.getLogger().log(Level.WARNING, "[ChatBridge] Telegram queue poll could not start", error);
            pollInFlight.set(false);
        }
    }

    private void deliver(JsonObject row) {
        String id = stringField(row, "id");
        String leaseToken = stringField(row, "lease_token");
        if (id == null || id.isBlank() || leaseToken == null || leaseToken.isBlank()) {
            plugin.getLogger().warning("[ChatBridge] Claimed Telegram message has no ID or lease token");
            return;
        }
        if (deliveredThisSession.containsKey(id)) {
            finish(id, leaseToken, "DELIVERED", null, 5);
            return;
        }
        String sender = safeText(stringField(row, "telegram_sender_name"), 48);
        String message = safeText(stringField(row, "message"), 500);
        if (sender.isBlank() || message.isBlank()) {
            finish(id, leaseToken, "FAILED", "INVALID_QUEUE_PAYLOAD", 5);
            return;
        }

        try {
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (!plugin.isEnabled()) {
                    finish(id, leaseToken, "RETRY", "PLUGIN_DISABLED", 10);
                    return;
                }
                if (!modules.isEnabled("minecraft-chat-bridge")) {
                    finish(id, leaseToken, "RETRY", "CHAT_BRIDGE_DISABLED", 10);
                    return;
                }

                long now = System.currentTimeMillis();
                deliveredThisSession.put(id, now);
                Component line = Component.text("[Telegram] ", NamedTextColor.AQUA)
                    .append(Component.text(sender, NamedTextColor.GOLD))
                    .append(Component.text(": ", NamedTextColor.GRAY))
                    .append(Component.text(message, NamedTextColor.WHITE));
                try {
                    Bukkit.broadcast(line);
                    finish(id, leaseToken, "DELIVERED", null, 5);
                } catch (RuntimeException broadcastError) {
                    deliveredThisSession.remove(id);
                    finish(id, leaseToken, "RETRY", broadcastError.getClass().getSimpleName(), 10);
                }
            });
        } catch (RuntimeException scheduleError) {
            finish(id, leaseToken, "RETRY", scheduleError.getClass().getSimpleName(), 10);
        }
    }

    private void finish(String id, String leaseToken, String status, String error, int retrySeconds) {
        JsonObject body = new JsonObject();
        body.addProperty("p_message_id", id);
        body.addProperty("p_lease_token", leaseToken);
        body.addProperty("p_status", status);
        if (error != null) body.addProperty("p_error", error);
        body.addProperty("p_retry_after_seconds", retrySeconds);
        try {
            supabase.postRpcAsync(RpcNames.MC_BRIDGE_FINISH_MESSAGE, body)
                .exceptionally(failure -> {
                    plugin.getLogger().warning("[ChatBridge] Message finalization failed (" + id + "): "
                        + failure.getClass().getSimpleName());
                    return null;
                });
        } catch (RuntimeException failure) {
            plugin.getLogger().warning("[ChatBridge] Message finalization could not start (" + id + "): "
                + failure.getClass().getSimpleName());
        }
    }

    private void pruneRecentIds() {
        long cutoff = System.currentTimeMillis() - RECENT_DELIVERY_TTL_MILLIS;
        deliveredThisSession.entrySet().removeIf(entry -> entry.getValue() < cutoff);
        if (deliveredThisSession.size() > 2_000) {
            deliveredThisSession.entrySet().stream()
                .sorted(Map.Entry.comparingByValue())
                .limit(deliveredThisSession.size() - 1_000L)
                .forEach(entry -> deliveredThisSession.remove(entry.getKey(), entry.getValue()));
        }
    }

    private static String stringField(JsonObject object, String key) {
        return object.has(key) && !object.get(key).isJsonNull() ? object.get(key).getAsString() : null;
    }

    private static String safeText(String value, int maxLength) {
        if (value == null) return "";
        String normalized = value.replace('§', ' ').replaceAll("[\\p{Cntrl}]", " ")
            .replaceAll("\\s+", " ").trim();
        return normalized.length() <= maxLength ? normalized : normalized.substring(0, maxLength - 1) + "…";
    }
}
