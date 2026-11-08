package team.prisma.plugin.commands;

import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.command.TabCompleter;
import org.bukkit.entity.Player;
import team.prisma.plugin.auth.MinecraftAuthService;

import java.util.List;

public final class MinecraftAuthCommand implements CommandExecutor, TabCompleter {
    private final MinecraftAuthService auth;

    public MinecraftAuthCommand(MinecraftAuthService auth) {
        this.auth = auth;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("PRISMA Auth доступен только игрокам.");
            return true;
        }

        switch (label.toLowerCase(java.util.Locale.ROOT)) {
            case "register" -> {
                if (args.length != 2) {
                    player.sendMessage("§7Использование: /register <пароль> <пароль>");
                    return true;
                }
                auth.register(player, args[0], args[1]);
            }
            case "login" -> {
                if (args.length != 1) {
                    player.sendMessage("§7Использование: /login <пароль>");
                    return true;
                }
                auth.login(player, args[0]);
            }
            case "changepass" -> {
                if (args.length != 2) {
                    player.sendMessage("§7Использование: /changepass <текущий> <новый>");
                    return true;
                }
                auth.changePassword(player, args[0], args[1]);
            }
            case "prismaauth", "auth" -> auth.sendHelp(player);
            default -> auth.sendHelp(player);
        }
        return true;
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        return List.of();
    }
}
