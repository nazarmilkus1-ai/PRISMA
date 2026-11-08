package team.prisma.plugin.maze;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.World;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.entity.Creature;
import org.bukkit.entity.Entity;
import org.bukkit.entity.EntityType;
import org.bukkit.entity.LivingEntity;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.EventPriority;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.entity.EntityDeathEvent;
import org.bukkit.event.entity.EntityTargetLivingEntityEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.persistence.PersistentDataType;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.modules.ModuleStateCache;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Configurable first layer of the Maze Runner mode.
 *
 * Coordinates are never hard-coded: an admin stands at the centre of the imported Glade
 * and runs /maze setglade after the map world has been loaded.
 */
public final class MazeRunnerController implements Listener, CommandExecutor, Runnable {
    private static final int DEFAULT_GLADE_HALF_SIZE = 100;
    private static final int DEFAULT_MAZE_RADIUS = 1_500;
    private static final int DEFAULT_MAX_GRIEVERS = 8;
    private static final int MIN_SPAWN_DISTANCE = 18;
    private static final int MAX_SPAWN_DISTANCE = 32;

    private final JavaPlugin plugin;
    private final ModuleStateCache modules;
    private final File settingsFile;
    private final NamespacedKey grieverKey;
    private YamlConfiguration settings;
    // Force one cleanup pass after startup if the mode is disabled in the panel.
    private boolean previouslyActive = true;

    public MazeRunnerController(JavaPlugin plugin, ModuleStateCache modules) {
        this.plugin = plugin;
        this.modules = modules;
        this.settingsFile = new File(plugin.getDataFolder(), "maze-runner.yml");
        this.grieverKey = new NamespacedKey(plugin, "maze-griever");
        loadSettings();
    }

    private void loadSettings() {
        if (!plugin.getDataFolder().exists() && !plugin.getDataFolder().mkdirs()) {
            plugin.getLogger().warning("[MazeRunner] Could not create plugin data directory");
        }
        settings = YamlConfiguration.loadConfiguration(settingsFile);
        if (!settings.isSet("run-enabled")) settings.set("run-enabled", false);
        if (!settings.isSet("glade.half-size")) settings.set("glade.half-size", DEFAULT_GLADE_HALF_SIZE);
        if (!settings.isSet("maze.radius")) settings.set("maze.radius", DEFAULT_MAZE_RADIUS);
        if (!settings.isSet("grievers.maximum")) settings.set("grievers.maximum", DEFAULT_MAX_GRIEVERS);
        if (!settings.isSet("grievers.enabled")) settings.set("grievers.enabled", true);
        saveSettings();
    }

    private boolean saveSettings() {
        try {
            settings.save(settingsFile);
            return true;
        } catch (IOException error) {
            plugin.getLogger().severe("[MazeRunner] Could not save maze-runner.yml: " + error.getMessage());
            return false;
        }
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!sender.hasPermission("prisma.command.spawnmanage")) {
            sender.sendMessage("§cКоманда Maze Runner доступна только персоналу.");
            return true;
        }

