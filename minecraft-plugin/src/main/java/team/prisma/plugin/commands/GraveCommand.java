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
import team.prisma.plugin.graves.GraveStore;
import team.prisma.plugin.graves.GraveStore.Grave;
import team.prisma.plugin.graves.GraveStore.Operation;
import team.prisma.plugin.graves.GraveStore.Result;
import team.prisma.plugin.listeners.GraveListener;

import java.util.List;
import java.util.Locale;

public final class GraveCommand implements CommandExecutor, TabCompleter {
    private static final double MAX_DISTANCE_SQUARED = 25.0d;

    private final JavaPlugin plugin;
    private final PlayerStateCache cache;
    private final GraveStore store;
    private final GraveListener listener;

    public GraveCommand(JavaPlugin plugin, PlayerStateCache cache, GraveStore store, GraveListener listener) {
        this.plugin = plugin;
        this.cache = cache;
        this.store = store;
        this.listener = listener;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        String userId = cache.userIdOf(player.getUniqueId());
        if (userId == null || userId.isBlank()) {
            player.sendMessage("§cПрофиль PRISMA ещё не синхронизирован. Перезайдите на сервер.");
            return true;
        }
        if (!store.isStorageHealthy()) {
            player.sendMessage("§cХранилище могил недоступно. Данные не изменены.");
            return true;
        }

        if (args.length == 0 || args[0].equalsIgnoreCase("list")) {
            if (args.length > 1) usage(player);
            else list(player);
            return true;
        }

        switch (args[0].toLowerCase(Locale.ROOT)) {
            case "info" -> info(player, args);
            case "claim", "restore" -> claim(player, args);
            default -> usage(player);
        }
        return true;
    }

    private void list(Player player) {
        boolean admin = player.hasPermission("prisma.command.grave.admin");
        List<Grave> graves = store.list(player.getUniqueId(), admin, System.currentTimeMillis());
        if (!store.isStorageHealthy()) {
            player.sendMessage("§cХранилище могил недоступно; список может быть неполным.");
            return;
        }
        player.sendMessage("§6§lМогилы §7— §fсрок хранения 10 минут");
        if (graves.isEmpty()) {
            player.sendMessage("§7Активных могил нет.");
            return;
        }
        for (Grave grave : graves.stream().limit(10).toList()) {
            long leftMillis = Math.max(0L, grave.expiresAtEpochMilli() - System.currentTimeMillis());
            long leftSeconds = Math.max(1L, (leftMillis + 999L) / 1000L);
            player.sendMessage("§e#" + grave.id() + " §7— §f" + grave.ownerName()
                + " §8| §f" + grave.world() + " " + block(grave.x()) + " " + block(grave.y()) + " " + block(grave.z())
                + " §8| §7ещё " + leftSeconds + " сек.");
            player.sendMessage("  §7Информация: §f/grave info " + grave.id()
                + " §8| §7получить у метки: §f/grave claim " + grave.id());
        }
        if (graves.size() > 10) player.sendMessage("§7Показаны первые 10 могил.");
    }

    private void info(Player player, String[] args) {
        if (args.length != 2 || !validId(args[1])) {
            player.sendMessage("§7Использование: /grave info <id>");
            return;
        }
        Grave grave = visibleGrave(player, args[1]);
        if (grave == null) {
            player.sendMessage("§cМогила не найдена или у вас нет доступа к ней.");
            return;
        }
        long seconds = Math.max(0L, (grave.expiresAtEpochMilli() - System.currentTimeMillis() + 999L) / 1000L);
        player.sendMessage("§6Могила §e#" + grave.id() + " §7— владелец: §f" + grave.ownerName());
        player.sendMessage("§7Мир и координаты: §f" + grave.world() + " "
            + block(grave.x()) + " " + block(grave.y()) + " " + block(grave.z()));
        player.sendMessage("§7Срок действия: §f" + seconds + " сек.");
        player.sendMessage("§7Подойдите к метке на расстояние до 5 блоков и используйте §f/grave claim " + grave.id());
    }

