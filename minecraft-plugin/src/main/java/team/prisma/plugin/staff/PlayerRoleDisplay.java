package team.prisma.plugin.staff;

import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.permissions.PermissionAttachment;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

public final class PlayerRoleDisplay {
    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final Map<UUID, Identity> identities = new ConcurrentHashMap<>();
    private final Map<UUID, PermissionAttachment> attachments = new ConcurrentHashMap<>();

    public PlayerRoleDisplay(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
    }

    public void start() {
        refreshAll();
        Bukkit.getScheduler().runTaskTimer(plugin, this::refreshAll, 20L * 10L, 20L * 10L);
    }

    public void refresh(Player player) {
        UUID playerUuid = player.getUniqueId();
        String userId = cache.userIdOf(playerUuid);
        if (userId == null) {
            applyOnlinePlayer(playerUuid, Identity.participant());
            return;
        }

        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        supabase.postRpcAsync(RpcNames.GET_STAFF_IDENTITY, body)
            .thenAccept(result -> {
                Identity identity = Identity.from(result);
                identities.put(playerUuid, identity);
                applyOnlinePlayer(playerUuid, identity);
            })
            .exceptionally(error -> {
                identities.put(playerUuid, Identity.participant());
                applyOnlinePlayer(playerUuid, Identity.participant());
                return null;
            });
    }

    private void applyOnlinePlayer(UUID playerUuid, Identity identity) {
        Runnable action = () -> {
            Player online = Bukkit.getPlayer(playerUuid);
            if (online != null && online.isOnline()) apply(online, identity);
        };
        if (Bukkit.isPrimaryThread()) {
            action.run();
        } else {
            Bukkit.getScheduler().runTask(plugin, action);
        }
    }

    private void refreshAll() {
        for (Player player : Bukkit.getOnlinePlayers()) refresh(player);
    }

    private void apply(Player player, Identity identity) {
        if (!player.isOnline()) return;

        String decorated = identity.prefix() + player.getName() + "§r";
        player.setDisplayName(decorated);
        player.setPlayerListName(decorated);
        player.setCustomName(decorated);
        player.setCustomNameVisible(true);

        PermissionAttachment attachment = attachments.computeIfAbsent(
            player.getUniqueId(), ignored -> player.addAttachment(plugin)
        );
        for (String node : ROLE_PERMISSION_NODES) {
            attachment.setPermission(node, identity.hasPermission(node));
        }
    }

    public String role(UUID playerUuid) {
        return identities.getOrDefault(playerUuid, Identity.participant()).role();
    }

    public void clear(UUID playerUuid) {
        identities.remove(playerUuid);
        PermissionAttachment attachment = attachments.remove(playerUuid);
        Player player = Bukkit.getPlayer(playerUuid);
        if (attachment != null && player != null) player.removeAttachment(attachment);
    }

    private static final String[] ROLE_PERMISSION_NODES = {
        "prisma.member",
        "prisma.command.clan",
        "prisma.command.village",
        "prisma.command.homes",
        "prisma.command.spawns",
        "prisma.command.spawnmanage",
        "prisma.command.journey",
        "prisma.command.menu",
        "prisma.command.hud",
        "prisma.command.moderation",
        "prisma.command.grave",
        "prisma.command.grave.admin",
        "prisma.command.tpall",
        "prisma.staff.content_maker",
        "prisma.command.tpa",
        "prisma.command.tpaccept",
        "prisma.command.tpdeny",
        "prisma.command.commands",
        "prisma.command.ptp",
        "prisma.command.ptphere",
        "prisma.staff",
        "prisma.staff.helper",
        "prisma.staff.moderator",
        "prisma.staff.senior_moderator",
        "prisma.staff.admin",
        "prisma.staff.head_staff",
        "prisma.staff.head_admin",
        "prisma.staff.owner",
        "prisma.staff.developer",
        "prisma.staff.builder",
        "prisma.staff.game_designer",
        "prisma.staff.event_manager",
        "prisma.staff.media"
    };

