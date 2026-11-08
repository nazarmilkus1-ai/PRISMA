package team.prisma.plugin.teleport;

import org.bukkit.Bukkit;
import org.bukkit.command.*;
import org.bukkit.entity.Player;

public final class TpaCommand implements CommandExecutor, TabCompleter {
    private final TpaManager manager;

    public TpaCommand(TpaManager manager) {
        this.manager = manager;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }

        String sub = command.getName().toLowerCase();
        if (sub.equals("tpa")) {
            if (args.length != 1) {
                player.sendMessage("§7Использование: /tpa <игрок>");
                return true;
            }
            Player target = Bukkit.getPlayerExact(args[0]);
            if (target == null) {
                player.sendMessage("§cИгрок не найден.");
                return true;
            }
            if (target.equals(player)) {
                player.sendMessage("§cНельзя отправить запрос самому себе.");
                return true;
            }
            if (!manager.request(player, target)) {
                player.sendMessage("§cУ этого игрока уже есть активный запрос. Попробуйте позже.");
                return true;
            }
            player.sendMessage("§aЗапрос на телепортацию отправлен игроку §f" + target.getName() + "§a.");
            target.sendMessage("§eИгрок §f" + player.getName() + " §eхочет телепортироваться к вам. §a/tpaccept §7или §c/tpdeny§e. Запрос действует 30 секунд.");
            return true;
        }

        if (sub.equals("tpaccept")) {
            TpaManager.Request request = manager.get(player);
            if (request == null) {
                player.sendMessage("§cАктивных запросов нет.");
                return true;
            }
            Player requester = Bukkit.getPlayer(request.requester());
            if (requester == null) {
                manager.clear(player);
                player.sendMessage("§cИгрок уже вышел.");
                return true;
            }
            manager.clear(player);
            if (!requester.teleport(player.getLocation())) {
                player.sendMessage("§cНе удалось выполнить телепортацию.");
                requester.sendMessage("§cТелепортация не удалась.");
                return true;
            }
            player.sendMessage("§aЗапрос принят.");
            requester.sendMessage("§aВас телепортировали к §f" + player.getName() + "§a.");
            return true;
        }

        if (sub.equals("tpdeny")) {
            TpaManager.Request request = manager.get(player);
            if (request == null) {
                player.sendMessage("§cАктивных запросов нет.");
                return true;
            }
            manager.clear(player);
            player.sendMessage("§eЗапрос отклонён.");
            Player requester = Bukkit.getPlayer(request.requester());
            if (requester != null) requester.sendMessage("§cВаш запрос на телепортацию отклонён.");
            return true;
        }

        return false;
    }

    @Override
    public java.util.List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length == 1 && command.getName().equalsIgnoreCase("tpa")) {
            String prefix = args[0].toLowerCase();
            return Bukkit.getOnlinePlayers().stream().map(Player::getName)
                .filter(name -> name.toLowerCase().startsWith(prefix)).sorted().toList();
        }
        return java.util.List.of();
    }
}
