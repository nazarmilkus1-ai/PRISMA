package team.prisma.plugin.clans;

import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.block.Block;
import org.bukkit.entity.Entity;
import org.bukkit.entity.Player;
import org.bukkit.entity.Projectile;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.block.*;
import org.bukkit.event.entity.EntityChangeBlockEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.hanging.HangingBreakEvent;
import org.bukkit.event.hanging.HangingBreakByEntityEvent;
import org.bukkit.event.player.PlayerBucketEmptyEvent;
import org.bukkit.event.player.PlayerBucketFillEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerInteractEntityEvent;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.staff.StaffPermissionCache;
import team.prisma.plugin.modules.ModuleStateCache;

public final class VillageProtectionListener implements Listener {
    private final VillageManager villages;
    private final PlayerStateCache cache;
    private final StaffPermissionCache staff;
    private final ModuleStateCache modules;

    public VillageProtectionListener(VillageManager villages, PlayerStateCache cache, StaffPermissionCache staff, ModuleStateCache modules) {
        this.villages = villages;
        this.cache = cache;
        this.staff = staff;
        this.modules = modules;
    }

    private boolean allowed(Player player, Village village) {
        String clan = cache.clanOf(player.getUniqueId());
        return (clan != null && village.clanId().toString().equalsIgnoreCase(clan))
            || staff.has(player.getUniqueId(), "clan.manage");
    }

    private void deny(Player player, Village village) {
        player.sendActionBar("§cТерритория клана §f[" + village.name() + "]§c. Ви не можете тут строить.");
    }

    private boolean protectedLocation(Location location) {
        return location != null && villages.at(location) != null;
    }

    private boolean mayEdit(Player player, Location location) {
        Village village = villages.at(location);
        if (village == null || allowed(player, village)) return true;
        deny(player, village);
        return false;
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onBreak(BlockBreakEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (!mayEdit(event.getPlayer(), event.getBlock().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onPlace(BlockPlaceEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (!mayEdit(event.getPlayer(), event.getBlockPlaced().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onInteract(PlayerInteractEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (event.getClickedBlock() != null && !mayEdit(event.getPlayer(), event.getClickedBlock().getLocation())) {
            event.setCancelled(true);
        }
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onInteractEntity(PlayerInteractEntityEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (event.getRightClicked() instanceof org.bukkit.entity.ArmorStand
            && !mayEdit(event.getPlayer(), event.getRightClicked().getLocation())) {
            event.setCancelled(true);
        }
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onHangingBreak(HangingBreakEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (event instanceof HangingBreakByEntityEvent byEntity && byEntity.getRemover() instanceof Player player) {
            if (!mayEdit(player, event.getEntity().getLocation())) event.setCancelled(true);
            return;
        }
        if (protectedLocation(event.getEntity().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onEmptyBucket(PlayerBucketEmptyEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (!mayEdit(event.getPlayer(), event.getBlock().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onFillBucket(PlayerBucketFillEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (!mayEdit(event.getPlayer(), event.getBlock().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onEntityChange(EntityChangeBlockEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (protectedLocation(event.getBlock().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onBlockExplode(BlockExplodeEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        event.blockList().removeIf(block -> protectedLocation(block.getLocation()));
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onEntityExplode(EntityExplodeEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        event.blockList().removeIf(block -> protectedLocation(block.getLocation()));
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onBlockBurn(BlockBurnEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (protectedLocation(event.getBlock().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onBlockIgnite(BlockIgniteEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (protectedLocation(event.getBlock().getLocation())) event.setCancelled(true);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onBlockSpread(BlockSpreadEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (protectedLocation(event.getBlock().getLocation()) || protectedLocation(event.getSource().getLocation())) {
            event.setCancelled(true);
        }
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onPistonExtend(BlockPistonExtendEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (pistonTouchesVillage(event.getBlocks(), event.getDirection().getModX(), event.getDirection().getModY(), event.getDirection().getModZ())) {
            event.setCancelled(true);
        }
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onPistonRetract(BlockPistonRetractEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (event.getBlocks().stream().anyMatch(block -> protectedLocation(block.getLocation()))) event.setCancelled(true);
    }

    private Player attackingPlayer(Entity attacker) {
        if (attacker instanceof Player player) return player;
        if (attacker instanceof Projectile projectile && projectile.getShooter() instanceof Player shooter) return shooter;
        return null;
    }

    private boolean pistonTouchesVillage(java.util.List<Block> blocks, int dx, int dy, int dz) {
        for (Block block : blocks) {
            if (protectedLocation(block.getLocation())
                || protectedLocation(block.getRelative(dx, dy, dz).getLocation())) return true;
        }
        return false;
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onPvp(EntityDamageByEntityEvent event) {
        if (modules.hasFreshState() && !modules.isEnabled("minecraft-village-protection")) return;
        if (!(event.getEntity() instanceof Player target)) return;
        Player source = attackingPlayer(event.getDamager());
        if (source == null) return;
        Village targetVillage = villages.at(target.getLocation());
        Village sourceVillage = villages.at(source.getLocation());
        if (targetVillage != null || sourceVillage != null) event.setCancelled(true);
    }
}
