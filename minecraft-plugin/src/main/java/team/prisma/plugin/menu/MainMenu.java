package team.prisma.plugin.menu;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.format.TextDecoration;
import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.inventory.ClickType;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.InventoryHolder;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.homes.PlayerHomesStore;
import team.prisma.plugin.journey.PlayerJourneyStore;
import team.prisma.plugin.spawn.SpawnPointsStore;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The PRISMA main menu. It is a plain chest inventory, so it works the same for Java players and for
 * Bedrock players through Geyser/Floodgate (Bedrock shows it as a chest screen). Every button runs the
 * existing command as the player, so permissions, module switches, cooldowns and warm-ups stay exactly
 * the same as when the command is typed.
 */
public final class MainMenu implements Listener {
    private enum Kind { MAIN, CHECKPOINTS }

    private static final class Holder implements InventoryHolder {
        final Kind kind;
        final Map<Integer, String[]> actions = new java.util.HashMap<>();
        Inventory inventory;

        Holder(Kind kind) {
            this.kind = kind;
        }

        @Override
        public Inventory getInventory() {
            return inventory;
        }
    }

    private final JavaPlugin plugin;
    private final PlayerHomesStore homes;
    private final PlayerJourneyStore journey;
    private final SpawnPointsStore spawns;

    public MainMenu(JavaPlugin plugin, PlayerHomesStore homes, PlayerJourneyStore journey, SpawnPointsStore spawns) {
        this.plugin = plugin;
        this.homes = homes;
        this.journey = journey;
        this.spawns = spawns;
    }

    // ------------------------------------------------------------------ building

    public void open(Player player) {
        Holder holder = new Holder(Kind.MAIN);
        Inventory inventory = Bukkit.createInventory(holder, 27, Component.text("PRISMA · меню", NamedTextColor.GOLD));
        holder.inventory = inventory;
        fill(inventory, Material.BLACK_STAINED_GLASS_PANE);

        UUID id = player.getUniqueId();
        Map<Integer, PlayerHomesStore.HomePoint> myHomes = homes.list(id);
        for (int slot = 1; slot <= PlayerHomesStore.MAX_HOMES; slot++) {
            PlayerHomesStore.HomePoint home = myHomes.get(slot);
            int guiSlot = 9 + slot;
            if (home != null) {
                put(holder, inventory, guiSlot, Material.RED_BED, "Дом " + slot, NamedTextColor.GREEN, List.of(
                    where(home.x(), home.y(), home.z(), home.world()),
                    "§aЛКМ§7 — телепорт", "§eПКМ§7 — перезаписать здесь"), "home " + slot, "sethome " + slot);
            } else {
                put(holder, inventory, guiSlot, Material.GRAY_BED, "Дом " + slot + " не задан", NamedTextColor.GRAY, List.of(
                    "§aЛКМ§7 — задать на этом месте"), "sethome " + slot, "sethome " + slot);
            }
        }
        put(holder, inventory, 12, Material.COMPASS, "Спавн", NamedTextColor.AQUA,
            spawnLore(), "spawn", "spawn");
        int checkpoints = journey.checkpoints(id).size();
        put(holder, inventory, 13, Material.LODESTONE, "Контрольные точки", NamedTextColor.RED, List.of(
            "§7Сохранено: §f" + checkpoints + "§7/" + PlayerJourneyStore.MAX_CHECKPOINTS,
            "§aЛКМ§7 — список", "§eПКМ§7 — сохранить здесь"), "@checkpoints", "@checkpoint-here");
        put(holder, inventory, 14, Material.SKELETON_SKULL, "Последняя смерть", NamedTextColor.WHITE, List.of(
            "§7Показать координаты места смерти"), "lastdeath", "lastdeath");
        put(holder, inventory, 15, Material.CHEST, "Могилы", NamedTextColor.YELLOW, List.of(
            "§7Ваши могилы и как их открыть"), "grave list", "grave list");
        put(holder, inventory, 16, Material.FILLED_MAP, "Карта мира", NamedTextColor.GOLD, List.of(
            "§7Показывает только места, где вы были", "§7и ваши сохранённые точки"), "worldmap", "worldmap");
        put(holder, inventory, 20, Material.WHITE_BANNER, "Клан", NamedTextColor.LIGHT_PURPLE, List.of(
            "§7Информация о вашем клане"), "clan info", "clan");
        put(holder, inventory, 22, Material.BOOK, "Команды", NamedTextColor.GREEN, List.of(
            "§7Все команды PRISMA"), "prismacommands", "prismacommands");
        put(holder, inventory, 24, Material.KNOWLEDGE_BOOK, "Помощь", NamedTextColor.BLUE, List.of(
            "§7Правила, связь с администрацией"), "help", "help");
        player.openInventory(inventory);
    }

