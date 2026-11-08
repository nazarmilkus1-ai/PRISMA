package team.prisma.plugin.commands;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import net.kyori.adventure.text.Component;
import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.command.PluginCommand;
import org.bukkit.command.TabCompleter;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerCommandPreprocessEvent;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.logging.Level;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Player-facing moderation command bridge. All mutations and hierarchy checks happen
 * in service-role-only Supabase RPCs, not in this command's cached Bukkit permissions.
 */
public final class ModerationCommand implements CommandExecutor, TabCompleter, Listener {
    private static final int MAX_REASON_LENGTH = 500;
    private static final int MAX_DURATION_MINUTES = 43_200;
    private static final Pattern DURATION_PATTERN = Pattern.compile("^(\\d{1,5})([mhd])?$", Pattern.CASE_INSENSITIVE);
    private static final DateTimeFormatter HISTORY_TIME =
        DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm").withZone(ZoneId.systemDefault());

    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;

    public ModerationCommand(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player actor)) {
            sender.sendMessage("Эта команда доступна только персоналу Minecraft.");
            return true;
        }
        if (!actor.hasPermission("prisma.command.moderation")) {
            actor.sendMessage("§cУ вашей роли нет доступа к игровым командам модерации.");
            return true;
        }

        String actorUserId = cache.userIdOf(actor.getUniqueId());
        if (actorUserId == null || actorUserId.isBlank()) {
            actor.sendMessage("§cПрофиль PRISMA ещё не синхронизирован. Наказание не отправлено.");
            return true;
        }

        String action = command.getName().toLowerCase(Locale.ROOT);
        if ("history".equals(action)) {
            showHistory(actor, actorUserId, args);
            return true;
        }

        Request request;
        try {
            request = parse(action, args);
        } catch (IllegalArgumentException error) {
            actor.sendMessage("§c" + error.getMessage());
            return true;
        }

        if ("KICK".equals(request.actionType()) && onlinePlayer(request.target()) == null) {
            actor.sendMessage("§cКоманда /kick доступна только для игрока, который сейчас в сети.");
            return true;
        }

        actor.sendMessage("§7Проверяю права PRISMA и отправляю модерационное действие...");
        JsonObject body = new JsonObject();
        body.addProperty("p_actor_user_id", actorUserId);
        body.addProperty("p_target_nickname", request.target());

        String rpc;
        if (request.actionType().equals("UNMUTE") || request.actionType().equals("UNBAN")) {
            rpc = RpcNames.MC_STAFF_LIFT_MODERATION;
            body.addProperty("p_action", request.actionType());
        } else {
            rpc = RpcNames.MC_STAFF_APPLY_MODERATION;
            body.addProperty("p_type", request.actionType());
            body.addProperty("p_reason", request.reason());
            if (request.durationMinutes() != null) {
                body.addProperty("p_duration_minutes", request.durationMinutes());
            }
        }

        try {
            supabase.postRpcAsync(rpc, body).whenComplete((result, error) ->
                onMain(() -> completeMutation(actor, request, result, error)));
        } catch (RuntimeException error) {
            plugin.getLogger().log(Level.WARNING, "[Moderation] RPC could not start for " + actor.getName(), error);
            actor.sendMessage("§cНе удалось запустить проверку. Наказание не применено.");
        }
        return true;
    }

    private Request parse(String action, String[] args) {
        return switch (action) {
            case "warn" -> {
                requireAtLeast(args, 2, "Использование: /warn <ник> <причина>");
                yield new Request(action, target(args[0]), "WARN", reason(args, 1), null);
            }
            case "mute" -> {
                requireAtLeast(args, 3, "Использование: /mute <ник> <длительность|perm> <причина>");
                Integer duration = parseOptionalDuration(args[1]);
                yield new Request(action, target(args[0]), "MUTE", reason(args, 2), duration);
            }
            case "kick" -> {
                requireAtLeast(args, 2, "Использование: /kick <ник> <причина>");
                yield new Request(action, target(args[0]), "KICK", reason(args, 1), null);
            }
            case "ban" -> {
                requireAtLeast(args, 2, "Использование: /ban <ник> <причина>");
                yield new Request(action, target(args[0]), "BAN", reason(args, 1), null);
            }
            case "tempban" -> {
                requireAtLeast(args, 3, "Использование: /tempban <ник> <длительность> <причина>");
                Integer duration = parseRequiredDuration(args[1]);
                yield new Request(action, target(args[0]), "BAN", reason(args, 2), duration);
            }
            case "unmute" -> {
                requireExactly(args, 1, "Использование: /unmute <ник>");
                yield new Request(action, target(args[0]), "UNMUTE", null, null);
            }
            case "unban" -> {
                requireExactly(args, 1, "Использование: /unban <ник>");
                yield new Request(action, target(args[0]), "UNBAN", null, null);
            }
            default -> throw new IllegalArgumentException("Неизвестная команда модерации.");
        };
    }

    private void completeMutation(Player actor, Request request, JsonObject result, Throwable error) {
        if (error != null) {
            String detail = rootMessage(error);
            plugin.getLogger().log(Level.WARNING,
                "[Moderation] " + request.action() + " -> " + request.target() + " failed: " + detail);
            if (actor.isOnline()) actor.sendMessage("§c" + friendlyError(detail));
            return;
        }
        if (result == null || result.has("error")
            || (result.has("success") && !result.get("success").isJsonNull()
                && !result.get("success").getAsBoolean())) {
            String detail = result == null ? "EMPTY_RESPONSE" : result.toString();
            plugin.getLogger().warning("[Moderation] RPC returned an unexpected response: " + detail);
            if (actor.isOnline()) actor.sendMessage("§cДействие не подтверждено сервером БД. Ничего не изменено.");
            return;
        }

        String targetName = stringField(result, "target_minecraft_nickname", request.target());
        Player target = Bukkit.getPlayerExact(targetName);
        Instant expiry = instantField(result, "expires_at");

        switch (request.actionType()) {
            case "WARN" -> {
                if (target != null && target.isOnline()) {
                    target.sendMessage(Component.text("Вы получили предупреждение PRISMA. Причина: " + request.reason()));
                }
            }
            case "MUTE" -> {
                if (target != null && target.isOnline()) {
                    cache.setMuted(target.getUniqueId(), expiry);
                    target.sendMessage(Component.text(expiry == null
                        ? "Вам выдан постоянный мут PRISMA. Причина: " + request.reason()
                        : "Вам выдан мут PRISMA до " + expiry + ". Причина: " + request.reason()));
                }
            }
            case "KICK" -> {
                if (target != null && target.isOnline()) {
                    target.kick(Component.text("Вы исключены с сервера PRISMA. Причина: " + request.reason()));
                }
            }
            case "BAN" -> {
                if (target != null && target.isOnline()) {
                    String message = expiry == null
                        ? "Вы забанены на сервере PRISMA. Причина: " + request.reason()
                        : "Вы временно забанены на сервере PRISMA до " + expiry + ". Причина: " + request.reason();
                    target.kick(Component.text(message));
                }
            }
            case "UNMUTE" -> {
                if (target != null) {
                    cache.unmute(target.getUniqueId());
                    if (target.isOnline()) target.sendMessage(Component.text("С вас снят мут PRISMA."));
                }
            }
            case "UNBAN" -> {
                if (target != null && target.isOnline()) {
                    target.sendMessage(Component.text("Ограничение PRISMA по бану снято."));
                }
            }
            default -> plugin.getLogger().warning("[Moderation] Unexpected action type " + request.actionType());
        }

        if (actor.isOnline()) {
            String id = stringField(result, "moderation_log_id", stringField(result, "revoked", ""));
            if (id.isBlank()) id = stringField(result, "moderation_action_id", "");
            actor.sendMessage("§aМодерационное действие подтверждено для §f" + targetName
                + (id.isBlank() ? "." : " §7(ID §f" + id + "§7)."));
        }
    }

    private void showHistory(Player actor, String actorUserId, String[] args) {
        if (args.length != 1 || !validTarget(args[0])) {
            actor.sendMessage("§7Использование: /history <ник>");
            return;
        }
        JsonObject body = new JsonObject();
        body.addProperty("p_actor_user_id", actorUserId);
        body.addProperty("p_target_nickname", args[0]);
        body.addProperty("p_limit", 10);
        actor.sendMessage("§7Загружаю историю наказаний...");
        try {
            supabase.postRpcAsync(RpcNames.MC_STAFF_MODERATION_HISTORY, body)
                .whenComplete((result, error) -> onMain(() -> {
                    if (!actor.isOnline()) return;
                    if (error != null || result == null || result.has("error")) {
                        String detail = error == null ? String.valueOf(result) : rootMessage(error);
                        plugin.getLogger().warning("[Moderation] history lookup failed: " + detail);
                        actor.sendMessage("§cНе удалось получить историю. Проверьте право punishment.view_history и точность ника.");
                        return;
                    }
                    JsonObject target = result.has("target") && result.get("target").isJsonObject()
                        ? result.getAsJsonObject("target") : new JsonObject();
                    String nickname = stringField(target, "minecraft_nickname", args[0]);
                    JsonArray logs = result.has("logs") && result.get("logs").isJsonArray()
                        ? result.getAsJsonArray("logs") : new JsonArray();
                    actor.sendMessage("§6§lИстория PRISMA: §f" + nickname);
                    if (logs.isEmpty()) {
                        actor.sendMessage("§7Записей о наказаниях нет.");
                        return;
                    }
                    for (JsonElement element : logs) {
                        if (!element.isJsonObject()) continue;
                        JsonObject row = element.getAsJsonObject();
                        String type = stringField(row, "type", "UNKNOWN");
                        String status = stringField(row, "status", "UNKNOWN");
                        boolean revoked = booleanField(row, "revoked");
                        String reason = safeText(stringField(row, "reason", "Причина не указана"), 90);
                        String issuer = safeText(stringField(row, "issued_by_name", "неизвестно"), 24);
                        String date = formatDate(stringField(row, "created_at", null));
                        String duration = durationLabel(row);
                        actor.sendMessage("§e" + date + " §f" + type + " §7[" + status + (revoked ? ", снято" : "") + "]");
                        actor.sendMessage(" §7" + reason + " §8| §7кем: §f" + issuer + duration);
                    }
                }));
        } catch (RuntimeException error) {
            plugin.getLogger().log(Level.WARNING, "[Moderation] history lookup could not start", error);
            actor.sendMessage("§cНе удалось запустить запрос истории.");
        }
    }

    private static String durationLabel(JsonObject row) {
        if (row.has("duration_minutes") && !row.get("duration_minutes").isJsonNull()) {
            try {
                long minutes = row.get("duration_minutes").getAsLong();
                return " §8| §7срок: §f" + formatMinutes(minutes);
            } catch (RuntimeException ignored) {
                return "";
            }
        }
        String expiry = stringField(row, "expires_at", null);
        return expiry == null ? " §8| §7срок: §fпостоянно" : " §8| §7до: §f" + formatDate(expiry);
    }

    private static String formatMinutes(long minutes) {
        if (minutes >= 1440 && minutes % 1440 == 0) return (minutes / 1440) + " д.";
        if (minutes >= 60 && minutes % 60 == 0) return (minutes / 60) + " ч.";
        return minutes + " мин.";
    }

    private static String formatDate(String raw) {
        if (raw == null || raw.isBlank()) return "дата неизвестна";
        try {
            return HISTORY_TIME.format(Instant.parse(raw));
        } catch (RuntimeException ignored) {
            try {
                return HISTORY_TIME.format(OffsetDateTime.parse(raw).toInstant());
            } catch (RuntimeException alsoIgnored) {
                return "дата неизвестна";
            }
        }
    }

    private static Integer parseOptionalDuration(String raw) {
        if ("perm".equalsIgnoreCase(raw) || "permanent".equalsIgnoreCase(raw) || "навсегда".equalsIgnoreCase(raw)) {
            return null;
        }
        return parseRequiredDuration(raw);
    }

    private static Integer parseRequiredDuration(String raw) {
        Matcher matcher = DURATION_PATTERN.matcher(raw == null ? "" : raw.trim());
        if (!matcher.matches()) {
            throw new IllegalArgumentException("Длительность задаётся как 30m, 2h или 7d; число без суффикса — минуты.");
        }
        long amount;
        try {
            amount = Long.parseLong(matcher.group(1));
        } catch (NumberFormatException error) {
            throw new IllegalArgumentException("Неверная длительность.");
        }
        String unit = matcher.group(2) == null ? "m" : matcher.group(2).toLowerCase(Locale.ROOT);
        long minutes = switch (unit) {
            case "h" -> amount * 60L;
            case "d" -> amount * 1440L;
            default -> amount;
        };
        if (minutes < 1L || minutes > MAX_DURATION_MINUTES) {
            throw new IllegalArgumentException("Длительность должна быть от 1 минуты до 30 дней.");
        }
        return (int) minutes;
    }

    private static String reason(String[] args, int from) {
        String value = String.join(" ", Arrays.copyOfRange(args, from, args.length)).trim();
        if (value.isEmpty()) throw new IllegalArgumentException("Укажите причину наказания.");
        if (value.length() > MAX_REASON_LENGTH) throw new IllegalArgumentException("Причина не должна превышать 500 символов.");
        return value;
    }

    private static String target(String raw) {
        if (!validTarget(raw)) throw new IllegalArgumentException("Укажите корректный ник игрока.");
        return raw.trim();
    }

    private static boolean validTarget(String raw) {
        return raw != null && !raw.isBlank() && raw.length() <= 64 && !raw.chars().anyMatch(Character::isWhitespace);
    }

    private static void requireAtLeast(String[] args, int count, String message) {
        if (args.length < count) throw new IllegalArgumentException(message);
    }

    private static void requireExactly(String[] args, int count, String message) {
        if (args.length != count) throw new IllegalArgumentException(message);
    }

    private static String friendlyError(String detail) {
        String normalized = detail == null ? "" : detail.toUpperCase(Locale.ROOT);
        if (normalized.contains("PERMISSION_DENIED") || normalized.contains("ADMIN_LACKS_PERMISSION")) {
            return "У вашей роли нет нужного права на это действие.";
        }
        if (normalized.contains("STAFF_HIERARCHY_FORBIDS")) {
            return "Нельзя применять это действие к сотруднику равного или более высокого уровня.";
        }
        if (normalized.contains("SELF_PUNISHMENT_FORBIDDEN")) {
            return "Нельзя применять наказание к самому себе.";
        }
        if (normalized.contains("TARGET_NOT_FOUND") || normalized.contains("USER_NOT_FOUND")) {
            return "Ник не найден в профилях PRISMA. Проверьте написание и привязку аккаунта.";
        }
        if (normalized.contains("TARGET_NICKNAME_AMBIGUOUS")) {
            return "Ник связан более чем с одним профилем. Обратитесь к владельцу.";
        }
        if (normalized.contains("NO_ACTIVE_PUNISHMENT")) {
            return "У игрока нет активного наказания этого типа.";
        }
        if (normalized.contains("INVALID_DURATION")) {
            return "Неверная длительность. Используйте 30m, 2h или 7d (до 30 дней).";
        }
        if (normalized.contains("INVALID_REASON")) {
            return "Причина должна содержать от 1 до 500 символов.";
        }
        return "Не удалось завершить действие. Проверьте доступность Supabase и серверный журнал.";
    }

    private static String rootMessage(Throwable error) {
        Throwable current = error;
        while (current.getCause() != null && current.getCause() != current) current = current.getCause();
        return current.getMessage() == null ? current.getClass().getSimpleName() : current.getMessage();
    }

    private static String stringField(JsonObject object, String key, String fallback) {
        return object != null && object.has(key) && !object.get(key).isJsonNull()
            ? object.get(key).getAsString() : fallback;
    }

    private static Instant instantField(JsonObject object, String key) {
        String raw = stringField(object, key, null);
        if (raw == null || raw.isBlank()) return null;
        try {
            return Instant.parse(raw);
        } catch (RuntimeException ignored) {
            try {
                return OffsetDateTime.parse(raw).toInstant();
            } catch (RuntimeException alsoIgnored) {
                return null;
            }
        }
    }

    private static boolean booleanField(JsonObject object, String key) {
        try {
            return object.has(key) && !object.get(key).isJsonNull() && object.get(key).getAsBoolean();
        } catch (RuntimeException ignored) {
            return false;
        }
    }

    private static String safeText(String value, int maxLength) {
        if (value == null || value.isBlank()) return "—";
        String normalized = value.replaceAll("[\\p{Cntrl}]", " ").replace('§', ' ');
        normalized = normalized.replaceAll("\\s+", " ").trim();
        return normalized.length() <= maxLength ? normalized : normalized.substring(0, maxLength - 1) + "…";
    }

    /**
     * Bukkit may retain the vanilla /ban or /kick dispatcher when a plugin command has
     * the same label. Intercept player commands before that dispatcher and route them
     * to PRISMA's RBAC-checked command handler.
     */
    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void interceptPlayerCommands(PlayerCommandPreprocessEvent event) {
        String message = event.getMessage();
        if (message == null || message.length() < 2 || message.charAt(0) != '/') return;
        String[] tokens = message.substring(1).trim().split("\\s+");
        if (tokens.length == 0) return;
        String invoked = tokens[0].toLowerCase(Locale.ROOT);
        int namespaceSeparator = invoked.indexOf(':');
        if (namespaceSeparator >= 0) invoked = invoked.substring(namespaceSeparator + 1);
        if (!List.of("warn", "mute", "unmute", "kick", "ban", "tempban", "unban", "history").contains(invoked)) return;

        PluginCommand pluginCommand = plugin.getCommand(invoked);
        if (pluginCommand == null) return;

        event.setCancelled(true);
        String[] args = Arrays.copyOfRange(tokens, 1, tokens.length);
        onCommand(event.getPlayer(), pluginCommand, invoked, args);
    }

    private static Player onlinePlayer(String nickname) {
        if (nickname == null) return null;
        for (Player player : Bukkit.getOnlinePlayers()) {
            if (player.getName().equalsIgnoreCase(nickname)) return player;
        }
        return null;
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        String root = command.getName().toLowerCase(Locale.ROOT);
        if (args.length == 1 && !root.equals("unmute") && !root.equals("unban")) {
            String prefix = args[0].toLowerCase(Locale.ROOT);
            return Bukkit.getOnlinePlayers().stream().map(Player::getName)
                .filter(name -> name.toLowerCase(Locale.ROOT).startsWith(prefix))
                .sorted().toList();
        }
        if (args.length == 2 && root.equals("mute")) {
            String prefix = args[1].toLowerCase(Locale.ROOT);
            return List.of("10m", "1h", "1d", "perm").stream()
                .filter(value -> value.startsWith(prefix.toLowerCase(Locale.ROOT))).toList();
        }
        if (args.length == 2 && root.equals("tempban")) {
            String prefix = args[1].toLowerCase(Locale.ROOT);
            return List.of("10m", "1h", "1d", "7d", "30d").stream()
                .filter(value -> value.startsWith(prefix)).toList();
        }
        if (args.length == 1 && (root.equals("unmute") || root.equals("unban"))) {
            String prefix = args[0].toLowerCase(Locale.ROOT);
            return Bukkit.getOnlinePlayers().stream().map(Player::getName)
                .filter(name -> name.toLowerCase(Locale.ROOT).startsWith(prefix))
                .sorted().toList();
        }
        return List.of();
    }

    private void onMain(Runnable action) {
        if (!plugin.isEnabled()) return;
        if (Bukkit.isPrimaryThread()) {
            action.run();
        } else {
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (plugin.isEnabled()) action.run();
            });
        }
    }

    private record Request(
        String action,
        String target,
        String actionType,
        String reason,
        Integer durationMinutes
    ) {}
}
