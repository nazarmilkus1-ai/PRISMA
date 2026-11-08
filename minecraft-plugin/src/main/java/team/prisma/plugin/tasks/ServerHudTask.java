package team.prisma.plugin.tasks;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.modules.ModuleStateCache;

import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.Locale;

/**
 * Русскоязычный HUD в action bar и сводка сервера в TAB.
 * Не заменяет scoreboard: сторонние плагины могут продолжать использовать sidebar.
 */
public final class ServerHudTask implements Runnable, CommandExecutor, Listener {
    private final JavaPlugin plugin;
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;
    private boolean previousFeatureEnabled;
    private final Set<UUID> disabledPlayers = ConcurrentHashMap.newKeySet();
    private long ticks;

    public ServerHudTask(JavaPlugin plugin, PlayerStateCache cache, ModuleStateCache modules) {
        this.plugin = plugin;
        this.cache = cache;
        this.modules = modules;
    }

    @Override
    public void run() {
        if (!plugin.isEnabled()) return;
        if (!modules.isEnabled("minecraft-hud")) {
            if (previousFeatureEnabled) {
                for (Player player : Bukkit.getOnlinePlayers()) {
                    player.sendActionBar(Component.empty());
                    player.sendPlayerListHeaderAndFooter(Component.empty(), Component.empty());
                }
            }
            previousFeatureEnabled = false;
            return;
        }
        previousFeatureEnabled = true;
        ticks += 40L;
        Set<UUID> onlineIds = Bukkit.getOnlinePlayers().stream()
            .map(Player::getUniqueId).collect(java.util.stream.Collectors.toSet());
        disabledPlayers.removeIf(id -> !onlineIds.contains(id));
        int online = onlineIds.size();
        int maximum = Bukkit.getMaxPlayers();
        String tps = currentTpsLabel();

        for (Player player : Bukkit.getOnlinePlayers()) {
            if (cache.userIdOf(player.getUniqueId()) == null || disabledPlayers.contains(player.getUniqueId())) {
                continue;
            }

            int ping = Math.max(0, player.getPing());
            player.sendActionBar(Component.text("PRISMA", NamedTextColor.RED)
                .append(Component.text("  •  ", NamedTextColor.DARK_GRAY))
                .append(Component.text("Онлайн ", NamedTextColor.GRAY))
                .append(Component.text(online + "/" + maximum, NamedTextColor.WHITE))
                .append(Component.text("  •  ", NamedTextColor.DARK_GRAY))
                .append(Component.text("Пинг ", NamedTextColor.GRAY))
                .append(Component.text(ping + " мс", ping <= 100 ? NamedTextColor.GREEN
                    : ping <= 200 ? NamedTextColor.YELLOW : NamedTextColor.RED))
                .append(Component.text("  •  ", NamedTextColor.DARK_GRAY))
                .append(Component.text("TPS ", NamedTextColor.GRAY))
                .append(Component.text(tps, NamedTextColor.WHITE)));

            if (ticks % 200L == 0L) {
                updateTab(player, online, maximum, tps, ping);
            }
        }
    }

    private void updateTab(Player player, int online, int maximum, String tps, int ping) {
        player.sendPlayerListHeaderAndFooter(
            Component.text("PRISMA", NamedTextColor.RED)
                .append(Component.text("  •  ", NamedTextColor.DARK_GRAY))
                .append(Component.text("Версия " + plugin.getDescription().getVersion(), NamedTextColor.GOLD))
                .append(Component.newline())
                .append(Component.text("Игровое сообщество", NamedTextColor.GRAY)),
            Component.text("Онлайн: " + online + "/" + maximum, NamedTextColor.WHITE)
                .append(Component.text("  •  TPS: " + tps, NamedTextColor.GRAY))
                .append(Component.newline())
                .append(Component.text("Подсказка: ", NamedTextColor.GRAY))
                .append(Component.text("/help", NamedTextColor.YELLOW))
                .append(Component.text("  •  ", NamedTextColor.DARK_GRAY))
                .append(Component.text("Пинг: " + ping + " мс", NamedTextColor.WHITE)));
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        disabledPlayers.remove(event.getPlayer().getUniqueId());
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Команда доступна только игрокам.");
            return true;
        }
        UUID id = player.getUniqueId();
        if (cache.userIdOf(id) == null) {
            player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите на сервер.");
            return true;
        }
        if (args.length > 1) {
            usage(player);
            return true;
        }

        String action = args.length == 0 ? "toggle" : args[0].toLowerCase(Locale.ROOT);
        switch (action) {
            case "on", "вкл" -> {
                disabledPlayers.remove(id);
                updateTab(player, Bukkit.getOnlinePlayers().size(), Bukkit.getMaxPlayers(), currentTpsLabel(), Math.max(0, player.getPing()));
                player.sendMessage("§aHUD и информация TAB включены.");
            }
            case "off", "выкл" -> {
                disabledPlayers.add(id);
                player.sendPlayerListHeaderAndFooter(Component.empty(), Component.empty());
                player.sendMessage("§eHUD и информация TAB отключены до выхода с сервера.");
            }
            case "status", "статус" -> player.sendMessage(disabledPlayers.contains(id)
                ? "§7HUD и информация TAB сейчас отключены."
                : "§aHUD и информация TAB сейчас включены.");
            case "toggle" -> {
                if (disabledPlayers.remove(id)) {
                    updateTab(player, Bukkit.getOnlinePlayers().size(), Bukkit.getMaxPlayers(), currentTpsLabel(), Math.max(0, player.getPing()));
                    player.sendMessage("§aHUD и информация TAB включены.");
                } else {
                    disabledPlayers.add(id);
                    player.sendPlayerListHeaderAndFooter(Component.empty(), Component.empty());
                    player.sendMessage("§eHUD и информация TAB отключены до выхода с сервера.");
                }
            }
            default -> {
                usage(player);
                return true;
            }
        }
        return true;
    }

    private static String currentTpsLabel() {
        try {
            double[] tpsValues = Bukkit.getServer().getTPS();
            if (tpsValues.length == 0 || !Double.isFinite(tpsValues[0])) return "—";
            double value = Math.max(0.0, Math.min(20.0, tpsValues[0]));
            return String.format(Locale.ROOT, "%.1f", value);
        } catch (RuntimeException error) {
            return "—";
        }
    }

    private static void usage(CommandSender sender) {
        sender.sendMessage("§7Использование: /hud [on|off|status]");
    }
}
