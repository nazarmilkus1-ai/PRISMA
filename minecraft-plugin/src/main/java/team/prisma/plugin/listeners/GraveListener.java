package team.prisma.plugin.listeners;

import org.bukkit.Bukkit;
import org.bukkit.Chunk;
import org.bukkit.Location;
import org.bukkit.NamespacedKey;
import org.bukkit.World;
import org.bukkit.entity.Entity;
import org.bukkit.entity.EntityType;
import org.bukkit.entity.Player;
import org.bukkit.entity.TextDisplay;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.entity.PlayerDeathEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.world.ChunkLoadEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.persistence.PersistentDataType;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.graves.GraveStore;
import team.prisma.plugin.graves.GraveStore.Grave;
import team.prisma.plugin.graves.GraveStore.Operation;
import team.prisma.plugin.graves.GraveStore.Result;
import team.prisma.plugin.modules.ModuleStateCache;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.logging.Level;

/**
 * Death markers and idempotent delivery. A CLAIMING record plus claim-id item tags
 * let the plugin resume safely after a restart rather than issuing the same grave twice.
 */
public final class GraveListener implements Listener {
    private static final double MARKER_Y_OFFSET = 1.0d;
    private static final int CLAIM_ITEM_TAG_VERSION = 1;

    private final JavaPlugin plugin;
    private final GraveStore store;
    private final ModuleStateCache modules;
    private final NamespacedKey markerKey;
    private final NamespacedKey claimItemKey;
    private final NamespacedKey claimVersionKey;

    public GraveListener(JavaPlugin plugin, GraveStore store, ModuleStateCache modules) {
        this.plugin = plugin;
        this.store = store;
        this.modules = modules;
        this.markerKey = new NamespacedKey(plugin, "grave-id");
        this.claimItemKey = new NamespacedKey(plugin, "grave-claim-id");
        this.claimVersionKey = new NamespacedKey(plugin, "grave-claim-version");
    }

