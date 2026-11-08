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
import team.prisma.plugin.homes.PlayerHomesStore;
import team.prisma.plugin.homes.PlayerHomesStore.HomePoint;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class PlayerHomeCommand implements CommandExecutor, TabCompleter {
    private final JavaPlugin plugin;
    private final PlayerStateCache cache;
    private final PlayerHomesStore homes;

    public PlayerHomeCommand(JavaPlugin plugin, PlayerStateCache cache, PlayerHomesStore homes) {
        this.plugin = plugin;
        this.cache = cache;
        this.homes = homes;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Команда доступна только игрокам.");
            return true;
        }
        String userId = cache.userIdOf(player.getUniqueId());
        if (userId == null || userId.isBlank()) {
            player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите на сервер.");
            return true;
        }

        String name = command.getName().toLowerCase(Locale.ROOT);
        switch (name) {
            case "sethome" -> setHome(player, args);
            case "home" -> goHome(player, args);
            case "homes" -> listHomes(player, args);
            case "delhome" -> deleteHome(player, args);
            default -> player.sendMessage("§cНеизвестная команда домов.");
        }
        return true;
    }

    private void setHome(Player player, String[] args) {
        Integer slot = parseSlot(player, args, 1, "/sethome [1|2]");
        if (slot == null) return;
        if (!homes.isStorageHealthy()) {
            player.sendMessage("§cХранилище домов недоступно. Данные не изменены; сообщите администрации.");
            return;
        }

        Location location = player.getLocation().clone();
        player.sendMessage("§7Сохраняю дом " + slot + "...");
        homes.set(player.getUniqueId(), slot, location).whenComplete((saved, error) -> main(() -> {
            if (!player.isOnline()) return;
            if (error != null || !Boolean.TRUE.equals(saved)) {
                player.sendMessage("§cНе удалось сохранить дом. Данные предыдущего сохранения оставлены без изменений.");
                return;
            }
            player.sendMessage("§aДом " + slot + " сохранён: §f"
                + location.getWorld().getName() + " "
                + location.getBlockX() + " " + location.getBlockY() + " " + location.getBlockZ());
        }));
    }

    private void goHome(Player player, String[] args) {
        Integer slot = parseSlot(player, args, 1, "/home [1|2]");
        if (slot == null) return;

        HomePoint home = homes.get(player.getUniqueId(), slot);
        if (home == null) {
            player.sendMessage("§cДом " + slot + " не установлен. Используйте §f/sethome " + slot + "§c.");
            return;
        }

        World world = Bukkit.getWorld(home.world());
        if (world == null) {
            player.sendMessage("§cМир дома «" + home.name() + "» не загружен. Телепортация отменена.");
            return;
        }
        if (home.y() < world.getMinHeight() || home.y() >= world.getMaxHeight()) {
            player.sendMessage("§cКоординаты дома недопустимы для этого мира. Телепортация отменена.");
            return;
        }

        Location target = new Location(world, home.x(), home.y(), home.z(), home.yaw(), home.pitch());
        player.sendMessage("§7Телепортация домой...");
        player.teleportAsync(target).whenComplete((success, error) -> {
            if (!plugin.isEnabled()) return;
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (!player.isOnline()) return;
                if (error != null || !Boolean.TRUE.equals(success)) {
                    player.sendMessage("§cНе удалось телепортироваться домой. Попробуйте позже.");
                    if (error != null) {
                        plugin.getLogger().warning("Ошибка телепортации домой для " + player.getName()
                            + ": " + error.getClass().getSimpleName());
                    }
                    return;
                }
                player.sendMessage("§aВы дома: §f" + home.name() + "§a.");
            });
        });
    }

    private void listHomes(Player player, String[] args) {
        if (args.length != 0) {
            player.sendMessage("§7Использование: /homes");
            return;
        }

        var playerHomes = homes.list(player.getUniqueId());
        player.sendMessage("§6§lВаши дома §7(" + playerHomes.size() + "/" + PlayerHomesStore.MAX_HOMES + ")");
        if (playerHomes.isEmpty()) {
            player.sendMessage("§7Домов пока нет. Установите первый: §f/sethome 1");
        }
        playerHomes.forEach((slot, home) -> player.sendMessage(
            "§eДом " + slot + " §8— §f" + home.world() + " "
                + floor(home.x()) + " " + floor(home.y()) + " " + floor(home.z())
                + " §8| §7телепорт: §f/home " + slot
        ));
        if (!homes.isStorageHealthy()) {
            player.sendMessage("§cХранилище сейчас недоступно для изменений; существующие дома доступны для просмотра.");
        }
    }

    private void deleteHome(Player player, String[] args) {
        Integer slot = parseSlot(player, args, null, "/delhome <1|2>");
        if (slot == null) return;

        if (!homes.isStorageHealthy()) {
            player.sendMessage("§cХранилище домов недоступно. Данные не изменены; сообщите администрации.");
            return;
        }
        if (homes.get(player.getUniqueId(), slot) == null) {
            player.sendMessage("§cДом " + slot + " не установлен.");
            return;
        }
        player.sendMessage("§7Удаляю дом " + slot + "...");
        homes.delete(player.getUniqueId(), slot).whenComplete((saved, error) -> main(() -> {
            if (!player.isOnline()) return;
            if (error != null || !Boolean.TRUE.equals(saved)) {
                player.sendMessage("§cНе удалось удалить дом. Предыдущее сохранённое состояние восстановлено.");
                return;
            }
            player.sendMessage("§eДом " + slot + " удалён.");
        }));
    }

    private Integer parseSlot(Player player, String[] args, Integer defaultSlot, String usage) {
        if (args.length == 0) {
            if (defaultSlot != null) return defaultSlot;
            player.sendMessage("§7Использование: " + usage);
            return null;
        }
        if (args.length != 1) {
            player.sendMessage("§7Использование: " + usage);
            return null;
        }
        try {
            int slot = Integer.parseInt(args[0]);
            if (slot >= 1 && slot <= PlayerHomesStore.MAX_HOMES) return slot;
        } catch (NumberFormatException ignored) {
            // Сообщение ниже объясняет допустимые слоты.
        }
        player.sendMessage("§cНомер дома должен быть 1 или 2.");
        return null;
    }

    private void main(Runnable task) {
        if (!plugin.isEnabled()) return;
        try {
            Bukkit.getScheduler().runTask(plugin, task);
        } catch (IllegalStateException ignored) {
            // Сервер уже завершает работу; не отправляем сообщение после выгрузки плагина.
        }
    }

    private static int floor(double value) {
        return (int) Math.floor(value);
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length != 1) return List.of();
        String name = command.getName().toLowerCase(Locale.ROOT);
        if (!List.of("sethome", "home", "delhome").contains(name)) return List.of();
        String prefix = args[0].toLowerCase(Locale.ROOT);
        List<String> slots = new ArrayList<>();
        for (String slot : List.of("1", "2")) {
            if (slot.startsWith(prefix)) slots.add(slot);
        }
        return slots;
    }
}
