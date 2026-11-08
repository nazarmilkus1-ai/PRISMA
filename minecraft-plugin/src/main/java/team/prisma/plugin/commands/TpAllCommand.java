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
import com.google.gson.JsonObject;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Подтверждаемая массовая телепортация для разрешённых ролей.
 * Перед подтверждением сохраняются UUID получателей и снимок точки назначения.
 */
public final class TpAllCommand implements CommandExecutor, TabCompleter {
    private static final long CONFIRMATION_WINDOW_MILLIS = 20_000L;

    private record PendingTeleport(
        Location destination,
        List<UUID> targetIds,
        long expiresAtMillis
    ) {}

    private final JavaPlugin plugin;
    private final PlayerStateCache cache;
    private final SupabaseClient supabase;
    private final Map<UUID, PendingTeleport> pending = new ConcurrentHashMap<>();

    public TpAllCommand(JavaPlugin plugin, PlayerStateCache cache, SupabaseClient supabase) {
        this.plugin = plugin;
        this.cache = cache;
        this.supabase = supabase;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам с разрешённой ролью.");
            return true;
        }
        if (!player.hasPermission("prisma.command.tpall")) {
            player.sendMessage("§cНедостаточно прав. /tpall доступна только администраторам и роли Content Maker.");
            return true;
        }
        if (args.length > 1) {
            usage(player);
            return true;
        }

        UUID actorId = player.getUniqueId();
        if (args.length == 1) {
            String action = args[0].toLowerCase(Locale.ROOT);
            if (action.equals("confirm")) {
                confirm(player);
                return true;
            }
            if (action.equals("cancel")) {
                cancel(player);
                return true;
            }
            usage(player);
            return true;
        }

        PendingTeleport existing = pending.get(actorId);
        if (existing != null && System.currentTimeMillis() < existing.expiresAtMillis()) {
            player.sendMessage("§eУ вас уже есть запрос /tpall. Подтвердите §f/tpall confirm §eили отмените §f/tpall cancel§e.");
            return true;
        }
        pending.remove(actorId);

        Location destination = player.getLocation().clone();
        List<UUID> targets = Bukkit.getOnlinePlayers().stream()
            .filter(target -> !target.getUniqueId().equals(actorId))
            .map(Player::getUniqueId)
            .toList();

        if (targets.isEmpty()) {
            player.sendMessage("§7Кроме вас, на сервере сейчас нет игроков для телепортации.");
            return true;
        }

        long expiresAt = System.currentTimeMillis() + CONFIRMATION_WINDOW_MILLIS;
        pending.put(actorId, new PendingTeleport(destination, targets, expiresAt));

        String worldName = destination.getWorld() == null ? "неизвестный мир" : destination.getWorld().getName();
        plugin.getLogger().info("[TPALL] Запрос: инициатор=" + player.getName()
            + ", uuid=" + actorId
            + ", получателей=" + targets.size()
            + ", мир=" + worldName
            + ", координаты=" + blockCoordinates(destination)
            + ", срок подтверждения=20 секунд");

        recordAudit(
            player.getName(),
            cache.userIdOf(actorId),
            "/tpall",
            "Запрошено подтверждение массовой телепортации.",
            worldName,
            targets.size(),
            -1,
            -1,
            "request"
        );