    public void initialize() {
        if (!store.isStorageHealthy()) return;
        long now = System.currentTimeMillis();
        store.pruneExpired(now);
        if (!store.isStorageHealthy()) return;
        cleanupLoadedMarkers(now);
        for (Grave grave : store.allRecords()) {
            if (grave.state() == GraveStore.State.PENDING && !grave.expired(now)) {
                scheduleExpiry(grave);
            } else {
                removeMarker(grave);
            }
        }
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onDeath(PlayerDeathEvent event) {
        if (!modules.isEnabled("minecraft-graves") || event.getKeepInventory()) return;
        if (!store.isStorageHealthy()) {
            plugin.getLogger().warning("[Graves] Хранилище недоступно; обычные дропы смерти не изменены.");
            return;
        }

        Player player = event.getEntity();
        List<ItemStack> drops = event.getDrops().stream()
            .filter(item -> item != null && !item.getType().isAir() && item.getAmount() > 0)
            .map(ItemStack::clone)
            .map(this::removeClaimTag)
            .toList();
        if (drops.isEmpty()) return;

        long now = System.currentTimeMillis();
        Operation result = store.create(player.getUniqueId(), player.getName(),
            player.getLocation().clone(), drops, now);
        if (result.result() != Result.SAVED || result.grave() == null) {
            plugin.getLogger().warning("[Graves] Могила для " + player.getName()
                + " не сохранена (" + result.result() + "); обычные дропы не удалены.");
            player.sendMessage("§cМогилу сохранить не удалось. Предметы остались обычными дропами.");
            return;
        }

        // The grave file is durably written before vanilla drops are suppressed.
        event.getDrops().clear();
        Grave grave = result.grave();
        spawnMarker(grave);
        scheduleExpiry(grave);
        player.sendMessage("§6Предметы сохранены в могиле §e#" + grave.id()
            + "§6. Подойдите к метке и используйте §e/grave claim " + grave.id()
            + "§6 в течение 15 минут.");
    }

    @EventHandler(priority = EventPriority.NORMAL)
    public void onJoin(PlayerJoinEvent event) {
        if (!store.isStorageHealthy()) return;
        Player player = event.getPlayer();
        for (Grave grave : store.claimingFor(player.getUniqueId())) {
            if (hasClaimTag(player, grave.claimId())) {
                completeDeliveredClaim(player, grave);
            } else {
                deliverClaim(player, grave, false);
            }
            if (!store.isStorageHealthy()) return;
        }
        cleanOrphanClaimTags(player);
    }

    @EventHandler
    public void onChunkLoad(ChunkLoadEvent event) {
        if (!store.isStorageHealthy()) return;
        cleanupMarkers(event.getChunk(), System.currentTimeMillis());
    }

    public void deliverClaim(Player player, Grave grave, boolean notify) {
        if (!store.isStorageHealthy()) {
            player.sendMessage("§cХранилище могил недоступно; предметы не выдавались.");
            return;
        }
        if (hasClaimTag(player, grave.claimId())) {
            completeDeliveredClaim(player, grave);
            return;
        }

        List<ItemStack> taggedItems;
        try {
            taggedItems = grave.items().stream()
                .map(item -> addClaimTag(item, grave.claimId()))
                .toList();
        } catch (RuntimeException error) {
            plugin.getLogger().log(Level.SEVERE, "[Graves] Не удалось подготовить транзакцию " + grave.id(), error);
            if (!store.rollbackClaim(grave.id(), grave.claimId())) {
                failClosed(player, "Не удалось отменить получение могилы.");
            } else {
                player.sendMessage("§cПредметы не изменены: не удалось подготовить безопасную выдачу.");
            }
            return;
        }

        PlayerInventory inventory = player.getInventory();
        if (!canFit(inventory.getStorageContents(), taggedItems)) {
            // Once a claim was started, do not discard an expired grave if recovery needs more inventory space.
            if (System.currentTimeMillis() >= grave.expiresAtEpochMilli()) {
                player.sendMessage("§cПолучение могилы сохранено, но инвентарь заполнен. Освободите слоты и повторите §f/grave claim "
                    + grave.id() + "§c; эта уже начатая операция не истечёт.");
                return;
            }
            if (!store.rollbackClaim(grave.id(), grave.claimId())) {
                failClosed(player, "Не удалось отменить получение могилы после проверки инвентаря.");
                return;
            }
            player.sendMessage("§cВ инвентаре недостаточно места. Освободите слоты и повторите §f/grave claim "
                + grave.id() + "§c у метки.");
            return;
        }

        try {
            java.util.Map<Integer, ItemStack> leftovers = inventory.addItem(taggedItems.toArray(ItemStack[]::new));
            if (!leftovers.isEmpty()) {
                removeClaimTags(player, grave.claimId());
                player.saveData();
                if (!store.rollbackClaim(grave.id(), grave.claimId())) {
                    failClosed(player, "Не удалось безопасно отменить частичную выдачу могилы.");
                    return;
                }
                player.sendMessage("§cИнвентарь изменился во время получения. Могила сохранена; повторите попытку.");
                return;
            }
            // Save the tagged inventory before deleting the durable CLAIMING record.
            player.saveData();
        } catch (RuntimeException error) {
            plugin.getLogger().log(Level.SEVERE, "[Graves] Не удалось сохранить выдачу могилы " + grave.id(), error);
            failClosed(player, "Не удалось сохранить выдачу предметов. Обратитесь к персоналу.");
            return;
        }
        completeDeliveredClaim(player, grave);
    }

    public void removeMarker(Grave grave) {
        if (grave == null) return;
        Entity recorded = grave.markerEntityId() == null ? null : Bukkit.getEntity(grave.markerEntityId());
        if (recorded instanceof TextDisplay display && markerId(display).equals(grave.id())) {
            display.remove();
        }

        World world = Bukkit.getWorld(grave.world());
        if (world == null) return;
        int chunkX = ((int) Math.floor(grave.x())) >> 4;
        int chunkZ = ((int) Math.floor(grave.z())) >> 4;
        if (!world.isChunkLoaded(chunkX, chunkZ)) return;
        removeMatchingMarkers(world.getChunkAt(chunkX, chunkZ), grave.id());
    }

    private void spawnMarker(Grave grave) {
        World world = Bukkit.getWorld(grave.world());
        if (world == null) return;
        Location markerLocation = new Location(world, grave.x(), grave.y() + MARKER_Y_OFFSET, grave.z());
        try {
            Entity raw = world.spawnEntity(markerLocation, EntityType.TEXT_DISPLAY);
            if (!(raw instanceof TextDisplay marker)) {
                raw.remove();
                return;
            }
            marker.setText("§6Могила §f#" + grave.id() + "\n§e/grave claim " + grave.id());
            marker.setBillboard(org.bukkit.entity.Display.Billboard.CENTER);
            marker.setPersistent(true);
            marker.setSeeThrough(true);
            marker.setShadowed(true);
            marker.addScoreboardTag("prisma_grave_marker");
            marker.getPersistentDataContainer().set(markerKey, PersistentDataType.STRING, grave.id());
            // Marker identity is carried by persistent entity data; no second write is needed here.
            // This keeps a valid saved grave claimable even if the disk fails after the first write.
        } catch (RuntimeException error) {
            plugin.getLogger().log(Level.WARNING, "[Graves] Не удалось создать метку могилы " + grave.id(), error);
        }
    }

    private void scheduleExpiry(Grave grave) {
        long delay = Math.max(1L, (grave.expiresAtEpochMilli() - System.currentTimeMillis()) / 50L);
        Bukkit.getScheduler().runTaskLater(plugin, () -> {
            store.pruneExpired(System.currentTimeMillis());
            if (store.isStorageHealthy()) removeMarker(grave);
        }, delay);
    }

    private void cleanupLoadedMarkers(long now) {
        for (World world : Bukkit.getWorlds()) {
            for (Chunk chunk : world.getLoadedChunks()) cleanupMarkers(chunk, now);
        }
    }

    private void cleanupMarkers(Chunk chunk, long now) {
        for (Entity entity : chunk.getEntities()) {
            if (!(entity instanceof TextDisplay display)
                || !display.getScoreboardTags().contains("prisma_grave_marker")) continue;
            String id = markerId(display);
            if (id.isBlank() || !store.hasActivePending(id, now)) display.remove();
        }
    }

    private void removeMatchingMarkers(Chunk chunk, String id) {
        for (Entity entity : chunk.getEntities()) {
            if (entity instanceof TextDisplay display && id.equals(markerId(display))) display.remove();
        }
    }

    private String markerId(TextDisplay display) {
        return display.getPersistentDataContainer().getOrDefault(markerKey, PersistentDataType.STRING, "");
    }

    private ItemStack addClaimTag(ItemStack source, String claimId) {
        ItemStack item = source.clone();
        var meta = item.getItemMeta();
        if (meta == null) throw new IllegalStateException("ItemMeta is unavailable");
        meta.getPersistentDataContainer().set(claimItemKey, PersistentDataType.STRING, claimId);
        meta.getPersistentDataContainer().set(claimVersionKey, PersistentDataType.INTEGER, CLAIM_ITEM_TAG_VERSION);
        item.setItemMeta(meta);
        return item;
    }

    private ItemStack removeClaimTag(ItemStack source) {
        ItemStack item = source.clone();
        var meta = item.getItemMeta();
        if (meta != null) {
            meta.getPersistentDataContainer().remove(claimItemKey);
            meta.getPersistentDataContainer().remove(claimVersionKey);
            item.setItemMeta(meta);
        }
        return item;
    }

    private boolean hasClaimTag(Player player, String claimId) {
        if (claimId == null || claimId.isBlank()) return false;
        for (ItemStack item : inventoryItems(player)) {
            if (claimId.equals(claimIdOf(item))) return true;
        }
        return false;
    }

    private void removeClaimTags(Player player, String claimId) {
        if (claimId == null) return;
        PlayerInventory inventory = player.getInventory();
        ItemStack[] storage = inventory.getStorageContents();
        for (int i = 0; i < storage.length; i++) {
            if (claimId.equals(claimIdOf(storage[i]))) storage[i] = removeClaimTag(storage[i]);
        }
        inventory.setStorageContents(storage);

        ItemStack[] armor = inventory.getArmorContents();
        for (int i = 0; i < armor.length; i++) {
            if (claimId.equals(claimIdOf(armor[i]))) armor[i] = removeClaimTag(armor[i]);
        }
        inventory.setArmorContents(armor);
        if (claimId.equals(claimIdOf(inventory.getItemInOffHand()))) {
            inventory.setItemInOffHand(removeClaimTag(inventory.getItemInOffHand()));
        }
        if (claimId.equals(claimIdOf(player.getItemOnCursor()))) {
            player.setItemOnCursor(removeClaimTag(player.getItemOnCursor()));
        }
    }

    private void cleanOrphanClaimTags(Player player) {
        for (ItemStack item : inventoryItems(player)) {
            String claimId = claimIdOf(item);
            if (claimId.isBlank()) continue;
            boolean transactionExists = store.allRecords().stream()
                .anyMatch(grave -> claimId.equals(grave.claimId()) && grave.state() == GraveStore.State.CLAIMING);
            if (!transactionExists) removeClaimTags(player, claimId);
        }
        player.saveData();
    }

    private String claimIdOf(ItemStack item) {
        if (item == null || item.getType().isAir() || !item.hasItemMeta()) return "";
        return item.getItemMeta().getPersistentDataContainer()
            .getOrDefault(claimItemKey, PersistentDataType.STRING, "");
    }

    private List<ItemStack> inventoryItems(Player player) {
        List<ItemStack> items = new ArrayList<>();
        PlayerInventory inventory = player.getInventory();
        Collections.addAll(items, inventory.getStorageContents());
        Collections.addAll(items, inventory.getArmorContents());
        items.add(inventory.getItemInOffHand());
        items.add(player.getItemOnCursor());
        return items;
    }

    private boolean canFit(ItemStack[] current, List<ItemStack> additions) {
        ItemStack[] simulated = new ItemStack[current.length];
        for (int i = 0; i < current.length; i++) {
            simulated[i] = current[i] == null ? null : current[i].clone();
        }
        for (ItemStack addition : additions) {
            int remaining = addition.getAmount();
            for (int i = 0; i < simulated.length && remaining > 0; i++) {
                ItemStack existing = simulated[i];
                if (existing == null || existing.getType().isAir() || !existing.isSimilar(addition)) continue;
                int max = Math.min(existing.getMaxStackSize(), addition.getMaxStackSize());
                int space = Math.max(0, max - existing.getAmount());
                int moved = Math.min(space, remaining);
                if (moved > 0) {
                    existing.setAmount(existing.getAmount() + moved);
                    remaining -= moved;
                }
            }
            for (int i = 0; i < simulated.length && remaining > 0; i++) {
                if (simulated[i] != null && !simulated[i].getType().isAir()) continue;
                int moved = Math.min(addition.getMaxStackSize(), remaining);
                ItemStack inserted = addition.clone();
                inserted.setAmount(moved);
                simulated[i] = inserted;
                remaining -= moved;
            }
            if (remaining > 0) return false;
        }
        return true;
    }

    private void completeDeliveredClaim(Player player, Grave grave) {
        if (!store.completeClaim(grave.id(), grave.claimId())) {
            failClosed(player, "Предметы выданы, но транзакцию могилы нельзя завершить. Не перемещайте эти предметы.");
            return;
        }
        removeClaimTags(player, grave.claimId());
        player.saveData();
        removeMarker(grave);
        player.sendMessage("§aМогила §e#" + grave.id() + " §aполучена. Предметы возвращены.");
    }

    private void failClosed(Player player, String reason) {
        plugin.getLogger().severe("[Graves] " + reason
            + " Игрок временно отключён, чтобы не допустить дублирования предметов.");
        player.kickPlayer("PRISMA: " + reason + " Обратитесь к персоналу.");
    }
}
