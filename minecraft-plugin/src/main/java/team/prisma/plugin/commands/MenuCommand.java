package team.prisma.plugin.commands;

import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import team.prisma.plugin.menu.MainMenu;

/** /menu — opens the PRISMA main menu (Java and Bedrock). */
public final class MenuCommand implements CommandExecutor {
    private final MainMenu menu;

    public MenuCommand(MainMenu menu) {
        this.menu = menu;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        menu.open(player);
        return true;
    }
}