    private void claim(Player player, String[] args) {
        if (args.length != 2 || !validId(args[1])) {
            player.sendMessage("§7Использование: /grave claim <id>");
            return;
        }
        long now = System.currentTimeMillis();
        Grave inProgress = store.claimingFor(player.getUniqueId()).stream()
            .filter(candidate -> candidate.id().equalsIgnoreCase(args[1]))
            .findFirst().orElse(null);
        if (inProgress != null) {
            // A transaction already authorized before a restart can be resumed after clearing space.
            listener.deliverClaim(player, inProgress, true);
            return;
        }
        Grave grave = visibleGrave(player, args[1]);
        if (grave == null) {
            player.sendMessage("§cМогила не найдена, истекла или у вас нет доступа к ней.");
            return;
        }
        World world = Bukkit.getWorld(grave.world());
        if (world == null) {
            player.sendMessage("§cМир могилы не загружен. Предметы не выдавались.");
            return;
        }
        if (!player.getWorld().getUID().equals(world.getUID())) {
            player.sendMessage("§cВы должны находиться в том же мире, где находится могила.");
            return;
        }
        Location target = new Location(world, grave.x(), grave.y(), grave.z());
        if (player.getLocation().distanceSquared(target) > MAX_DISTANCE_SQUARED) {
            player.sendMessage("§cПодойдите к метке ближе — не дальше 5 блоков.");
            return;
        }

        Operation operation = store.beginClaim(grave.id(), player.getUniqueId(),
            player.hasPermission("prisma.command.grave.admin"), now);
        if (operation.result() != Result.SAVED || operation.grave() == null) {
            switch (operation.result()) {
                case EXPIRED -> player.sendMessage("§cСрок действия могилы истёк.");
                case FORBIDDEN -> player.sendMessage("§cЗабрать эту могилу может только владелец или администратор.");
                case ALREADY_CLAIMING -> player.sendMessage("§cПолучение этой могилы уже обрабатывается.");
                case STORAGE_UNAVAILABLE, FAILED -> player.sendMessage("§cНе удалось начать получение. Предметы не изменены.");
                default -> player.sendMessage("§cМогила недоступна.");
            }
            return;
        }
        listener.deliverClaim(player, operation.grave(), true);
    }

    private Grave visibleGrave(Player player, String rawId) {
        Grave grave = store.pending(rawId, System.currentTimeMillis());
        if (grave == null) return null;
        if (!grave.ownerId().equals(player.getUniqueId())
            && !player.hasPermission("prisma.command.grave.admin")) return null;
        return grave;
    }

    private static boolean validId(String id) {
        return id != null && id.matches("(?i)^[a-f0-9]{8}$");
    }

    private static int block(double value) {
        return (int) Math.floor(value);
    }

    private static void usage(CommandSender sender) {
        sender.sendMessage("§7/grave или /graves §8— список ваших могил");
        sender.sendMessage("§7/grave info <id> §8— информация и координаты");
        sender.sendMessage("§7/grave claim <id> §8— вернуть предметы у метки");
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (!(sender instanceof Player player) || !store.isStorageHealthy()) return List.of();
        if (args.length == 1) {
            String prefix = args[0].toLowerCase(Locale.ROOT);
            return List.of("list", "info", "claim")
                .stream().filter(value -> value.startsWith(prefix)).toList();
        }
        if (args.length == 2 && (args[0].equalsIgnoreCase("claim")
            || args[0].equalsIgnoreCase("info") || args[0].equalsIgnoreCase("restore"))) {
            boolean admin = player.hasPermission("prisma.command.grave.admin");
            String prefix = args[1].toLowerCase(Locale.ROOT);
            return store.list(player.getUniqueId(), admin, System.currentTimeMillis()).stream()
                .map(Grave::id).filter(id -> id.startsWith(prefix)).toList();
        }
        return List.of();
    }
}