    private void openCheckpoints(Player player) {
        Holder holder = new Holder(Kind.CHECKPOINTS);
        Inventory inventory = Bukkit.createInventory(holder, 27, Component.text("PRISMA · контрольные точки", NamedTextColor.RED));
        holder.inventory = inventory;
        fill(inventory, Material.BLACK_STAINED_GLASS_PANE);
        Map<String, PlayerJourneyStore.Point> points = journey.checkpoints(player.getUniqueId());
        int slot = 11;
        for (Map.Entry<String, PlayerJourneyStore.Point> entry : points.entrySet()) {
            PlayerJourneyStore.Point p = entry.getValue();
            put(holder, inventory, slot++, Material.LODESTONE, entry.getKey(), NamedTextColor.RED, List.of(
                where(p.x(), p.y(), p.z(), p.world()), "§aЛКМ§7 — телепорт"), "checkpoint go " + entry.getKey(), "checkpoint go " + entry.getKey());
        }
        if (points.isEmpty()) {
            put(holder, inventory, 13, Material.BARRIER, "Точек пока нет", NamedTextColor.GRAY, List.of(
                "§7Вернитесь в меню и нажмите ПКМ", "§7на «Контрольные точки»"), "@back", "@back");
        }
        put(holder, inventory, 22, Material.ARROW, "Назад", NamedTextColor.WHITE, List.of(), "@back", "@back");
        player.openInventory(inventory);
    }

    private List<String> spawnLore() {
        SpawnPointsStore.SpawnPoint spawn = spawns.get(SpawnPointsStore.MAIN_SPAWN_ID);
        List<String> lore = new ArrayList<>();
        lore.add(spawn == null ? "§7Основной спавн ещё не задан" : "§7Основной спавн сервера");
        lore.add("§aЛКМ§7 — телепорт");
        return lore;
    }

    private static String where(double x, double y, double z, String world) {
        return "§7" + Math.round(x) + ", " + Math.round(y) + ", " + Math.round(z) + " §8(" + world + ")";
    }

    private static void fill(Inventory inventory, Material material) {
        ItemStack pane = new ItemStack(material);
        ItemMeta meta = pane.getItemMeta();
        meta.displayName(Component.text(" "));
        pane.setItemMeta(meta);
        for (int i = 0; i < inventory.getSize(); i++) inventory.setItem(i, pane);
    }

    private static void put(Holder holder, Inventory inventory, int slot, Material material, String title,
                            NamedTextColor color, List<String> lore, String leftAction, String rightAction) {
        ItemStack item = new ItemStack(material);
        ItemMeta meta = item.getItemMeta();
        meta.displayName(Component.text(title, color).decoration(TextDecoration.ITALIC, false));
        List<Component> lines = new ArrayList<>();
        for (String line : lore) lines.add(legacy(line));
        meta.lore(lines);
        item.setItemMeta(meta);
        inventory.setItem(slot, item);
        holder.actions.put(slot, new String[]{leftAction, rightAction});
    }

    private static Component legacy(String text) {
        return net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer.legacySection()
            .deserialize(text).decoration(TextDecoration.ITALIC, false);
    }

    // ------------------------------------------------------------------ clicks

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onClick(InventoryClickEvent event) {
        if (!(event.getView().getTopInventory().getHolder() instanceof Holder holder)) return;
        event.setCancelled(true); // nothing can be taken out of or put into the menu
        if (!(event.getWhoClicked() instanceof Player player)) return;
        if (event.getClickedInventory() != event.getView().getTopInventory()) return;
        String[] actions = holder.actions.get(event.getSlot());
        if (actions == null) return;
        ClickType click = event.getClick();
        String action = (click == ClickType.RIGHT || click == ClickType.SHIFT_RIGHT) ? actions[1] : actions[0];
        Bukkit.getScheduler().runTask(plugin, () -> run(player, holder, action));
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onDrag(InventoryDragEvent event) {
        if (event.getView().getTopInventory().getHolder() instanceof Holder) event.setCancelled(true);
    }

    private void run(Player player, Holder holder, String action) {
        if (!player.isOnline() || action == null) return;
        switch (action) {
            case "@checkpoints" -> openCheckpoints(player);
            case "@back" -> open(player);
            case "@checkpoint-here" -> {
                player.closeInventory();
                Map<String, PlayerJourneyStore.Point> taken = journey.checkpoints(player.getUniqueId());
                int next = 1;
                while (taken.containsKey("point" + next)) next++; // never overwrite an existing point
                player.performCommand("checkpoint set point" + next);
            }
            default -> {
                player.closeInventory();
                player.performCommand(action);
            }
        }
    }
}