    private record Identity(String role, String branch, int priority, String prefix) {
        boolean hasPermission(String node) {
            return switch (node) {
                case "prisma.member",
                "prisma.command.clan",
                "prisma.command.village",
                "prisma.command.homes",
                "prisma.command.spawns",
                "prisma.command.journey",
                "prisma.command.menu",
                "prisma.command.hud",
                "prisma.command.grave",
                "prisma.command.tpa",
                "prisma.command.tpaccept",
                "prisma.command.tpdeny",
                "prisma.command.commands" -> true;

                case "prisma.command.ptp", "prisma.command.ptphere",
                     "prisma.staff" -> isModerationStaff();

                case "prisma.command.moderation" -> isModerationStaff()
                    || "head_admin".equals(role)
                    || "owner".equals(role);

                case "prisma.command.spawnmanage" ->
                    "owner".equals(role)
                    || "head_admin".equals(role)
                    || ("moderation".equals(branch) && priority >= 60);

                case "prisma.command.grave.admin" ->
                    ("admin".equals(role) && "moderation".equals(branch) && priority >= 60)
                    || "head_admin".equals(role)
                    || "owner".equals(role);

                case "prisma.command.tpall" ->
                    ("admin".equals(role) && "moderation".equals(branch) && priority >= 60)
                    || "head_admin".equals(role)
                    || "owner".equals(role)
                    || "content_maker".equals(role);

                case "prisma.staff.helper" -> isModerationStaff();
                case "prisma.staff.moderator" -> isModerationStaff() && priority >= 40;
                case "prisma.staff.senior_moderator" -> "senior_moderator".equals(role) || priority >= 50 && "moderation".equals(branch);
                case "prisma.staff.admin" -> isModerationStaff() && priority >= 60;
                case "prisma.staff.head_staff" -> "head_staff".equals(role);
                case "prisma.staff.head_admin" -> "head_admin".equals(role) || "owner".equals(role);
                case "prisma.staff.owner" -> "owner".equals(role);

                case "prisma.staff.developer" -> "developer".equals(role);
                case "prisma.staff.builder" -> "builder".equals(role);
                case "prisma.staff.game_designer" -> "game_designer".equals(role);
                case "prisma.staff.event_manager" -> "event_manager".equals(role);
                case "prisma.staff.media" -> "media".equals(role);
                case "prisma.staff.content_maker" -> "content_maker".equals(role);

                default -> false;
            };
        }

        private boolean isModerationStaff() {
            return "moderation".equals(branch) && priority >= 30;
        }

        static Identity participant() {
            return new Identity("participant", "community", 0, "§7[УЧ] §f");
        }

        static Identity from(JsonObject result) {
            String role = result.has("role") && !result.get("role").isJsonNull()
                ? result.get("role").getAsString() : "participant";
            String branch = result.has("branch") && !result.get("branch").isJsonNull()
                ? result.get("branch").getAsString() : "community";
            int priority = result.has("priority") && !result.get("priority").isJsonNull()
                ? result.get("priority").getAsInt() : 0;
            return new Identity(role, branch, priority, prefixFor(role));
        }

        private static String prefixFor(String role) {
            return switch (role) {
                case "helper" -> "§a[ХЕЛП] §f";
                case "moderator" -> "§2[МДР] §f";
                case "senior_moderator" -> "§3[СМДР] §f";
                case "admin" -> "§6[АДМ] §f";
                case "head_staff" -> "§c[ГС] §f";
                case "head_admin" -> "§d[ГА] §f";
                case "owner" -> "§4[ВЛД] §f";
                case "developer" -> "§b[ТЕХ] §f";
                case "builder" -> "§e[СТР] §f";
                case "game_designer" -> "§9[ГД] §f";
                case "event_manager" -> "§a[ИВТ] §f";
                case "media" -> "§5[МЕД] §f";
                case "content_maker" -> "§5[КМ] §f";
                default -> "§7[УЧ] §f";
            };
        }
    }
}
