package team.prisma.plugin.commands;

import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.World;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.command.TabCompleter;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.journey.PlayerJourneyStore;
import team.prisma.plugin.journey.PlayerJourneyStore.MutationResult;
import team.prisma.plugin.journey.PlayerJourneyStore.Point;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class PlayerJourneyCommand implements CommandExecutor, TabCompleter {
    private static final DateTimeFormatter DEATH_TIME =
        DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm").withZone(ZoneId.systemDefault());

    private final JavaPlugin plugin;
    private final PlayerStateCache cache;
    private final PlayerJourneyStore journey;
    private final Map<java.util.UUID, Long> lastCoordinateBroadcast = new java.util.HashMap<>();

    public PlayerJourneyCommand(JavaPlugin plugin, PlayerStateCache cache, PlayerJourneyStore journey) {
        this.plugin = plugin;
        this.cache = cache;
        this.journey = journey;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        String userId = cache.userIdOf(player.getUniqueId());
        if (userId == null || userId.isBlank()) {
            player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите на сервер.");
            return true;
        }

        switch (command.getName().toLowerCase(Locale.ROOT)) {
            case "coords" -> coords(player, args);
            case "lastdeath" -> lastDeath(player, args);
            case "checkpoint" -> checkpoint(player, args);
            default -> player.sendMessage("§cНеизвестная команда контрольных точек.");
        }
        return true;
    }

    private void coords(Player player, String[] args) {
        if (args.length > 1 || (args.length == 1 && !args[0].equalsIgnoreCase("share"))) {
            player.sendMessage("§7Использование: /coords [share]");
            return;
        }
        Location location = player.getLocation();
        String coordinates = location.getWorld().getName() + " "
            + location.getBlockX() + " " + location.getBlockY() + " " + location.getBlockZ();
        if (args.length == 0) {
            player.sendMessage("§6Ваши координаты: §f" + coordinates);
            player.sendMessage("§7Чтобы показать координаты всем игрокам, используйте §f/coords share§7.");
            return;
        }

        long now = System.currentTimeMillis();
        lastCoordinateBroadcast.entrySet().removeIf(entry -> now - entry.getValue() > 60_000L);
        long last = lastCoordinateBroadcast.getOrDefault(player.getUniqueId(), 0L);
        if (now - last < 15_000L) {
            player.sendMessage("§cПодождите перед следующей публикацией координат.");
            return;
        }
        lastCoordinateBroadcast.put(player.getUniqueId(), now);
        Bukkit.broadcastMessage("§7[Координаты] §f" + player.getName() + " §7находится в §f" + coordinates);
    }

    private void lastDeath(Player player, String[] args) {
        if (args.length != 0) {
            player.sendMessage("§7Использование: /lastdeath");
            return;
        }
        Point point = journey.lastDeath(player.getUniqueId());
        if (point == null) {
            player.sendMessage("§7Сохранённого места смерти пока нет.");
            return;
        }
        player.sendMessage("§6Последнее место смерти: §f" + coordinates(point));
        if (point.recordedAtEpochMilli() > 0L) {
            player.sendMessage("§7Время: §f" + DEATH_TIME.format(Instant.ofEpochMilli(point.recordedAtEpochMilli())));
        }
    }

    private void checkpoint(Player player, String[] args) {
        if (args.length == 0 || args[0].equalsIgnoreCase("list")) {
            if (args.length > 1) {
                usage(player);
                return;
            }
            listCheckpoints(player);
            return;
        }
        String action = args[0].toLowerCase(Locale.ROOT);
        switch (action) {
            case "set" -> setCheckpoint(player, args);
            case "delete", "del" -> deleteCheckpoint(player, args);
            case "go", "tp" -> goCheckpoint(player, args);
            default -> usage(player);
        }
    }

    private void listCheckpoints(Player player) {
        var checkpoints = journey.checkpoints(player.getUniqueId());
        player.sendMessage("§6§lКонтрольные точки §7(" + checkpoints.size() + "/" + PlayerJourneyStore.MAX_CHECKPOINTS + ")");
        if (checkpoints.isEmpty()) {
            player.sendMessage("§7Точек пока нет. Создайте её: §f/checkpoint set база");
            return;
        }
        checkpoints.forEach((name, point) -> player.sendMessage(
            "§e" + name + " §8— §f" + coordinates(point) + " §8| §7перейти: §f/checkpoint go " + name
        ));
        if (!journey.isStorageHealthy()) {
            player.sendMessage("§cХранилище недоступно для изменений; существующие точки оставлены только для чтения.");
        }
    }

    private void setCheckpoint(Player player, String[] args) {
        if (args.length != 2 || !validCheckpointName(args[1])) {
            player.sendMessage("§7Использование: /checkpoint set <имя>");
            player.sendMessage("§7Имя: 1–16 букв, цифр, дефисов или подчёркиваний; максимум 5 точек.");
            return;
        }
        if (!journey.isStorageHealthy()) {
            player.sendMessage("§cХранилище контрольных точек недоступно. Данные не изменены.");
            return;
        }
        Point point = Point.capture(player.getLocation(), System.currentTimeMillis());
        if (point == null) {
            player.sendMessage("§cНе удалось прочитать текущую позицию.");
            return;
        }
        String name = args[1].toLowerCase(Locale.ROOT);
        player.sendMessage("§7Сохраняю контрольную точку «" + name + "»...");
        journey.setCheckpoint(player.getUniqueId(), name, point).whenComplete((result, error) -> main(() -> {
            if (!player.isOnline()) return;
            if (error != null || result == null || result == MutationResult.FAILED
                || result == MutationResult.UNAVAILABLE) {
                player.sendMessage("§cНе удалось сохранить точку. Прежние данные не изменены.");
                return;
            }
            switch (result) {
                case SAVED -> player.sendMessage("§aКонтрольная точка «" + name + "» сохранена.");
                case LIMIT_REACHED -> player.sendMessage("§cДостигнут лимит — " + PlayerJourneyStore.MAX_CHECKPOINTS
                    + " точек. Удалите ненужную через §f/checkpoint delete <имя>§c.");
                default -> player.sendMessage("§cНе удалось сохранить контрольную точку.");
            }
        }));
    }

    private void deleteCheckpoint(Player player, String[] args) {
        if (args.length != 2 || !validCheckpointName(args[1])) {
            player.sendMessage("§7Использование: /checkpoint delete <имя>");
            return;
        }
        if (!journey.isStorageHealthy()) {
            player.sendMessage("§cХранилище контрольных точек недоступно. Данные не изменены.");
            return;
        }
        String name = args[1].toLowerCase(Locale.ROOT);
        journey.deleteCheckpoint(player.getUniqueId(), name).whenComplete((result, error) -> main(() -> {
            if (!player.isOnline()) return;
            if (error != null || result == null || result == MutationResult.FAILED
                || result == MutationResult.UNAVAILABLE) {
                player.sendMessage("§cНе удалось удалить точку. Старые данные сохранены.");
            } else if (result == MutationResult.DELETED) {
                player.sendMessage("§eКонтрольная точка «" + name + "» удалена.");
            } else {
                player.sendMessage("§cКонтрольная точка «" + name + "» не найдена.");
            }
        }));
    }

    private void goCheckpoint(Player player, String[] args) {
        if (args.length != 2 || !validCheckpointName(args[1])) {
            player.sendMessage("§7Использование: /checkpoint go <имя>");
            return;
        }
        Point point = journey.checkpoint(player.getUniqueId(), args[1]);
        if (point == null) {
            player.sendMessage("§cТакая контрольная точка не найдена. Список: §f/checkpoint list§c.");
            return;
        }
        World world = Bukkit.getWorld(point.world());
        if (world == null) {
            player.sendMessage("§cМир точки «" + args[1] + "» не загружен. Телепортация отменена.");
            return;
        }
        if (point.y() < world.getMinHeight() || point.y() >= world.getMaxHeight()) {
            player.sendMessage("§cКоординаты контрольной точки недопустимы для этого мира.");
            return;
        }
        Location target = new Location(world, point.x(), point.y(), point.z(), point.yaw(), point.pitch());
        player.sendMessage("§7Телепортация к точке «" + args[1] + "»...");
        player.teleportAsync(target).whenComplete((success, error) -> main(() -> {
            if (!player.isOnline()) return;
            if (error != null || !Boolean.TRUE.equals(success)) {
                player.sendMessage("§cНе удалось телепортироваться к контрольной точке.");
                if (error != null) plugin.getLogger().warning(
                    "Ошибка телепортации к контрольной точке для " + player.getName()
                        + ": " + error.getClass().getSimpleName()
                );
                return;
            }
            player.sendMessage("§aВы прибыли к контрольной точке «" + args[1] + "».");
        }));
    }

    private static String coordinates(Point point) {
        return point.world() + " " + floor(point.x()) + " " + floor(point.y()) + " " + floor(point.z());
    }

    private static int floor(double value) {
        return (int) Math.floor(value);
    }

    private static boolean validCheckpointName(String name) {
        return name != null && name.matches("^[\\p{L}\\p{N}_-]{1,16}$");
    }

    private static void usage(CommandSender sender) {
        sender.sendMessage("§7/coords [share] §8— текущие координаты, лично или в общий чат");
        sender.sendMessage("§7/lastdeath §8— последнее сохранённое место смерти");
        sender.sendMessage("§7/checkpoint list");
        sender.sendMessage("§7/checkpoint set <имя>");
        sender.sendMessage("§7/checkpoint go <имя>");
        sender.sendMessage("§7/checkpoint delete <имя>");
    }

    private void main(Runnable task) {
        if (!plugin.isEnabled()) return;
        Bukkit.getScheduler().runTask(plugin, () -> {
            if (plugin.isEnabled()) task.run();
        });
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (!(sender instanceof Player player)) return List.of();
        String root = command.getName().toLowerCase(Locale.ROOT);
        if (root.equals("coords") && args.length == 1) {
            return "share".startsWith(args[0].toLowerCase(Locale.ROOT)) ? List.of("share") : List.of();
        }
        if (!root.equals("checkpoint")) return List.of();
        if (args.length == 1) {
            String prefix = args[0].toLowerCase(Locale.ROOT);
            List<String> actions = List.of("list", "set", "go", "delete");
            return actions.stream().filter(action -> action.startsWith(prefix)).toList();
        }
        if (args.length == 2 && (args[0].equalsIgnoreCase("go")
            || args[0].equalsIgnoreCase("tp")
            || args[0].equalsIgnoreCase("delete")
            || args[0].equalsIgnoreCase("del"))) {
            String prefix = args[1].toLowerCase(Locale.ROOT);
            return journey.checkpoints(player.getUniqueId()).keySet().stream()
                .filter(name -> name.startsWith(prefix)).toList();
        }
        return List.of();
    }
}
