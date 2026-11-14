package team.prisma.plugin.commands;

import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import team.prisma.plugin.explore.ExploreMapManager;

/** /worldmap — gives the player their personal fog-of-war map (also opened from /menu). */
public final class MapCommand implements CommandExecutor {
    private final ExploreMapManager maps;

    public MapCommand(ExploreMapManager maps) {
        this.maps = maps;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        switch (maps.give(player)) {
            case GIVEN -> {
                player.sendMessage("§aВаша карта PRISMA выдана. Она показывает только те места, где вы были.");
                player.sendMessage("§7Метки: §9дом §7· §cконтрольные точки §7· §fместо смерти §7· спавн.");
            }
            case ALREADY_HAS -> player.sendMessage("§eКарта уже у вас в инвентаре.");
            case NO_PROFILE -> player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите на сервер.");
            default -> player.sendMessage("§cНе удалось создать карту. Попробуйте позже.");
        }
        return true;
    }
}
