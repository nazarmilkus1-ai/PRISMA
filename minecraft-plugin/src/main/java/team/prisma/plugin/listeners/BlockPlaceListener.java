package team.prisma.plugin.listeners;

import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDeathEvent;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.modules.ModuleStateCache;

public final class BlockPlaceListener implements Listener {
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;

    public BlockPlaceListener(PlayerStateCache cache, ModuleStateCache modules) {
        this.cache = cache;
        this.modules = modules;
    }

    @EventHandler(priority = EventPriority.MONITOR, ignoreCancelled = true)
    public void onBlockPlace(BlockPlaceEvent event) {
        if (!modules.isEnabled("analytics")) return;
        cache.incrementBlocksPlaced(event.getPlayer().getUniqueId());
    }

    @EventHandler(priority = EventPriority.MONITOR, ignoreCancelled = true)
    public void onBlockBreak(BlockBreakEvent event) {
        if (!modules.isEnabled("analytics")) return;
        cache.incrementBlocksBroken(event.getPlayer().getUniqueId());
    }

    @EventHandler(priority = EventPriority.MONITOR, ignoreCancelled = true)
    public void onMobDeath(EntityDeathEvent event) {
        if (!modules.isEnabled("analytics")) return;
        if (event.getEntity() instanceof Player) return;
        Player killer = event.getEntity().getKiller();
        if (killer == null) return;
        cache.incrementMobsKilled(killer.getUniqueId());
    }
}
