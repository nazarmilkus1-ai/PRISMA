package team.prisma.plugin.listeners;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.AsyncPlayerPreLoginEvent;
import org.bukkit.event.player.AsyncPlayerPreLoginEvent.Result;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.auth.FloodgateSupport;
import team.prisma.plugin.cache.PlayerStateCache;

import java.util.UUID;

import java.util.logging.Logger;

public final class WhitelistListener implements Listener {

    private final SupabaseClient supabase;
    private final Logger log;
    private final PlayerStateCache cache;

    public WhitelistListener(SupabaseClient supabase, Logger log, PlayerStateCache cache) {
        this.supabase = supabase;
        this.log = log;
        this.cache = cache;
    }

    @EventHandler
    public void onPreLogin(AsyncPlayerPreLoginEvent event) {
        String nickname = event.getName();
        UUID playerUuid = event.getUniqueId();
        boolean bedrock = FloodgateSupport.isBedrockPlayer(playerUuid);

        try {
            JsonObject lookup = new JsonObject();
            lookup.addProperty("p_nickname", nickname);
            lookup.addProperty("p_minecraft_uuid", playerUuid.toString());
            JsonObject user = supabase.postRpcSync(RpcNames.GET_MINECRAFT_USER_V2, lookup);

            String lookupError = textOrNull(user, "error");
            if (lookupError != null) {
                String message = switch (lookupError) {
                    case "USER_NOT_FOUND" -> "§cВы не подавали заявку.";
                    case "MINECRAFT_UUID_MISMATCH" -> "§cЭтот Minecraft-аккаунт не совпадает с закреплённой личностью.";
                    case "INVALID_MINECRAFT_NICK", "INVALID_MINECRAFT_UUID" -> "§cНе удалось проверить Minecraft-личность.";
                    default -> "§cНе удалось подтвердить Minecraft-личность.";
                };
                if (!"USER_NOT_FOUND".equals(lookupError)) {
                    log.warning("[Whitelist] identity lookup rejected " + nickname + ": " + lookupError);
                }
                event.disallow(Result.KICK_WHITELIST, deny(
                    message,
                    "§7При необходимости обратитесь к администрации PRISMA."
                ));
                return;
            }

            String status = textOrNull(user, "status");
            String platform = textOrNull(user, "platform");
            String expectedPlatform = bedrock ? "BEDROCK" : "JAVA";
            if (platform == null || !expectedPlatform.equalsIgnoreCase(platform)) {
                event.disallow(Result.KICK_WHITELIST, deny(
                    "§cПлатформа аккаунта не совпадает.",
                    "§7Обратитесь к администрации PRISMA."
                ));
                return;
            }
            boolean whitelisted = user.has("is_whitelisted") && user.get("is_whitelisted").getAsBoolean();
            boolean banned = user.has("is_banned") && user.get("is_banned").getAsBoolean();

            if (banned) {
                String reason = textOrNull(user, "ban_reason");
                event.disallow(Result.KICK_BANNED, deny(
                    "§cВы забанены на сервере.",
                    "§7Причина: " + (reason != null ? reason : "не указана")
                ));
                return;
            }

            if (!whitelisted) {
                String message = switch (status == null ? "" : status) {
                    case "PENDING" -> "§eВаша анкета ещё на рассмотрении.";
                    case "REJECTED" -> "§cВаша анкета отклонена.";
                    default -> "§cВы не в белом списке.";
                };
                event.disallow(Result.KICK_WHITELIST, deny(
                    message,
                    "§7Проверьте статус в Telegram-боте PRISMA."
                ));
                return;
            }

            // Java + Bedrock accounts of one profile share it, but only one may be online at a time.
            String profileId = textOrNull(user, "id");
            if (cache != null && cache.otherOnlineAccount(profileId, playerUuid) != null) {
                event.disallow(Result.KICK_OTHER, deny(
                    "§cС этого профиля уже играет другой ваш аккаунт.",
                    "§7Выйдите с него и зайдите снова."
                ));
                return;
            }

            String boundUuid = textOrNull(user, "minecraft_uuid");
            if (boundUuid == null) {
                JsonObject bind = new JsonObject();
                bind.addProperty("p_nickname", nickname);
                bind.addProperty("p_minecraft_uuid", playerUuid.toString());
                bind.addProperty("p_platform", expectedPlatform);

                JsonObject boundUser = supabase.postRpcSync(RpcNames.BIND_MINECRAFT_IDENTITY, bind);
                String bindError = textOrNull(boundUser, "error");
                if (bindError != null) {
                    log.warning("[Whitelist] identity bind failed for " + nickname + ": " + bindError);
                    event.disallow(Result.KICK_OTHER, deny(
                        "§cНе удалось закрепить Minecraft-аккаунт.",
                        "§7Обратитесь к администрации PRISMA."
                    ));
                    return;
                }

                String canonicalUuid = textOrNull(boundUser, "minecraft_uuid");
                String canonicalPlatform = textOrNull(boundUser, "platform");
                if (!playerUuid.toString().equalsIgnoreCase(canonicalUuid)
                    || !expectedPlatform.equalsIgnoreCase(canonicalPlatform)) {
                    log.warning("[Whitelist] identity bind returned unexpected identity for " + nickname);
                    event.disallow(Result.KICK_OTHER, deny(
                        "§cНе удалось подтвердить Minecraft-личность.",
                        "§7Обратитесь к администрации PRISMA."
                    ));
                    return;
                }
            }

        } catch (Exception e) {
            log.warning("[Whitelist] check failed for " + nickname + ": " + e.getMessage());
            event.disallow(Result.KICK_OTHER, deny(
                "§cНе удалось проверить доступ.",
                "§7Попробуйте зайти через минуту."
            ));
        }
    }

    private static String textOrNull(JsonObject obj, String key) {
        JsonElement el = obj.get(key);
        return el == null || el.isJsonNull() ? null : el.getAsString();
    }

    private static String deny(String... lines) {
        return String.join("\n", lines);
    }
}