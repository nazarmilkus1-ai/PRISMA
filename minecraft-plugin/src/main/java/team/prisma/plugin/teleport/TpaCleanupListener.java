package team.prisma.plugin.teleport;

import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerQuitEvent;

public final class TpaCleanupListener implements Listener {
    private final TpaManager manager;

    public TpaCleanupListener(TpaManager manager) {
        this.manager = manager;
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        manager.clearFor(event.getPlayer().getUniqueId());
    }
}
