package team.prisma.plugin.listeners;

import com.google.gson.JsonObject;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerCommandPreprocessEvent;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.auth.MinecraftAuthService;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.modules.ModuleStateCache;

public final class CommandListener implements Listener {
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;

    public CommandListener(SupabaseClient supabase, PlayerStateCache cache, ModuleStateCache modules) {
        this.supabase = supabase;
        this.cache = cache;
        this.modules = modules;
    }

    @EventHandler(ignoreCancelled = true)
    public void onCommand(PlayerCommandPreprocessEvent event) {
        if (!modules.isEnabled("analytics")) return;
        Player player = event.getPlayer();
        String userId = cache.userIdOf(player.getUniqueId());
        if (userId == null) return;

        String raw = event.getMessage();
        if (MinecraftAuthService.isAuthenticationCommand(raw)) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_event_type", "COMMAND");
        body.addProperty("p_nickname", player.getName());
        body.addProperty("p_command", raw.length() > 512 ? raw.substring(0, 512) : raw);
        body.addProperty("p_world", player.getWorld().getName());
        supabase.postRpcAsync(RpcNames.RECORD_MINECRAFT_EVENT, body)
            .exceptionally(error -> {
                java.util.logging.Logger.getLogger("PrismaPlugin")
                    .warning("[Events] COMMAND record failed for " + player.getName() + ": " + error.getMessage());
                return null;
            });
    }
}