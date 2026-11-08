package team.prisma.plugin.commands;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.command.*;
import org.bukkit.entity.Player;
import org.bukkit.plugin.Plugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.clans.Village;
import team.prisma.plugin.clans.VillageManager;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;

import java.util.*;
import java.util.stream.Collectors;

public final class ClanCommand implements CommandExecutor, TabCompleter {
    private static final Map<String, String> ALIASES = Map.ofEntries(
        Map.entry("create", "create"), Map.entry("создать", "create"),
        Map.entry("join", "join"), Map.entry("вступить", "join"),
        Map.entry("leave", "leave"), Map.entry("покинуть", "leave"),
        Map.entry("chat", "chat"), Map.entry("чат", "chat"),
        Map.entry("list", "list"), Map.entry("список", "list"),
        Map.entry("info", "info"), Map.entry("инфо", "info"),
        Map.entry("invite", "invite"), Map.entry("пригласить", "invite"),
        Map.entry("invites", "invites"), Map.entry("заявки", "invites"),
        Map.entry("accept", "accept"), Map.entry("принять", "accept"),
        Map.entry("deny", "deny"), Map.entry("отклонить", "deny"),
        Map.entry("kick", "kick"), Map.entry("исключить", "kick"),
        Map.entry("promote", "promote"), Map.entry("повысить", "promote"),
        Map.entry("demote", "demote"), Map.entry("понизить", "demote"),
        Map.entry("role", "role"), Map.entry("роль", "role"), Map.entry("назначить", "role"),
        Map.entry("transfer", "transfer"), Map.entry("передать", "transfer"),
        Map.entry("disband", "disband"), Map.entry("распустить", "disband"),
        Map.entry("home", "home"), Map.entry("дом", "home"),
        Map.entry("village", "village"), Map.entry("село", "village"),
        Map.entry("war", "war"), Map.entry("война", "war"), Map.entry("войны", "war"),
        Map.entry("news", "news"), Map.entry("новости", "news"),
        Map.entry("announce", "announce"), Map.entry("объявить", "announce"), Map.entry("объявление", "announce")
    );

    private final Plugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final VillageManager villages;

    public ClanCommand(Plugin plugin, SupabaseClient supabase, PlayerStateCache cache, VillageManager villages) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.villages = villages;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        if (args.length == 0) {
            help(player);
            return true;
        }