        player.sendMessage("§6§lPRISMA §7— §fПодтверждение /tpall");
        player.sendMessage("§eБудут перемещены §f" + targets.size()
            + " §eигроков в вашу текущую точку.");
        player.sendMessage("§7Мир: §f" + worldName + " §7· Координаты: §f" + blockCoordinates(destination));
        player.sendMessage("§cКоманда повлияет на других игроков и сменит им мир, если он отличается.");
        player.sendMessage("§aВведите §f/tpall confirm §aв течение 20 секунд.");
        player.sendMessage("§7Отмена: §f/tpall cancel");
        return true;
    }

    private void confirm(Player actor) {
        String actorName = actor.getName();
        UUID actorId = actor.getUniqueId();
        String actorUserId = cache.userIdOf(actorId);
        PendingTeleport request = pending.remove(actorId);
        if (request == null) {
            actor.sendMessage("§cНет ожидающего подтверждения. Сначала используйте §f/tpall§c.");
            return;
        }
        if (System.currentTimeMillis() > request.expiresAtMillis()) {
            actor.sendMessage("§cВремя подтверждения истекло. Запросите §f/tpall §cзаново.");
            plugin.getLogger().info("[TPALL] Истёк запрос: инициатор=" + actorName + ", uuid=" + actorId);
            recordAudit(actorName, actorUserId, "/tpall confirm", "Время подтверждения истекло.", null, 0, 0, 0, "expired");
            return;
        }
        if (!actor.hasPermission("prisma.command.tpall")) {
            actor.sendMessage("§cВаши права изменились. Телепортация отменена.");
            recordAudit(actorName, actorUserId, "/tpall confirm", "Разрешение отсутствует на момент подтверждения.", null, 0, 0, 0, "denied");
            return;
        }
        if (actorUserId == null || actorUserId.isBlank()) {
            actor.sendMessage("§cНе удалось подтвердить профиль PRISMA. Массовая телепортация отменена.");
            plugin.getLogger().warning("[TPALL] Отмена: профиль инициатора не синхронизирован; инициатор=" + actorName);
            return;
        }

        JsonObject identityRequest = new JsonObject();
        identityRequest.addProperty("p_user_id", actorUserId);
        actor.sendMessage("§7Проверяю актуальные права PRISMA перед выполнением...");
        try {
            supabase.postRpcAsync(RpcNames.GET_STAFF_IDENTITY, identityRequest)
                .whenComplete((identity, error) -> onMain(() -> {
                    if (!actor.isOnline()) return;
                    if (error != null || !authorizesTpAll(identity)) {
                        actor.sendMessage("§cАктуальные права не подтверждены. Телепортация отменена.");
                        plugin.getLogger().warning("[TPALL] Отмена: актуальная роль не подтверждена для " + actorName
                            + (error == null ? "" : " (" + error.getClass().getSimpleName() + ")"));
                        recordAudit(
                            actorName, actorUserId, "/tpall confirm",
                            "Актуальная роль не подтверждена; действие отменено.",
                            null, 0, 0, 0, "denied"
                        );
                        return;
                    }
                    if (!actor.hasPermission("prisma.command.tpall")) {
                        actor.sendMessage("§cВаше разрешение уже отозвано. Телепортация отменена.");
                        recordAudit(
                            actorName, actorUserId, "/tpall confirm",
                            "Разрешение отозвано до выполнения действия.",
                            null, 0, 0, 0, "denied"
                        );
                        return;
                    }
                    executeConfirmed(actor, actorName, actorId, actorUserId, request);
                }));
        } catch (RuntimeException error) {
            actor.sendMessage("§cНе удалось проверить права PRISMA. Телепортация отменена.");
            plugin.getLogger().warning("[TPALL] Не удалось запустить проверку роли для " + actorName
                + ": " + error.getClass().getSimpleName());
            recordAudit(
                actorName, actorUserId, "/tpall confirm",
                "Не удалось запустить проверку роли; действие отменено.",
                null, 0, 0, 0, "denied"
            );
        }
    }

    private boolean authorizesTpAll(JsonObject identity) {
        if (identity == null || identity.has("error")
            || !identity.has("role") || identity.get("role").isJsonNull()) {
            return false;
        }
        try {
            String role = identity.get("role").getAsString();
            if ("content_maker".equals(role) || "head_admin".equals(role) || "owner".equals(role)) {
                return true;
            }
            String branch = identity.has("branch") && !identity.get("branch").isJsonNull()
                ? identity.get("branch").getAsString() : "community";
            int priority = identity.has("priority") && !identity.get("priority").isJsonNull()
                ? identity.get("priority").getAsInt() : 0;
            return "admin".equals(role) && "moderation".equals(branch) && priority >= 60;
        } catch (RuntimeException error) {
            return false;
        }
    }

    private void executeConfirmed(
        Player actor,
        String actorName,
        UUID actorId,
        String actorUserId,
        PendingTeleport request
    ) {
        Location snapshot = request.destination();
        World previousWorld = snapshot.getWorld();
        World world = previousWorld == null ? null : Bukkit.getWorld(previousWorld.getUID());
        if (world == null || snapshot.getY() < world.getMinHeight() || snapshot.getY() >= world.getMaxHeight()) {
            actor.sendMessage("§cМир назначения больше недоступен. Телепортация отменена.");
            plugin.getLogger().warning("[TPALL] Отмена: мир назначения недоступен; инициатор=" + actorName);
            recordAudit(actorName, actorUserId, "/tpall confirm", "Мир назначения недоступен; телепортация отменена.", null, 0, 0, 0, "aborted");
            return;
        }

        Location destination = new Location(
            world, snapshot.getX(), snapshot.getY(), snapshot.getZ(), snapshot.getYaw(), snapshot.getPitch()
        );
        List<Player> targets = new ArrayList<>();
        for (UUID targetId : request.targetIds()) {
            Player target = Bukkit.getPlayer(targetId);
            if (target != null && target.isOnline() && !target.getUniqueId().equals(actorId)) {
                targets.add(target);
            }
        }
        if (targets.isEmpty()) {
            actor.sendMessage("§7Игроки из подтверждённого списка уже вышли. Никто не перемещён.");
            plugin.getLogger().info("[TPALL] Нет активных получателей: инициатор=" + actorName);
            recordAudit(actorName, actorUserId, "/tpall confirm", "Игроки из подтверждённого списка вышли; перемещение не выполнено.", world.getName(), 0, 0, 0, "empty");
            return;
        }

        List<String> targetNames = targets.stream().map(Player::getName).toList();
        String worldName = world.getName();
        plugin.getLogger().info("[TPALL] Подтверждено: инициатор=" + actorName
            + ", uuid=" + actorId
            + ", получатели=" + String.join(",", targetNames)
            + ", мир=" + worldName
            + ", координаты=" + blockCoordinates(destination));

        recordAudit(
            actorName,
            actorUserId,
            "/tpall confirm",
            "Массовая телепортация запущена; получатели=" + String.join(", ", targetNames),
            worldName,
            targets.size(),
            -1,
            -1,
            "started"
        );

        actor.sendMessage("§7Телепортация " + targets.size() + " игроков началась...");

        List<CompletableFuture<Boolean>> outcomes = new ArrayList<>();
        for (Player target : targets) {
            try {
                CompletableFuture<Boolean> outcome = target.teleportAsync(destination.clone())
                    .handle((success, error) -> error == null && Boolean.TRUE.equals(success));
                outcomes.add(outcome);
            } catch (RuntimeException error) {
                plugin.getLogger().warning("[TPALL] Не удалось запустить телепортацию для "
                    + target.getName() + ": " + error.getClass().getSimpleName());
                outcomes.add(CompletableFuture.completedFuture(false));
            }
        }

        CompletableFuture.allOf(outcomes.toArray(CompletableFuture[]::new)).whenComplete((ignored, error) -> {
            int succeeded = (int) outcomes.stream()
                .filter(outcome -> Boolean.TRUE.equals(outcome.getNow(false)))
                .count();
            int failed = outcomes.size() - succeeded;

            plugin.getLogger().info("[TPALL] Результат: инициатор=" + actorName
                + ", успешно=" + succeeded + ", ошибок=" + failed
                + ", всего=" + outcomes.size());

            recordAudit(
                actorName,
                actorUserId,
                "/tpall confirm",
                "Массовая телепортация завершена.",
                worldName,
                outcomes.size(),
                succeeded,
                failed,
                "result"
            );

            onMain(() -> {
                if (!actor.isOnline()) return;
                if (failed == 0) {
                    actor.sendMessage("§aТелепортация завершена: §f" + succeeded + " §aигроков.");
                } else {
                    actor.sendMessage("§eТелепортация завершена: §a" + succeeded
                        + " успешно§e, §c" + failed + " не удалось§e. Подробности записаны в журнал.");
                }
            });
        });
    }

    private void cancel(Player player) {
        PendingTeleport removed = pending.remove(player.getUniqueId());
        if (removed == null) {
            player.sendMessage("§7Нет ожидающего запроса /tpall.");
            return;
        }
        plugin.getLogger().info("[TPALL] Отменено: инициатор=" + player.getName()
            + ", uuid=" + player.getUniqueId());
        recordAudit(
            player.getName(),
            cache.userIdOf(player.getUniqueId()),
            "/tpall cancel",
            "Запрос массовой телепортации отменён.",
            null,
            removed.targetIds().size(),
            0,
            0,
            "cancelled"
        );
        player.sendMessage("§eЗапрос /tpall отменён. Игроки не перемещены.");
    }

    private void recordAudit(
        String actorName,
        String userId,
        String commandName,
        String message,
        String world,
        int targetCount,
        int succeeded,
        int failed,
        String stage
    ) {
        if (userId == null || userId.isBlank()) {
            plugin.getLogger().warning("[TPALL] Событие аудита не записано в Supabase: профиль инициатора не синхронизирован.");
            return;
        }

        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_event_type", "COMMAND");
        body.addProperty("p_nickname", actorName);
        body.addProperty("p_command", commandName);
        body.addProperty("p_message", message.length() > 2000 ? message.substring(0, 2000) : message);
        if (world != null && !world.isBlank()) body.addProperty("p_world", world);

        JsonObject metadata = new JsonObject();
        metadata.addProperty("action", "TPALL");
        metadata.addProperty("stage", stage);
        metadata.addProperty("target_count", targetCount);
        metadata.addProperty("succeeded", succeeded);
        metadata.addProperty("failed", failed);
        body.add("p_metadata", metadata);

        supabase.postRpcAsync(RpcNames.RECORD_MINECRAFT_EVENT, body).exceptionally(error -> {
            plugin.getLogger().warning("[TPALL] Не удалось сохранить событие аудита для "
                + actorName + ": " + error.getClass().getSimpleName());
            return null;
        });
    }

    private void onMain(Runnable task) {
        if (!plugin.isEnabled()) return;
        try {
            Bukkit.getScheduler().runTask(plugin, task);
        } catch (RuntimeException ignored) {
            // Сервер уже завершает работу; не выполняем Bukkit-действия после выключения плагина.
        }
    }

    private static String blockCoordinates(Location location) {
        return (int) Math.floor(location.getX()) + " "
            + (int) Math.floor(location.getY()) + " "
            + (int) Math.floor(location.getZ());
    }

    private static void usage(CommandSender sender) {
        sender.sendMessage("§7Использование: /tpall, затем /tpall confirm или /tpall cancel.");
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length != 1 || !(sender instanceof Player player)
            || !player.hasPermission("prisma.command.tpall")) {
            return List.of();
        }
        String prefix = args[0].toLowerCase(Locale.ROOT);
        return List.of("confirm", "cancel").stream().filter(value -> value.startsWith(prefix)).toList();
    }
}