        String action = args.length == 0 ? "status" : args[0].toLowerCase(Locale.ROOT);
        switch (action) {
            case "status" -> showStatus(sender);
            case "setglade", "glade" -> setGlade(sender);
            case "gladesize" -> setGladeSize(sender, args);
            case "maze-radius" -> setMazeRadius(sender, args);
            case "start" -> start(sender);
            case "stop" -> stop(sender);
            case "clear" -> sender.sendMessage("§7Удалено Гриверов: §f" + removeManagedGrievers());
            default -> usage(sender);
        }
        return true;
    }

    private void showStatus(CommandSender sender) {
        String state;
        if (!modules.hasFreshState()) state = "§eсостояние панели ещё не подтверждено";
        else state = modules.isEnabled("minecraft-maze-runner") ? "§aпереключатель включён" : "§cпереключатель выключен";

        sender.sendMessage("§6§lMAZE RUNNER §7— " + state);
        sender.sendMessage("§7Раунд: " + (settings.getBoolean("run-enabled", false) ? "§aзапущен" : "§cостановлен"));
        if (isGladeConfigured()) {
            sender.sendMessage("§7Мир: §f" + gladeWorldName()
                + " §7| Центр: §f" + settings.getInt("glade.center-x") + ", "
                + settings.getInt("glade.center-z")
                + " §7| Полуразмер Глейда: §f" + gladeHalfSize());
        } else {
            sender.sendMessage("§eЦентр Глейда не настроен. Встаньте в центре поляны и выполните §f/maze setglade");
        }
        sender.sendMessage("§7Радиус лабиринта: §f" + mazeRadius()
            + " §7| Максимум управляемых Гриверов: §f" + maxGrievers());
        sender.sendMessage("§7Запуск/спавн также требует включённого модуля в панели §f/admin/dashboard/modules");
    }

    private void setGlade(CommandSender sender) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("§c/maze setglade нужно выполнить игроком, стоя в центре Глейда.");
            return;
        }
        Location location = player.getLocation();
        settings.set("glade.world", location.getWorld().getName());
        settings.set("glade.center-x", location.getBlockX());
        settings.set("glade.center-z", location.getBlockZ());
        if (saveSettings()) {
            sender.sendMessage("§aЦентр Глейда сохранён: §f" + location.getWorld().getName()
                + " §7(" + location.getBlockX() + ", " + location.getBlockZ() + ")"
                + "§a. По умолчанию безопасная зона — 200×200 блоков.");
        } else {
            sender.sendMessage("§cНе удалось сохранить центр Глейда; проверьте права на папку плагина.");
        }
    }

    private void setGladeSize(CommandSender sender, String[] args) {
        if (args.length != 2) {
            sender.sendMessage("§7Использование: §f/maze gladesize <50–250>");
            return;
        }
        Integer value = parseInteger(args[1]);
        if (value == null || value < 50 || value > 250) {
            sender.sendMessage("§cРазмер должен быть числом от 50 до 250 блоков от центра по каждой стороне.");
            return;
        }
        settings.set("glade.half-size", value);
        if (saveSettings()) sender.sendMessage("§aПолуразмер Глейда установлен: §f" + value + "§a. Зона будет примерно " + (value * 2) + "×" + (value * 2) + ".");
        else sender.sendMessage("§cНе удалось сохранить настройки режима.");
    }

    private void setMazeRadius(CommandSender sender, String[] args) {
        if (args.length != 2) {
            sender.sendMessage("§7Использование: §f/maze maze-radius <250–5000>");
            return;
        }
        Integer value = parseInteger(args[1]);
        if (value == null || value < 250 || value > 5_000) {
            sender.sendMessage("§cРадиус лабиринта должен быть числом от 250 до 5000 блоков.");
            return;
        }
        settings.set("maze.radius", value);
        if (saveSettings()) sender.sendMessage("§aРадиус игровой зоны установлен: §f" + value + "§a блоков.");
        else sender.sendMessage("§cНе удалось сохранить настройки режима.");
    }

    private void start(CommandSender sender) {
        if (!modules.hasFreshState()) {
            sender.sendMessage("§cСостояние переключателей не подтверждено. Повторите после синхронизации панели.");
            return;
        }
        if (!modules.isEnabled("minecraft-maze-runner")) {
            sender.sendMessage("§cСначала включите «Игровой режим Maze Runner» в панели §f/admin/dashboard/modules§c.");
            return;
        }
        if (!isGladeConfigured()) {
            sender.sendMessage("§cСначала настройте центр Глейда: встаньте в центре поляны и выполните §f/maze setglade§c.");
            return;
        }
        if (Bukkit.getWorld(gladeWorldName()) == null) {
            sender.sendMessage("§cМир «" + gladeWorldName() + "» не загружен. Импортируйте/загрузите мир и повторите.");
            return;
        }

        settings.set("run-enabled", true);
        if (!saveSettings()) {
            settings.set("run-enabled", false);
            sender.sendMessage("§cРаунд не запущен: не удалось сохранить настройки.");
            return;
        }
        previouslyActive = true;
        sender.sendMessage("§aРежим Maze Runner запущен. Управляемые Гриверы будут появляться ночью за пределами Глейда.");
    }

    private void stop(CommandSender sender) {
        settings.set("run-enabled", false);
        boolean saved = saveSettings();
        int removed = removeManagedGrievers();
        previouslyActive = false;
        if (saved) sender.sendMessage("§eРежим Maze Runner остановлен. Удалено управляемых Гриверов: §f" + removed);
        else sender.sendMessage("§cРаунд остановлен в памяти, но файл настроек не сохранился. Удалено Гриверов: §f" + removed);
    }

    @Override
    public void run() {
        // Do not spawn enemies from an unknown or stale control-plane state.
        if (!modules.hasFreshState()) {
            removeManagedGrievers();
            previouslyActive = false;
            return;
        }

        boolean active = modules.isEnabled("minecraft-maze-runner")
            && settings.getBoolean("run-enabled", false)
            && isGladeConfigured();

        if (!active) {
            if (previouslyActive) removeManagedGrievers();
            previouslyActive = false;
            return;
        }
        previouslyActive = true;

        World world = Bukkit.getWorld(gladeWorldName());
        if (world == null) return;

        if (!isNight(world.getTime())) {
            removeManagedGrievers(world);
            return;
        }
        if (!settings.getBoolean("grievers.enabled", true)) return;

        spawnGrieverIfNeeded(world);
    }

    private void spawnGrieverIfNeeded(World world) {
        if (countManagedGrievers(world) >= maxGrievers()) return;

        List<Player> candidates = new ArrayList<>();
        for (Player player : world.getPlayers()) {
            if (isInsideMaze(player.getLocation()) && !isInsideGlade(player.getLocation())) {
                candidates.add(player);
            }
        }
        if (candidates.isEmpty()) return;

        ThreadLocalRandom random = ThreadLocalRandom.current();
        for (int offset = 0; offset < candidates.size(); offset++) {
            Player player = candidates.get((offset + random.nextInt(candidates.size())) % candidates.size());
            boolean hasNearbyGriever = world.getNearbyEntities(player.getLocation(), 48, 32, 48)
                .stream().anyMatch(this::isManagedGriever);
            if (hasNearbyGriever) continue;

            Location playerLocation = player.getLocation();
            for (int attempt = 0; attempt < 8; attempt++) {
                double angle = random.nextDouble(0, Math.PI * 2);
                int distance = random.nextInt(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE + 1);
                int x = playerLocation.getBlockX() + (int) Math.round(Math.cos(angle) * distance);
                int z = playerLocation.getBlockZ() + (int) Math.round(Math.sin(angle) * distance);

                if (!world.isChunkLoaded(x >> 4, z >> 4)) continue;
                Location column = new Location(world, x, playerLocation.getBlockY(), z);
                if (!isInsideMaze(column) || isInsideGlade(column)) continue;

                int surfaceY = world.getHighestBlockYAt(x, z);
                if (surfaceY <= world.getMinHeight() || surfaceY + 2 >= world.getMaxHeight()) continue;
                if (!world.getBlockAt(x, surfaceY, z).getType().isSolid()) continue;
                if (!world.getBlockAt(x, surfaceY + 1, z).getType().isAir()
                    || !world.getBlockAt(x, surfaceY + 2, z).getType().isAir()) continue;

                Location spawnLocation = new Location(world, x + 0.5, surfaceY + 1, z + 0.5);
                Entity entity = world.spawnEntity(spawnLocation, EntityType.SPIDER);
                if (!(entity instanceof LivingEntity griever)) {
                    entity.remove();
                    continue;
                }
                griever.getPersistentDataContainer().set(grieverKey, PersistentDataType.BYTE, (byte) 1);
                griever.setCustomName("§c§lГривер");
                griever.setCustomNameVisible(true);
                griever.setPersistent(true);
                player.sendMessage("§cВ темноте лабиринта слышен скрежет… Гривер близко.");
                return;
            }
        }
    }

    @EventHandler
    public void protectGladeFromManagedGrievers(EntityTargetLivingEntityEvent event) {
        if (!isManagedGriever(event.getEntity()) || !(event.getTarget() instanceof Player target)) return;
        if (!isInsideGlade(target.getLocation())) return;

        event.setCancelled(true);
        if (event.getEntity() instanceof Creature creature) creature.setTarget(null);
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void preventGrieverDamageInGlade(EntityDamageByEntityEvent event) {
        if (!(event.getEntity() instanceof Player target)
            || !isInsideGlade(target.getLocation())
            || !isManagedGriever(event.getDamager())) return;

        event.setCancelled(true);
        if (event.getDamager() instanceof Creature creature) creature.setTarget(null);
    }

    @EventHandler
    public void dropCompassForManagedGriever(EntityDeathEvent event) {
        if (!isManagedGriever(event.getEntity()) || !isGameActive()) return;
        ItemStack compass = new ItemStack(Material.COMPASS);
        ItemMeta meta = compass.getItemMeta();
        if (meta != null) {
            meta.displayName(Component.text("Компас Гривера", NamedTextColor.GOLD));
            meta.lore(List.of(Component.text("Для финального прохода лабиринта.", NamedTextColor.GRAY)));
            compass.setItemMeta(meta);
        }
        event.getDrops().add(compass);
    }

    private boolean isGameActive() {
        return modules.hasFreshState()
            && modules.isEnabled("minecraft-maze-runner")
            && settings.getBoolean("run-enabled", false);
    }

    private boolean isInsideGlade(Location location) {
        if (location == null || location.getWorld() == null || !isGladeConfigured()) return false;
        if (!location.getWorld().getName().equals(gladeWorldName())) return false;
        int halfSize = gladeHalfSize();
        return Math.abs(location.getBlockX() - settings.getInt("glade.center-x")) < halfSize
            && Math.abs(location.getBlockZ() - settings.getInt("glade.center-z")) < halfSize;
    }

    private boolean isInsideMaze(Location location) {
        if (location == null || location.getWorld() == null || !isGladeConfigured()) return false;
        if (!location.getWorld().getName().equals(gladeWorldName())) return false;
        long dx = (long) location.getBlockX() - settings.getInt("glade.center-x");
        long dz = (long) location.getBlockZ() - settings.getInt("glade.center-z");
        long radius = mazeRadius();
        return dx * dx + dz * dz <= radius * radius;
    }

    private boolean isGladeConfigured() {
        return settings.isSet("glade.world") && !gladeWorldName().isBlank()
            && settings.isSet("glade.center-x") && settings.isSet("glade.center-z");
    }

    private String gladeWorldName() {
        return settings.getString("glade.world", "");
    }

    private int gladeHalfSize() {
        return Math.max(50, Math.min(250, settings.getInt("glade.half-size", DEFAULT_GLADE_HALF_SIZE)));
    }

    private int mazeRadius() {
        return Math.max(250, Math.min(5_000, settings.getInt("maze.radius", DEFAULT_MAZE_RADIUS)));
    }

    private int maxGrievers() {
        return Math.max(1, Math.min(50, settings.getInt("grievers.maximum", DEFAULT_MAX_GRIEVERS)));
    }

    private int countManagedGrievers(World world) {
        int count = 0;
        for (Entity entity : world.getEntities()) {
            if (isManagedGriever(entity)) count++;
        }
        return count;
    }

    private int removeManagedGrievers() {
        int removed = 0;
        for (World world : Bukkit.getWorlds()) removed += removeManagedGrievers(world);
        return removed;
    }

    private int removeManagedGrievers(World world) {
        int removed = 0;
        for (Entity entity : world.getEntities()) {
            if (isManagedGriever(entity)) {
                entity.remove();
                removed++;
            }
        }
        return removed;
    }

    private boolean isManagedGriever(Entity entity) {
        return entity != null
            && entity.getPersistentDataContainer().has(grieverKey, PersistentDataType.BYTE);
    }

    private static boolean isNight(long time) {
        return time >= 13_000L && time < 23_000L;
    }

    private static Integer parseInteger(String value) {
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static void usage(CommandSender sender) {
        sender.sendMessage("§7Maze Runner: §f/maze status");
        sender.sendMessage("§7/maze setglade §8— задать центр Глейда, стоя в его центре");
        sender.sendMessage("§7/maze gladesize <50–250> §8— полуразмер безопасной зоны");
        sender.sendMessage("§7/maze maze-radius <250–5000> §8— радиус игровой зоны");
        sender.sendMessage("§7/maze start|stop §8— запустить/остановить раунд; /maze clear §8— убрать Гриверов");
    }
}
