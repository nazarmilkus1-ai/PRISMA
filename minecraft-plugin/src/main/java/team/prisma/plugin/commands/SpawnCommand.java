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
import team.prisma.plugin.spawn.SpawnPointsStore;
import team.prisma.plugin.spawn.SpawnPointsStore.SpawnPoint;
import team.prisma.plugin.cache.PlayerStateCache;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.stream.Collectors;

public final class SpawnCommand implements CommandExecutor, TabCompleter {
    private final JavaPlugin plugin;
    private final SpawnPointsStore spawns;
    private final PlayerStateCache cache;

    public SpawnCommand(JavaPlugin plugin, SpawnPointsStore spawns, PlayerStateCache cache) {
        this.plugin = plugin;
        this.spawns = spawns;
        this.cache = cache;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }

        String root = command.getName().toLowerCase(Locale.ROOT);
        boolean staffManagement = root.equals("setspawn") || root.equals("delspawn");
        if (!staffManagement) {
            String userId = cache.userIdOf(player.getUniqueId());
            if (userId == null || userId.isBlank()) {
                player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите на сервер.");
                return true;
            }
        }
        switch (root) {
            case "spawn" -> teleport(player, args);
            case "spawns" -> list(player, args);
            case "setspawn" -> set(player, args);
            case "delspawn" -> delete(player, args);
            default -> player.sendMessage("§cНеизвестная команда появления.");
        }
        return true;
    }

    private void teleport(Player player, String[] args) {
        int id = 0;
        if (args.length > 1) {
            player.sendMessage("§7Использование: /spawn [0–999]");
            return;
        }
        if (args.length == 1) {
            try {
                id = Integer.parseInt(args[0]);
            } catch (NumberFormatException error) {
                player.sendMessage("§cНомер точки должен быть числом от 0 до 999.");
                return;
            }
        }
        if (id < 0 || id > SpawnPointsStore.MAX_CUSTOM_SPAWN_ID) {
            player.sendMessage("§cНомер точки должен быть от 0 до 999.");
            return;
        }

        Location target;
        if (id == SpawnPointsStore.MAIN_SPAWN_ID && spawns.get(0) == null) {
            if (Bukkit.getWorlds().isEmpty()) {
                player.sendMessage("§cНа сервере пока нет загруженного мира.");
                return;
            }
            target = Bukkit.getWorlds().get(0).getSpawnLocation();
        } else {
            SpawnPoint point = spawns.get(id);
            if (point == null) {
                player.sendMessage("§cТочка появления " + id + " не настроена. Список: §f/spawns§c.");
                return;
            }
            World world = Bukkit.getWorld(point.world());
            if (world == null) {
                player.sendMessage("§cМир точки «" + point.name() + "» не загружен. Телепортация отменена.");
                return;
            }
            if (point.y() < world.getMinHeight() || point.y() >= world.getMaxHeight()) {
                player.sendMessage("§cКоординаты точки недопустимы для этого мира. Телепортация отменена.");
                return;
            }
            target = new Location(world, point.x(), point.y(), point.z(), point.yaw(), point.pitch());
        }

        player.sendMessage("§7Телепортация...");
        player.teleportAsync(target).whenComplete((success, error) -> {
            if (!plugin.isEnabled()) return;
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (!player.isOnline()) return;
                if (error != null || !Boolean.TRUE.equals(success)) {
                    player.sendMessage("§cНе удалось телепортироваться. Попробуйте позже.");
                    if (error != null) plugin.getLogger().warning(
                        "Ошибка телепортации на спавн для " + player.getName()
                            + ": " + error.getClass().getSimpleName()
                    );
                    return;
                }
                player.sendMessage("§aВы прибыли на точку появления.");
            });
        });
    }

    private void list(Player player, String[] args) {
        if (args.length != 0) {
            player.sendMessage("§7Использование: /spawns");
            return;
        }

        player.sendMessage("§6§lТочки появления PRISMA");
        SpawnPoint main = spawns.get(0);
        if (main == null) {
            if (Bukkit.getWorlds().isEmpty()) {
                player.sendMessage("§70 — Основной спавн (мир ещё не загружен)");
            } else {
                Location location = Bukkit.getWorlds().get(0).getSpawnLocation();
                player.sendMessage("§e0 §8— §fОсновной спавн §7(" + location.getWorld().getName()
                    + " " + location.getBlockX() + " " + location.getBlockY() + " " + location.getBlockZ() + ")");
            }
        } else {
            player.sendMessage(format(main));
        }
        for (SpawnPoint point : spawns.list().values()) {
            if (point.id() != 0) player.sendMessage(format(point));
        }
        if (spawns.list().size() == 1 && main != null || spawns.list().isEmpty()) {
            player.sendMessage("§7Дополнительные точки не настроены.");
        }
        if (!spawns.isStorageHealthy()) {
            player.sendMessage("§cХранилище точек недоступно для изменений; сообщите администрации.");
        }
    }

    private void set(Player player, String[] args) {
        if (!player.hasPermission("prisma.command.spawnmanage")) {
            player.sendMessage("§cНедостаточно прав. Настраивать спавны может только старший персонал.");
            return;
        }
        if (args.length < 3) {
            player.sendMessage("§7Использование: /setspawn <0–999> <название>");
            return;
        }
        int id;
        try {
            id = Integer.parseInt(args[0]);
        } catch (NumberFormatException error) {
            player.sendMessage("§cНомер точки должен быть числом от 0 до 999.");
            return;
        }
        if (id < 0 || id > SpawnPointsStore.MAX_CUSTOM_SPAWN_ID) {
            player.sendMessage("§cНомер точки должен быть от 0 до 999.");
            return;
        }
        if (!spawns.isStorageHealthy()) {
            player.sendMessage("§cХранилище точек недоступно. Старые данные не изменены.");
            return;
        }

        String name = argsFrom(args, 1);
        if (name.length() > 40 || name.isBlank()) {
            player.sendMessage("§cНазвание должно содержать от 1 до 40 символов.");
            return;
        }
        Location location = player.getLocation().clone();
        player.sendMessage("§7Сохраняю точку " + id + "...");
        spawns.set(id, name, location).whenComplete((saved, error) -> main(() -> {
            if (!player.isOnline()) return;
            if (error != null || !Boolean.TRUE.equals(saved)) {
                player.sendMessage("§cНе удалось сохранить точку. Предыдущее сохранённое состояние оставлено без изменений.");
                return;
            }
            player.sendMessage("§aТочка " + id + " «" + name + "» сохранена.");
        }));
    }

    private void delete(Player player, String[] args) {
        if (!player.hasPermission("prisma.command.spawnmanage")) {
            player.sendMessage("§cНедостаточно прав. Настраивать спавны может только старший персонал.");
            return;
        }
        if (args.length != 1) {
            player.sendMessage("§7Использование: /delspawn <0–999>");
            return;
        }
        int id;
        try {
            id = Integer.parseInt(args[0]);
        } catch (NumberFormatException error) {
            player.sendMessage("§cНомер точки должен быть числом от 0 до 999.");
            return;
        }
        if (id < 0 || id > SpawnPointsStore.MAX_CUSTOM_SPAWN_ID) {
            player.sendMessage("§cНомер точки должен быть от 0 до 999.");
            return;
        }
        if (!spawns.isStorageHealthy()) {
            player.sendMessage("§cХранилище точек недоступно. Старые данные не изменены.");
            return;
        }
        if (spawns.get(id) == null) {
            player.sendMessage("§cТочка " + id + " не найдена.");
            return;
        }
        player.sendMessage("§7Удаляю точку " + id + "...");
        spawns.delete(id).whenComplete((saved, error) -> main(() -> {
            if (!player.isOnline()) return;
            if (error != null || !Boolean.TRUE.equals(saved)) {
                player.sendMessage("§cНе удалось удалить точку. Предыдущее сохранённое состояние восстановлено.");
                return;
            }
            if (id == 0) {
                player.sendMessage("§eПереопределение основного спавна удалено. Теперь используется спавн первого мира.");
            } else {
                player.sendMessage("§eТочка " + id + " удалена.");
            }
        }));
    }

    private void main(Runnable task) {
        if (!plugin.isEnabled()) return;
        try {
            Bukkit.getScheduler().runTask(plugin, task);
        } catch (IllegalStateException ignored) {
            // Сервер уже завершает работу; не отправляем сообщение после выгрузки плагина.
        }
    }

    private static String argsFrom(String[] args, int start) {
        return java.util.Arrays.stream(args).skip(start).collect(Collectors.joining(" ")).trim();
    }

    private static String format(SpawnPoint point) {
        return "§e" + point.id() + " §8— §f" + point.name() + " §7("
            + point.world() + " " + floor(point.x()) + " " + floor(point.y()) + " " + floor(point.z()) + ")";
    }

    private static int floor(double value) {
        return (int) Math.floor(value);
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length != 1) return List.of();
        String root = command.getName().toLowerCase(Locale.ROOT);
        if (!List.of("spawn", "setspawn", "delspawn").contains(root)) return List.of();
        String prefix = args[0].toLowerCase(Locale.ROOT);
        List<String> ids = new ArrayList<>();
        ids.add("0");
        ids.addAll(spawns.list().keySet().stream().filter(id -> id > 0)
            .map(String::valueOf).sorted().collect(Collectors.toList()));
        return ids.stream().distinct().filter(id -> id.startsWith(prefix)).collect(Collectors.toList());
    }
}
