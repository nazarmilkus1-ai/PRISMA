package team.prisma.plugin.teleport;

import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.command.TabCompleter;
import org.bukkit.entity.Player;
import team.prisma.plugin.staff.StaffPermissionCache;

public final class StaffTeleportCommand implements CommandExecutor, TabCompleter {
    private final StaffPermissionCache staff;

    public StaffTeleportCommand(StaffPermissionCache staff) {
        this.staff = staff;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        if (args.length < 1) {
            player.sendMessage("§7Использование: /ptp <игрок> или /ptphere <игрок>");
            return true;
        }

        boolean teleportToHere = command.getName().equalsIgnoreCase("ptphere");
        String permission = teleportToHere ? "teleport.to_here" : "teleport.to_player";

        Player target = Bukkit.getPlayerExact(args[0]);
        if (target == null) {
            player.sendMessage("§cИгрок не найден или не в сети.");
            return true;
        }

        staff.checkNow(player, permission, allowed -> {
            // The permission service guarantees this callback runs on Bukkit's main thread.
            if (!player.isOnline()) return;
            if (!allowed) {
                player.sendMessage("§cНедостаточно прав.");
                return;
            }
            if (!target.isOnline()) {
                player.sendMessage("§cИгрок уже не в сети.");
                return;
            }

            if (teleportToHere) {
                if (target.teleport(player.getLocation())) {
                    player.sendMessage("§aИгрок §f" + target.getName() + " §aтелепортирован к вам.");
                    target.sendMessage("§eВас телепортировал §f" + player.getName() + "§e.");
                } else {
                    player.sendMessage("§cНе удалось выполнить телепортацию.");
                }
            } else if (player.teleport(target.getLocation())) {
                player.sendMessage("§aВы телепортированы до §f" + target.getName() + "§a.");
            } else {
                player.sendMessage("§cНе удалось выполнить телепортацию.");
            }
        });
        return true;
    }

    @Override
    public java.util.List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length == 1) {
            String prefix = args[0].toLowerCase();
            return Bukkit.getOnlinePlayers().stream()
                .map(Player::getName)
                .filter(name -> name.toLowerCase().startsWith(prefix))
                .sorted()
                .toList();
        }
        return java.util.List.of();
    }
}
