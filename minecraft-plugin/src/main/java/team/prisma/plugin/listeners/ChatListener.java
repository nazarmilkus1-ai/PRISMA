package team.prisma.plugin.listeners;

import com.google.gson.JsonObject;
import io.papermc.paper.event.player.AsyncChatEvent;
import net.kyori.adventure.text.serializer.plain.PlainTextComponentSerializer;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.modules.ModuleStateCache;

import java.util.UUID;
import java.util.logging.Logger;

/**
 * Enforces cached chat mutes on the chat event and captures Bukkit-owned player
 * state on the main thread before asynchronously sending durable chat RPCs.
 */
public final class ChatListener implements Listener {
    private static final Logger LOG = Logger.getLogger("PrismaPlugin");

    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;

    public ChatListener(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache, ModuleStateCache modules) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.modules = modules;
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void enforceMute(AsyncChatEvent event) {
        UUID playerId = event.getPlayer().getUniqueId();
        if (!cache.isMuted(playerId)) return;

        event.setCancelled(true);
        try {
            Bukkit.getScheduler().runTask(plugin, () -> {
                Player player = Bukkit.getPlayer(playerId);
                if (player != null && player.isOnline()) {
                    player.sendMessage("§cВы в муте и не можете писать в чат.");
                }
            });
        } catch (RuntimeException schedulingError) {
            LOG.warning("[Chat] Could not notify muted player (" + schedulingError.getClass().getSimpleName() + ")");
        }
    }

    /**
     * Observe only accepted chat messages. AsyncChatEvent may execute off-thread,
     * so world/name reads and all event-to-RPC scheduling happen after returning to
     * the Bukkit main thread.
     */
    @EventHandler(priority = EventPriority.MONITOR, ignoreCancelled = true)
    public void recordAndBridge(AsyncChatEvent event) {
        UUID playerId = event.getPlayer().getUniqueId();
        if (cache.isMuted(playerId)
            || !modules.isEnabled("minecraft")
            || !modules.isEnabled("chat")) {
            return;
        }

        String userId = cache.userIdOf(playerId);
        if (userId == null || userId.isBlank()) return;
        String message = PlainTextComponentSerializer.plainText().serialize(event.message()).trim();
        if (message.isBlank()) return;

        try {
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (!plugin.isEnabled()
                    || !modules.isEnabled("minecraft")
                    || !modules.isEnabled("chat")
                    || cache.isMuted(playerId)
                    || !userId.equals(cache.userIdOf(playerId))) {
                    return;
                }

                Player player = Bukkit.getPlayer(playerId);
                if (player == null || !player.isOnline()) return;

                // Snapshot Bukkit-owned values while on the primary server thread.
                String nickname = player.getName();
                String world = player.getWorld().getName();

                JsonObject record = new JsonObject();
                record.addProperty("p_user_id", userId);
                record.addProperty("p_message", message.length() > 2000 ? message.substring(0, 2000) : message);
                record.addProperty("p_world", world);
                record.addProperty("p_nickname", nickname);
                supabase.postRpcAsync(RpcNames.RECORD_CHAT_MESSAGE, record)
                    .exceptionally(error -> {
                        LOG.warning("[Chat] message record failed (" + error.getClass().getSimpleName() + ")");
                        return null;
                    });

                if (!modules.isEnabled("minecraft-chat-bridge")) return;

                String bridgeMessage = message.length() > 500 ? message.substring(0, 500) : message;
                JsonObject bridge = new JsonObject();
                bridge.addProperty("p_user_id", userId);
                bridge.addProperty("p_minecraft_uuid", playerId.toString());
                bridge.addProperty("p_nickname", nickname);
                bridge.addProperty("p_world", world);
                bridge.addProperty("p_message", bridgeMessage);
                supabase.postRpcAsync(RpcNames.MC_BRIDGE_ENQUEUE_FROM_MINECRAFT, bridge)
                    .thenAccept(result -> {
                        if (result == null || !result.has("success") || result.get("success").isJsonNull()
                            || !result.get("success").getAsBoolean()) {
                            LOG.fine("[ChatBridge] Message was not queued for " + nickname);
                        }
                    })
                    .exceptionally(error -> {
                        LOG.warning("[ChatBridge] Minecraft enqueue failed (" + error.getClass().getSimpleName() + ")");
                        return null;
                    });
            });
        } catch (RuntimeException schedulingError) {
            LOG.warning("[ChatBridge] Could not queue chat snapshot (" + schedulingError.getClass().getSimpleName() + ")");
        }
    }
}