        String sub = ALIASES.getOrDefault(args[0].toLowerCase(Locale.ROOT), "");
        switch (sub) {
            case "create" -> create(player, args);
            case "join" -> join(player, args);
            case "leave" -> leave(player);
            case "chat" -> chat(player, args);
            case "list" -> list(player);
            case "info" -> info(player, args);
            case "invite" -> invite(player, args);
            case "invites" -> invites(player);
            case "accept" -> acceptInvite(player, args);
            case "deny" -> denyInvite(player, args);
            case "kick" -> action(player, "KICK", args);
            case "promote" -> action(player, "PROMOTE", args);
            case "demote" -> action(player, "DEMOTE", args);
            case "role" -> setRole(player, args);
            case "transfer" -> action(player, "TRANSFER", args);
            case "disband" -> action(player, "DISBAND", args);
            case "home" -> home(player, args);
            case "village" -> villageHelp(player);
            case "war" -> war(player, args);
            case "news" -> news(player);
            case "announce" -> announce(player, args);
            default -> help(player);
        }
        return true;
    }

    private void help(Player player) {
        player.sendMessage("§6§lPRISMA CLAN");
        player.sendMessage("§7/clan create <название> <тег>");
        player.sendMessage("§7/clan invite <игрок> §8| §7/clan invites");
        player.sendMessage("§7/clan accept <id> §8| §7/clan deny <id>");
        player.sendMessage("§7/clan kick/promote/demote <игрок>");
        player.sendMessage("§7/clan role <игрок> <совладелец|офицер|участник|рекрут>");
        player.sendMessage("§7/clan village §8| §7/village <...>");
        player.sendMessage("§7/clan home [село] §8| §7/clan info");
        player.sendMessage("§7/clan chat <сообщение> §8| §7/clan leave");
        player.sendMessage("§7/clan war [list|create|accept|deny|start|finish] ...");
        player.sendMessage("§7/clan news §8| §7/clan announce <заголовок> | <текст>");
    }

    private String userId(Player player) {
        String id = cache.userIdOf(player.getUniqueId());
        if (id == null) player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите на сервер.");
        return id;
    }

    private void create(Player player, String[] args) {
        if (args.length < 3) {
            player.sendMessage("§7Использование: /clan create <название> <тег>");
            return;
        }
        if (cache.clanOf(player.getUniqueId()) != null) {
            player.sendMessage("§cВы уже состоите в клане.");
            return;
        }
        String userId = userId(player);
        if (userId == null) return;

        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_name", args[1]);
        body.addProperty("p_tag", args[2]);
        call(player, RpcNames.CREATE_CLAN, body, result -> {
            String clanId = stringField(result, "clan_id");
            String tag = stringField(result, "tag");
            if (clanId == null) {
                player.sendMessage("§cНе удалось создать клан: " + error(result));
                return;
            }
            cache.setClan(player.getUniqueId(), clanId);
            player.sendMessage("§aКлан §f[" + (tag == null ? args[2] : tag) + "] " + args[1] + " §aсоздан.");
        });
    }

    private void join(Player player, String[] args) {
        if (args.length < 2) {
            player.sendMessage("§7Использование: /clan join <название>");
            return;
        }
        if (cache.clanOf(player.getUniqueId()) != null) {
            player.sendMessage("§cВы уже состоите в клане.");
            return;
        }
        String userId = userId(player);
        if (userId == null) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_clan_name", String.join(" ", Arrays.copyOfRange(args, 1, args.length)));
        call(player, RpcNames.JOIN_CLAN, body, result -> {
            String clanId = stringField(result, "clan_id");
            if (clanId == null) {
                String code = error(result);
                String message = switch (code) {
                    case "CLAN_NOT_OPEN" -> "Этот клан закрыт. Вступление доступно только по приглашению.";
                    case "CLAN_NOT_FOUND" -> "Клан не найден.";
                    case "USER_ALREADY_IN_CLAN" -> "Вы уже состоите в клане.";
                    case "USER_NOT_ALLOWED" -> "Для вступления сначала одобрите заявку и получите whitelist.";
                    default -> "Не удалось вступить: " + code;
                };
                player.sendMessage("§c" + message);
                return;
            }
            cache.setClan(player.getUniqueId(), clanId);
            player.sendMessage("§aВы вступили в клан §f[" + safe(result, "tag") + "] " + safe(result, "name") + "§a.");
        });
    }

    private void leave(Player player) {
        String userId = userId(player);
        if (userId == null) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        call(player, RpcNames.LEAVE_CLAN, body, result -> {
            if (!bool(result, "success")) {
                player.sendMessage("§cНе удалось покинуть клан: " + error(result));
                return;
            }
            cache.setClan(player.getUniqueId(), null);
            player.sendMessage(bool(result, "disbanded") ? "§eКлан расформирован." : "§eВы покинули клан.");
            villages.refresh();
        });
    }

    private void chat(Player player, String[] args) {
        if (args.length < 2) {
            player.sendMessage("§7Использование: /clan chat <сообщение>");
            return;
        }
        String clanId = cache.clanOf(player.getUniqueId());
        if (clanId == null) {
            player.sendMessage("§cВы не состоите в клане.");
            return;
        }
        String message = String.join(" ", Arrays.copyOfRange(args, 1, args.length));
        String line = "§8[§6Клан§8] §f" + player.getName() + "§7: §f" + message;
        for (UUID uuid : cache.onlineInClan(clanId)) {
            Player member = Bukkit.getPlayer(uuid);
            if (member != null) member.sendMessage(line);
        }
    }

    private void list(Player player) {
        JsonObject body = new JsonObject();
        body.addProperty("p_limit", 20);
        call(player, RpcNames.LIST_CLANS, body, result -> {
            JsonArray rows = result.has("clans") && result.get("clans").isJsonArray()
                ? result.getAsJsonArray("clans") : new JsonArray();
            if (rows.isEmpty() && !result.has("clans")) {
                player.sendMessage("§7Не удалось загрузить список кланов.");
                return;
            }
            if (rows.isEmpty()) {
                player.sendMessage("§7Пока нет активных кланов.");
                return;
            }
            player.sendMessage("§6§lТОП КЛАНОВ");
            for (var element : rows) {
                JsonObject clan = element.getAsJsonObject();
                player.sendMessage("§f[" + safe(clan,"tag") + "] §e" + safe(clan,"name")
                    + " §7ур." + safe(clan,"level") + " §8· §f" + safe(clan,"rating") + " рейтинга");
            }
        });
    }

    private void info(Player player, String[] args) {
        String identifier = args.length >= 2
            ? String.join(" ", Arrays.copyOfRange(args, 1, args.length))
            : cache.clanOf(player.getUniqueId());

        if (identifier == null || identifier.isBlank()) {
            player.sendMessage("§cВы не в клане. Укажите название.");
            return;
        }

        JsonObject body = new JsonObject();
        body.addProperty("p_identifier", identifier);
        call(player, RpcNames.GET_CLAN_BY_IDENTIFIER, body, result -> {
            if ("CLAN_NOT_FOUND".equals(error(result))) {
                player.sendMessage("§cКлан не найден.");
                return;
            }
            player.sendMessage("§6§l[" + safe(result,"tag") + "] " + safe(result,"name"));
            player.sendMessage("§7Уровень: §f" + safe(result,"level") + " §8· §7XP: §f" + safe(result,"xp"));
            player.sendMessage("§7Рейтинг: §f" + safe(result,"rating")
                + " §8· §7Победы/поражения: §f" + safe(result,"wins") + "§7/§f" + safe(result,"losses"));
            player.sendMessage("§7Описание: §f" + safe(result,"description"));
        });
    }

    private void invite(Player player, String[] args) {
        if (args.length != 2) {
            player.sendMessage("§7Использование: /clan invite <игрок>");
            return;
        }
        String userId = userId(player);
        if (userId == null) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_target_nickname", args[1]);
        call(player, RpcNames.INVITE_PLAYER, body, result -> {
            if (!bool(result,"success")) {
                player.sendMessage("§cНе удалось отправить приглашение: " + error(result));
                return;
            }
            Player target = Bukkit.getPlayerExact(args[1]);
            player.sendMessage("§aПриглашение отправлено игроку §f" + args[1] + "§a.");
            if (target != null) target.sendMessage("§eВас пригласили в клан. Посмотрите приглашения: §f/clan invites");
        });
    }

    private void invites(Player player) {
        String userId = userId(player);
        if (userId == null) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        call(player, RpcNames.LIST_CLAN_INVITES, body, result -> {
            JsonArray arr = result.has("invites") && result.get("invites").isJsonArray() ? result.getAsJsonArray("invites")
                : result.isJsonArray() ? result.getAsJsonArray() : new JsonArray();
            if (arr.isEmpty()) {
                player.sendMessage("§7Активных приглашений нет.");
                return;
            }
            player.sendMessage("§6Приглашения:");
            for (var element : arr) {
                JsonObject x = element.getAsJsonObject();
                player.sendMessage("§f" + safe(x,"id") + " §7— §e[" + safe(x,"tag") + "] " + safe(x,"name") + " §8от §f" + safe(x,"inviter_nickname"));
            }
            player.sendMessage("§7Принять: /clan accept <ID>");
        });
    }

    private void acceptInvite(Player player, String[] args) {
        if (args.length != 2) { player.sendMessage("§7Использование: /clan accept <invite-uuid>"); return; }
        String userId = userId(player);
        if (userId == null) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_invite_id", args[1]);
        call(player, RpcNames.ACCEPT_CLAN_INVITE, body, result -> {
            if (!bool(result,"success")) { player.sendMessage("§cНе удалось принять: " + error(result)); return; }
            cache.setClan(player.getUniqueId(), stringField(result,"clan_id"));
            player.sendMessage("§aВы вступили в §f[" + safe(result,"tag") + "] " + safe(result,"name") + "§a.");
        });
    }

    private void denyInvite(Player player, String[] args) {
        if (args.length != 2) { player.sendMessage("§7Использование: /clan deny <invite-uuid>"); return; }
        String userId = userId(player);
        if (userId == null) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_invite_id", args[1]);
        call(player, RpcNames.DECLINE_CLAN_INVITE, body, result -> {
            if (!bool(result,"success")) player.sendMessage("§cНе удалось отклонить: " + error(result));
            else player.sendMessage("§eПриглашение отклонено.");
        });
    }

    private void setRole(Player player, String[] args) {
        if (args.length != 3) {
            player.sendMessage("§7Использование: /clan role <игрок> <совладелец|офицер|участник|рекрут>");
            return;
        }

        String role = switch (args[2].toLowerCase(Locale.ROOT)) {
            case "совладелец", "co_owner", "co-owner", "заместитель" -> "co_owner";
            case "офицер", "officer" -> "officer";
            case "участник", "member" -> "member";
            case "рекрут", "recruit" -> "recruit";
            default -> null;
        };
        if (role == null) {
            player.sendMessage("§cНеизвестная роль. Используйте: совладелец, офицер, участник или рекрут.");
            return;
        }

        String userId = userId(player);
        if (userId == null) return;

        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_target_nickname", args[1]);
        body.addProperty("p_role", role);
        call(player, RpcNames.SET_CLAN_ROLE, body, result -> {
            if (!bool(result, "success")) {
                String code = error(result);
                String message = switch (code) {
                    case "NO_CLAN_PERMISSION" -> "У вас нет права изменять эту роль.";
                    case "TARGET_INVALID_ROLE" -> "Нельзя управлять ролью равного или более высокого уровня.";
                    case "CANNOT_MANAGE_SELF" -> "Нельзя изменять собственную роль.";
                    case "ROLE_UNCHANGED" -> "У игрока уже установлена эта роль.";
                    case "TARGET_NOT_IN_CLAN" -> "Игрок не состоит в вашем клане.";
                    case "PLAYER_NOT_FOUND" -> "Игрок не найден.";
                    default -> "Операция не выполнена: " + code;
                };
                player.sendMessage("§c" + message);
                return;
            }
            String label = switch (role) {
                case "co_owner" -> "Совладелец";
                case "officer" -> "Офицер";
                case "member" -> "Участник";
                default -> "Рекрут";
            };
            player.sendMessage("§aРоль игрока §f" + args[1] + "§a изменена на §f" + label + "§a.");
        });
    }

    private void action(Player player, String action, String[] args) {
        if (!action.equals("DISBAND") && args.length != 2) {
            player.sendMessage("§7Использование: /clan " + action.toLowerCase(Locale.ROOT) + " <игрок>");
            return;
        }
        String userId = userId(player);
        if (userId == null) return;
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_action", action);
        if (!action.equals("DISBAND")) body.addProperty("p_target_nickname", args[1]);
        call(player, RpcNames.CLAN_ACTION, body, result -> {
            if (!bool(result,"success")) {
                player.sendMessage("§c" + humanClanError(error(result)));
                return;
            }
            if (action.equals("DISBAND")) cache.setClan(player.getUniqueId(), null);
            player.sendMessage("§aГотово.");
            villages.refresh();
        });
    }

    private void news(Player player) {
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId(player));
        call(player, RpcNames.LIST_CLAN_ANNOUNCEMENTS, body, result -> {
            JsonArray rows = result.has("announcements") && result.get("announcements").isJsonArray()
                ? result.getAsJsonArray("announcements") : new JsonArray();
            if (rows.isEmpty()) {
                player.sendMessage("§7У клана пока нет объявлений.");
                return;
            }
            player.sendMessage("§6§lОБЪЯВЛЕНИЯ КЛАНА");
            for (var item : rows) {
                JsonObject a = item.getAsJsonObject();
                player.sendMessage("§e" + safe(a, "title") + " §8· §7" + safe(a, "author_nickname"));
                player.sendMessage("§f" + safe(a, "body"));
            }
        });
    }

    private void announce(Player player, String[] args) {
        String payload = args.length >= 2
            ? String.join(" ", Arrays.copyOfRange(args, 1, args.length))
            : "";
        int separator = payload.indexOf('|');
        if (separator <= 0 || separator >= payload.length() - 1) {
            player.sendMessage("§7Использование: /clan announce <заголовок> | <текст>");
            return;
        }
        String title = payload.substring(0, separator).trim();
        String message = payload.substring(separator + 1).trim();
        if (title.length() < 3 || title.length() > 120 || message.length() < 3 || message.length() > 3000) {
            player.sendMessage("§cЗаголовок: 3–120 символов, текст: 3–3000 символов.");
            return;
        }

        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId(player));
        body.addProperty("p_title", title);
        body.addProperty("p_body", message);
        call(player, RpcNames.CREATE_CLAN_ANNOUNCEMENT, body, result -> {
            if (!bool(result, "success")) {
                player.sendMessage("§c" + humanClanAnnouncementError(error(result)));
                return;
            }
            player.sendMessage("§aОбъявление опубликовано.");
        });
    }

    private static String humanClanAnnouncementError(String code) {
        return switch (code) {
            case "NO_CLAN_PERMISSION" -> "Объявления может публиковать только владелец или офицер.";
            case "INVALID_ANNOUNCEMENT" -> "Заголовок: 3–120 символов, текст: 3–3000 символов.";
            case "NO_CLAN" -> "Вы не состоите в клане.";
            default -> "Объявление не опубликовано: " + code;
        };
    }

    private void war(Player player, String[] args) {
        if (args.length < 2 || args[1].equalsIgnoreCase("list") || args[1].equalsIgnoreCase("список") || args[1].equalsIgnoreCase("войны")) {
            JsonObject body = new JsonObject();
            body.addProperty("p_user_id", userId(player));
            call(player, RpcNames.LIST_CLAN_WARS, body, result -> {
                JsonArray wars = result.has("wars") && result.get("wars").isJsonArray()
                    ? result.getAsJsonArray("wars") : new JsonArray();
                if (wars.isEmpty()) {
                    player.sendMessage("§7У вашего клана пока нет войн.");
                    return;
                }
                player.sendMessage("§6§lВОЙНЫ КЛАНА");
                for (var item : wars) {
                    JsonObject w = item.getAsJsonObject();
                    player.sendMessage(
                        "§f[" + safe(w, "opponent_tag") + "] §e" + safe(w, "opponent")
                            + " §7— " + warStatus(safe(w, "status"))
                            + " §8ID: §f" + safe(w, "id")
                    );
                }
            });
            return;
        }

        String sub = args[1].toLowerCase(Locale.ROOT);
        if (sub.equals("create") || sub.equals("создать")) {
            if (args.length < 3) {
                player.sendMessage("§7Использование: /clan war create <клан>");
                return;
            }
            JsonObject body = new JsonObject();
            body.addProperty("p_user_id", userId(player));
            body.addProperty("p_target", String.join(" ", Arrays.copyOfRange(args, 2, args.length)));
            call(player, RpcNames.CREATE_CLAN_WAR, body, result -> {
                if (!bool(result, "success")) {
                    player.sendMessage("§c" + humanClanWarError(error(result)));
                    return;
                }
                player.sendMessage("§aВызов на войну отправлен клану §f[" + safe(result, "target_tag") + "] " + safe(result, "target_clan") + "§a.");
            });
            return;
        }

        if (sub.equals("accept") || sub.equals("принять") || sub.equals("deny") || sub.equals("отклонить")) {
            if (args.length < 3) {
                player.sendMessage("§7Использование: /clan war accept|deny <war-id>");
                return;
            }
            JsonObject body = new JsonObject();
            body.addProperty("p_user_id", userId(player));
            body.addProperty("p_war_id", args[2]);
            body.addProperty("p_action", (sub.equals("accept") || sub.equals("принять")) ? "ACCEPT" : "DECLINE");
            call(player, RpcNames.RESPOND_CLAN_WAR, body, result -> {
                if (!bool(result, "success")) {
                    player.sendMessage("§c" + humanClanWarError(error(result)));
                    return;
                }
                player.sendMessage(body.get("p_action").getAsString().equals("ACCEPT")
                    ? "§aВызов принят. Войну можно начать."
                    : "§eВызов отклонён.");
            });
            return;
        }

        if (sub.equals("start") || sub.equals("начать")) {
            if (args.length < 3) {
                player.sendMessage("§7Использование: /clan war start <war-id>");
                return;
            }
            JsonObject body = new JsonObject();
            body.addProperty("p_user_id", userId(player));
            body.addProperty("p_war_id", args[2]);
            call(player, RpcNames.START_CLAN_WAR, body, result -> {
                if (!bool(result, "success")) {
                    player.sendMessage("§c" + humanClanWarError(error(result)));
                    return;
                }
                player.sendMessage("§6Война началась.");
            });
            return;
        }

        if (sub.equals("finish") || sub.equals("завершить")) {
            if (args.length < 5) {
                player.sendMessage("§7Использование: /clan war finish <war-id> <счёт-A> <счёт-B>");
                return;
            }
            int scoreA;
            int scoreB;
            try {
                scoreA = Integer.parseInt(args[3]);
                scoreB = Integer.parseInt(args[4]);
            } catch (NumberFormatException ex) {
                player.sendMessage("§cСчёт должен быть целым числом.");
                return;
            }
            if (scoreA < 0 || scoreB < 0) {
                player.sendMessage("§cСчёт не может быть отрицательным.");
                return;
            }
            JsonObject body = new JsonObject();
            body.addProperty("p_user_id", userId(player));
            body.addProperty("p_war_id", args[2]);
            body.addProperty("p_score_a", scoreA);
            body.addProperty("p_score_b", scoreB);
            call(player, RpcNames.FINISH_CLAN_WAR, body, result -> {
                if (!bool(result, "success")) {
                    player.sendMessage("§c" + humanClanWarError(error(result)));
                    return;
                }
                player.sendMessage("§aВойна завершена со счётом §f" + scoreA + ":" + scoreB + "§a. Рейтинг кланов обновлён.");
            });
            return;
        }

        player.sendMessage("§7Использование: /clan war list|create|accept|deny|start|finish ...");
    }

    private static String warStatus(String status) {
        return switch (status) {
            case "pending" -> "Ожидает ответа";
            case "scheduled" -> "Принята";
            case "active" -> "Идёт";
            case "finished" -> "Завершена";
            case "cancelled" -> "Отменена";
            default -> status;
        };
    }

    private static String humanClanWarError(String code) {
        return switch (code) {
            case "NO_CLAN_PERMISSION" -> "Недостаточно прав в клане.";
            case "CLAN_NOT_FOUND" -> "Клан не найден.";
            case "WAR_ALREADY_ACTIVE" -> "У клана уже есть незавершённая война.";
            case "WAR_NOT_PENDING" -> "Вызов уже обработан.";
            case "WAR_NOT_SCHEDULED" -> "Война ещё не принята.";
            case "WAR_NOT_ACTIVE" -> "Активной войны с таким ID нет.";
            case "USE_DECLINE" -> "Для входящего вызова используйте отклонение.";
            case "INVALID_SCORE" -> "Счёт не может быть отрицательным.";
            case "WAR_NOT_FOUND" -> "Война не найдена.";
            default -> "Операция с войной не выполнена: " + code;
        };
    }

    private static String roleLabel(String role) {
        return switch (role) {
            case "co_owner" -> "Совладелец";
            case "officer" -> "Офицер";
            case "member" -> "Участник";
            case "recruit" -> "Рекрут";
            default -> role;
        };
    }

    private static String humanClanRoleError(String code) {
        return switch (code) {
            case "NO_CLAN_PERMISSION" -> "Недостаточно прав для изменения этой роли.";
            case "TARGET_NOT_IN_CLAN" -> "Игрок не состоит в вашем клане.";
            case "TARGET_INVALID_ROLE" -> "Нельзя назначить роль этого уровня или выше.";
            case "CANNOT_MANAGE_SELF" -> "Нельзя изменить собственную роль.";
            case "ROLE_UNCHANGED" -> "Эта роль уже установлена.";
            case "PLAYER_NOT_FOUND" -> "Игрок не найден.";
            default -> "Роль не изменена: " + code;
        };
    }

    private void home(Player player, String[] args) {
        String clanId = cache.clanOf(player.getUniqueId());
        if (clanId == null) { player.sendMessage("§cВы не состоите в клане."); return; }
        Village v = args.length >= 2 ? villages.byName(clanId, args[1]) : villages.forClan(clanId).stream().findFirst().orElse(null);
        if (v == null) { player.sendMessage("§cУ клана нет подходящего села."); return; }
        var world = Bukkit.getWorld(v.world());
        if (world == null) { player.sendMessage("§cМир села не загружен."); return; }
        var safe = world.getHighestBlockAt((int)Math.floor(v.centerX()), (int)Math.floor(v.centerZ())).getLocation().add(0.5,1,0.5);
        player.teleport(safe);
        player.sendMessage("§aВы прибыли в село §f" + v.name() + "§a.");
    }

    private void villageHelp(Player player) {
        player.sendMessage("§6§lVILLAGE");
        player.sendMessage("§7/village create <название> [радиус]");
        player.sendMessage("§7/village list/info/home");
        player.sendMessage("§7/village radius <название> <24-96>");
        player.sendMessage("§7/village delete <название>");
    }

    private void call(Player player, String rpc, JsonObject body, java.util.function.Consumer<JsonObject> callback) {
        supabase.postRpcAsync(rpc, body)
            .thenAccept(result -> run(() -> callback.accept(result)))
            .exceptionally(error -> {
                run(() -> player.sendMessage("§cОшибка связи с PRISMA: " + unwrap(error)));
                return null;
            });
    }

    private void run(Runnable task) { Bukkit.getScheduler().runTask(plugin, task); }

    private static String humanClanError(String code) {
        return switch (code) {
            case "NO_CLAN" -> "Вы не состоите в клане.";
            case "NO_CLAN_PERMISSION" -> "Недостаточно прав в клане.";
            case "PLAYER_NOT_FOUND" -> "Игрок не найден.";
            case "PLAYER_ALREADY_IN_CLAN" -> "Игрок уже состоит в клане.";
            case "CANNOT_INVITE_SELF" -> "Нельзя пригласить самого себя.";
            case "INVITE_ALREADY_EXISTS" -> "Этому игроку уже отправлено приглашение.";
            case "INVITE_NOT_FOUND" -> "Приглашение не найдено или уже недействительно.";
            case "TARGET_NOT_IN_CLAN" -> "Игрок не состоит в вашем клане.";
            case "CANNOT_KICK" -> "Этого игрока нельзя исключить.";
            case "TARGET_INVALID_ROLE" -> "Нельзя управлять ролью равного или более высокого уровня.";
            case "OWNER_ONLY" -> "Это действие доступно только владельцу клана.";
            case "PLAYER_ACCESS_REQUIRED" -> "Для этого действия нужен одобренный и допущенный к серверу аккаунт.";
            case "USER_NOT_ALLOWED" -> "Действие недоступно для этого аккаунта.";
            case "CLAN_NOT_OPEN" -> "Этот клан закрыт. Вступление доступно только по приглашению.";
            case "CLAN_NAME_TAKEN" -> "Такое название клана уже занято.";
            case "CLAN_TAG_TAKEN" -> "Такой тег клана уже занят.";
            default -> "Операция не выполнена: " + code;
        };
    }

    private static String error(JsonObject o) {
        if (o.has("error") && !o.get("error").isJsonNull()) return o.get("error").getAsString();
        return "неизвестная ошибка";
    }

    private static String unwrap(Throwable e) {
        Throwable x = e.getCause() == null ? e : e.getCause();
        return x.getMessage() == null ? "неизвестная ошибка" : x.getMessage();
    }

    private static boolean bool(JsonObject o, String key) {
        return o.has(key) && !o.get(key).isJsonNull() && o.get(key).getAsBoolean();
    }

    private static String stringField(JsonObject o, String key) {
        return o.has(key) && !o.get(key).isJsonNull() ? o.get(key).getAsString() : null;
    }

    private static String safe(JsonObject o, String key) {
        return stringField(o,key) == null ? "—" : stringField(o,key);
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length == 1) {
            return ALIASES.keySet().stream()
                .filter(k -> k.startsWith(args[0].toLowerCase(Locale.ROOT)))
                .sorted()
                .collect(Collectors.toList());
        }

        String first = args[0].toLowerCase(Locale.ROOT);
        if (first.equals("war") || first.equals("война") || first.equals("войны")) {
            if (args.length == 2) {
                return List.of("list", "create", "accept", "deny", "start", "finish").stream()
                    .filter(k -> k.startsWith(args[1].toLowerCase(Locale.ROOT)))
                    .collect(Collectors.toList());
            }
        }

        if (first.equals("role") || first.equals("роль") || first.equals("назначить")) {
            if (args.length == 3) {
                return List.of("совладелец", "офицер", "участник", "рекрут").stream()
                    .filter(k -> k.startsWith(args[2].toLowerCase(Locale.ROOT)))
                    .collect(Collectors.toList());
            }
        }

        return List.of();
    }
}
