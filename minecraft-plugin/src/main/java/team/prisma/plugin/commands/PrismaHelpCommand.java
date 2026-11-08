package team.prisma.plugin.commands;

import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.modules.ModuleStateCache;

import java.util.Locale;

/**
 * Краткая русскоязычная справка PRISMA. Полный постраничный каталог остаётся в /prismacommands.
 */
public final class PrismaHelpCommand implements CommandExecutor {
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;

    public PrismaHelpCommand(PlayerStateCache cache, ModuleStateCache modules) {
        this.cache = cache;
        this.modules = modules;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (args.length > 1) {
            usage(sender);
            return true;
        }

        String section = args.length == 0 ? "main" : args[0].toLowerCase(Locale.ROOT);
        if (!section.equals("main") && !section.equals("основное")
            && !section.equals("перемещение") && !section.equals("телепортация")
            && !section.equals("кланы") && !section.equals("авторизация")
            && !section.equals("персонал")) {
            usage(sender);
            return true;
        }

        String platform = sender instanceof Player player
            ? cache.platformOf(player.getUniqueId()) : null;
        boolean staff = sender.hasPermission("prisma.command.spawnmanage")
            || sender.hasPermission("prisma.command.tpall")
            || sender.hasPermission("prisma.command.moderation")
            || sender.hasPermission("prisma.staff");
        boolean bedrock = "BEDROCK".equalsIgnoreCase(platform);

        if (section.equals("main") || section.equals("основное")) {
            sender.sendMessage("§a§lPRISMA §7— §fКраткая справка");
            if (modules.isEnabled("minecraft-spawns")) sender.sendMessage("§6Точки появления: §f/spawn, /spawns");
            if (modules.isEnabled("minecraft-homes")) sender.sendMessage("§6Личные дома: §f/home, /homes");
            if (modules.isEnabled("minecraft-journey")) sender.sendMessage("§6Точки и координаты: §f/checkpoint, /coords, /lastdeath");
            if (modules.isEnabled("minecraft-hud")) sender.sendMessage("§6Интерфейс: §f/hud [on|off|status]");
            if (modules.isEnabled("minecraft-graves")) sender.sendMessage("§6Могилы: §f/grave, /graves, /grave claim <id>");
            if (modules.isEnabled("minecraft-teleport-requests")) sender.sendMessage("§6Общение: §f/tpa <игрок>, /tpaccept, /tpdeny");
            if (modules.isEnabled("minecraft-clan-commands")) sender.sendMessage("§6Кланы: §f/clan help");
            if (modules.isEnabled("minecraft-village-commands")) sender.sendMessage("§6Сёла: §f/village");
            if (bedrock) {
                sender.sendMessage("§6Вход: §fGeyser + Floodgate (отдельный пароль не нужен)");
            } else {
                sender.sendMessage("§6Вход Java: §f/login <пароль>, /register <пароль> <пароль>");
            }
            sender.sendMessage("§7Разделы: /help перемещение | кланы | авторизация | персонал");
            sender.sendMessage("§7Все команды и доступ: §f/prismacommands 1");
            return true;
        }

        switch (section) {
            case "перемещение", "телепортация" -> {
                sender.sendMessage("§a§lPRISMA §7— §fПеремещение");
                if (modules.isEnabled("minecraft-spawns")) sender.sendMessage("§e/spawn §7— основной спавн; §e/spawn 0 §7— тот же спавн");
                if (modules.isEnabled("minecraft-spawns")) sender.sendMessage("§e/spawns §7— все точки; §e/spawn <номер> §7— дополнительная точка");
                if (modules.isEnabled("minecraft-homes")) sender.sendMessage("§e/sethome [1|2] §7— установить дом");
                if (modules.isEnabled("minecraft-homes")) sender.sendMessage("§e/home [1|2] §7— вернуться домой; §e/homes §7— список");
                if (modules.isEnabled("minecraft-homes")) sender.sendMessage("§e/delhome <1|2> §7— удалить дом");
                if (modules.isEnabled("minecraft-journey")) sender.sendMessage("§e/checkpoint set <имя> §7— сохранить точку (максимум 5)");
                if (modules.isEnabled("minecraft-journey")) sender.sendMessage("§e/checkpoint list/go/delete <имя> §7— список, переход или удаление");
                if (modules.isEnabled("minecraft-journey")) sender.sendMessage("§e/coords §7— личные координаты; §e/coords share §7— опубликовать их в чате");
                if (modules.isEnabled("minecraft-journey")) sender.sendMessage("§e/lastdeath §7— координаты и время последней смерти");
                if (modules.isEnabled("minecraft-graves")) sender.sendMessage("§e/grave §7— могилы; §e/grave claim <id> §7— вернуть предметы у метки");
                if (modules.isEnabled("minecraft-hud")) sender.sendMessage("§e/hud [on|off|status] §7— настройки интерфейса HUD/TAB");
                if (modules.isEnabled("minecraft-teleport-requests")) sender.sendMessage("§e/tpa <игрок> §7— запросить телепортацию; §e/tpaccept §7/ §e/tpdeny");
                if (staff && modules.isEnabled("minecraft-spawns")) sender.sendMessage("§c/setspawn <номер> <название> §7и §c/delspawn <номер> §7— управление спавнами");
            }
            case "кланы" -> {
                sender.sendMessage("§a§lPRISMA §7— §fКланы и сёла");
                if (modules.isEnabled("minecraft-clan-commands")) sender.sendMessage("§e/clan §7— справка по командам клана");
                if (modules.isEnabled("minecraft-clan-commands")) sender.sendMessage("§e/clan list §7— список кланов; §e/clan info §7— информация");
                if (modules.isEnabled("minecraft-clan-commands")) sender.sendMessage("§e/clan invite <игрок> §7— приглашение; §e/clan invites §7— приглашения");
                if (modules.isEnabled("minecraft-village-commands")) sender.sendMessage("§e/village list §7— сёла; §e/village info §7— информация");
                sender.sendMessage("§7Подробный список: §f/prismacommands 1");
            }
            case "авторизация" -> {
                sender.sendMessage("§a§lPRISMA §7— §fАвторизация");
                if (bedrock) {
                    sender.sendMessage("§7Bedrock-вход подтверждается через Geyser + Floodgate.");
                    sender.sendMessage("§7Отдельный пароль PRISMA Auth для Bedrock не используется.");
                } else {
                    sender.sendMessage("§e/register <пароль> <пароль> §7— задать пароль впервые");
                    sender.sendMessage("§e/login <пароль> §7— войти");
                    sender.sendMessage("§e/changepass <текущий> <новый> §7— изменить пароль");
                    sender.sendMessage("§7Никогда не сообщайте свой пароль другим игрокам.");
                }
            }
            case "персонал" -> {
                if (!staff) {
                    sender.sendMessage("§cЭтот раздел доступен только персоналу PRISMA.");
                    return true;
                }
                sender.sendMessage("§a§lPRISMA §7— §fКоманды персонала");
                boolean hasStaffCommand = false;
                if (sender.hasPermission("prisma.command.ptp") && modules.isEnabled("minecraft-staff-teleport")) {
                    sender.sendMessage("§e/ptp <игрок> §7— телепортироваться к игроку");
                    hasStaffCommand = true;
                }
                if (sender.hasPermission("prisma.command.ptphere") && modules.isEnabled("minecraft-staff-teleport")) {
                    sender.sendMessage("§e/ptphere <игрок> §7— переместить игрока к себе");
                    hasStaffCommand = true;
                }
                if (sender.hasPermission("prisma.command.spawnmanage") && modules.isEnabled("minecraft-spawns")) {
                    sender.sendMessage("§e/setspawn <номер> <название> §7— настроить точку");
                    sender.sendMessage("§e/delspawn <номер> §7— удалить точку");
                    hasStaffCommand = true;
                }
                if (sender.hasPermission("prisma.command.tpall") && modules.isEnabled("minecraft-tpall")) {
                    sender.sendMessage("§e/tpall §7— запросить массовую телепортацию");
                    sender.sendMessage("§e/tpall confirm §7— подтвердить после проверки актуальной роли, в течение 20 секунд");
                    sender.sendMessage("§e/tpall cancel §7— отменить запрос");
                    hasStaffCommand = true;
                }
                if (sender.hasPermission("prisma.command.moderation") && modules.isEnabled("minecraft-moderation")) {
                    sender.sendMessage("§e/warn <ник> <причина> §7— предупреждение");
                    sender.sendMessage("§e/mute <ник> <срок|perm> <причина> §7— мут; срок: 30m, 2h, 7d");
                    sender.sendMessage("§e/unmute <ник> §7— снять мут; §e/kick <ник> <причина> §7— кикнуть");
                    sender.sendMessage("§e/ban <ник> <причина> §7— бан навсегда; §e/tempban <ник> <срок> <причина> §7— временный бан");
                    sender.sendMessage("§e/unban <ник> §7— снять бан; §e/history <ник> §7— история наказаний");
                    hasStaffCommand = true;
                }
                if (!hasStaffCommand) {
                    sender.sendMessage("§7Для вашей роли нет отдельных игровых команд персонала.");
                }
                sender.sendMessage("§7Доступ зависит от назначенной роли. Полный список: §f/prismacommands 1");
            }
            default -> usage(sender);
        }
        return true;
    }

    private static void usage(CommandSender sender) {
        sender.sendMessage("§7Использование: /help [перемещение|кланы|авторизация|персонал]");
    }
}
