package team.prisma.plugin.tasks;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.kyori.adventure.text.Component;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.plugin.Plugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.modules.ModuleStateCache;

import java.time.Instant;
import java.util.logging.Logger;

/**
 * Polls trusted mc_* Supabase RPCs for unapplied moderation actions
 * and applies the in-game subset.
 */
public final class ModerationPollTask implements Runnable {

    private final Plugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;
    private final Logger log;

    public ModerationPollTask(Plugin plugin, SupabaseClient supabase, PlayerStateCache cache, ModuleStateCache modules, Logger log) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.modules = modules;
        this.log = log;
    }

    @Override
    public void run() {
        if (!modules.isEnabled("minecraft") || !modules.isEnabled("moderation")) return;
        try {
            JsonObject body = new JsonObject();
            body.addProperty("p_limit", 100);

            JsonObject response = supabase.postRpcSync(RpcNames.CLAIM_PENDING_MODERATION, body);
            JsonArray pending = response.has("data") && response.get("data").isJsonArray()
                ? response.getAsJsonArray("data")
                : new JsonArray();

            if (pending.isEmpty()) return;

            for (var el : pending) {
                applyOne(el.getAsJsonObject());
            }
        } catch (Exception e) {
            log.warning("[ModerationPoll] failed: " + e.getMessage());
        }
    }

    private void applyOne(JsonObject action) {
        String id = action.get("id").getAsString();
        String type = action.get("type").getAsString();
        String reason = textOrDefault(action, "reason", "Модерационное действие");
        String nickname = textOrNull(action, "minecraft_nickname");

        // WARN has no live Minecraft effect, and whitelist state is read from
        // the canonical users row during AsyncPlayerPreLoginEvent.
        if ("WARN".equals(type) || "WHITELIST".equals(type) || "UNWHITELIST".equals(type)
            || "UNBAN".equals(type)) {
            markAppliedAsync(id);
            return;
        }

        if (nickname == null || nickname.isBlank()) {
            markAppliedAsync(id);
            return;
        }

        Bukkit.getScheduler().runTask(plugin, () -> {
            Player player = Bukkit.getPlayerExact(nickname);

            switch (type) {
                case "KICK" -> {
                    if (player != null && player.isOnline()) {
                        player.kick(Component.text("Вы исключены с сервера.\n" + reason));
                    }
                }
                case "BAN" -> {
                    if (player != null && player.isOnline()) {
                        player.kick(Component.text("Вы забанены на сервере.\n" + reason));
                    }
                }
                case "MUTE" -> {
                    Integer minutes = action.has("duration_minutes") && !action.get("duration_minutes").isJsonNull()
                        ? action.get("duration_minutes").getAsInt() : null;
                    Instant until = action.has("expires_at") && !action.get("expires_at").isJsonNull()
                        ? Instant.parse(action.get("expires_at").getAsString())
                        : (minutes != null ? Instant.now().plusSeconds(minutes * 60L) : null);
                    if (player != null) cache.setMuted(player.getUniqueId(), until);
                    if (player != null && player.isOnline()) {
                        player.sendMessage(Component.text("Вы получили мут. " + reason));
                    }
                }
                case "UNMUTE" -> {
                    if (player != null) {
                        cache.unmute(player.getUniqueId());
                        if (player.isOnline()) player.sendMessage(Component.text("С вас снят мут."));
                    }
                }
                default -> log.warning("[ModerationPoll] unknown type " + type + " for log " + id);
            }

            markAppliedAsync(id);
        });
    }

    private void markAppliedAsync(String moderationLogId) {
        JsonObject body = new JsonObject();
        body.addProperty("p_log_id", moderationLogId);
        supabase.postRpcAsync(RpcNames.MARK_MODERATION_APPLIED, body).exceptionally(error -> {
            log.warning("[ModerationPoll] failed to mark " + moderationLogId + ": " + error.getMessage());
            return null;
        });
    }

    private static String textOrNull(JsonObject obj, String key) {
        if (!obj.has(key) || obj.get(key).isJsonNull()) return null;
        return obj.get(key).getAsString();
    }

    private static String textOrDefault(JsonObject obj, String key, String fallback) {
        String value = textOrNull(obj, key);
        return value == null || value.isBlank() ? fallback : value;
    }
}