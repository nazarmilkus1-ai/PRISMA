package team.prisma.plugin.auth;

import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;

import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.logging.Logger;

public final class MinecraftAuthService {
    private static final int MIN_PASSWORD_BYTES = 8;
    private static final int MAX_PASSWORD_BYTES = 72;

    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final Set<UUID> authenticated = ConcurrentHashMap.newKeySet();
    private final Logger log;

    public MinecraftAuthService(JavaPlugin plugin, SupabaseClient supabase, Logger log) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.log = log;
    }

    public boolean isAuthenticated(UUID uuid) {
        return authenticated.contains(uuid);
    }

    public void markAuthenticated(UUID uuid) {
        authenticated.add(uuid);
    }

    public void clear(UUID uuid) {
        authenticated.remove(uuid);
    }

    public void begin(Player player, long timeoutTicks) {
        UUID uuid = player.getUniqueId();
        if (FloodgateSupport.isBedrockPlayer(uuid)) {
            authenticated.add(uuid);
            player.sendMessage("§aPRISMA §7— §fBedrock-вход подтверждён через Geyser/Floodgate.");
            return;
        }

        authenticated.remove(uuid);
        player.sendMessage("§6§lPRISMA AUTH");
        player.sendMessage("§7Java-аккаунт требует авторизации.");
        player.sendMessage("§7Используйте §f/login <пароль>§7.");
        player.sendMessage("§7Если пароль ещё не задан: §f/register <пароль> <пароль>§7.");

        status(player).thenAccept(result -> runMain(() -> {
            if (!player.isOnline() || isAuthenticated(uuid)) return;
            String error = stringField(result, "error");
            if (error != null) {
                player.sendMessage("§cНе удалось проверить состояние PRISMA Auth: §7" + error);
                return;
            }
            boolean configured = bool(result, "configured");
            if (configured) {
                player.sendMessage("§eПароль уже установлен. Введите §f/login <пароль>§e.");
            } else {
                player.sendMessage("§eПароль ещё не установлен. Введите §f/register <пароль> <пароль>§e.");
            }
        })).exceptionally(error -> {
            runMain(() -> {
                if (player.isOnline() && !isAuthenticated(uuid)) {
                    player.sendMessage("§cPRISMA Auth сейчас не отвечает. Повторите команду /login или /register.");
                }
            });
            return null;
        });

        Bukkit.getScheduler().runTaskLater(plugin, () -> {
            if (player.isOnline() && !isAuthenticated(uuid)) {
                player.kickPlayer("§cВремя авторизации PRISMA истекло.");
                clear(uuid);
            }
        }, timeoutTicks);
    }

    public boolean validPassword(String password) {
        if (password == null || password.isBlank()) return false;
        int bytes = password.getBytes(StandardCharsets.UTF_8).length;
        return bytes >= MIN_PASSWORD_BYTES && bytes <= MAX_PASSWORD_BYTES;
    }

    public java.util.concurrent.CompletableFuture<JsonObject> status(Player player) {
        JsonObject body = identity(player);
        return supabase.postRpcAsync(RpcNames.MC_AUTH_STATUS, body);
    }

    public void register(Player player, String password, String repeat) {
        if (isAuthenticated(player.getUniqueId())) {
            player.sendMessage("§eВы уже авторизованы.");
            return;
        }
        if (!validPassword(password) || !password.equals(repeat)) {
            player.sendMessage("§cПароль должен быть 8–72 байта, а два значения должны совпадать.");
            return;
        }

        status(player).thenAccept(result -> runMain(() -> {
            String error = stringField(result, "error");
            if (error != null) {
                tellAuthError(player, error);
                return;
            }
            if (bool(result, "configured")) {
                player.sendMessage("§eПароль уже установлен. Используйте §f/login <пароль>§e.");
                return;
            }
            String userId = stringField(result, "user_id");
            if (userId == null) {
                player.sendMessage("§cPRISMA не вернул ID аккаунта.");
                return;
            }

            JsonObject body = new JsonObject();
            body.addProperty("p_user_id", userId);
            body.addProperty("p_new_password", password);

            supabase.postRpcAsync(RpcNames.MC_AUTH_SET_PASSWORD, body).thenAccept(setResult -> runMain(() -> {
                String setError = stringField(setResult, "error");
                if (setError != null) {
                    tellAuthError(player, setError);
                    return;
                }
                authenticated.add(player.getUniqueId());
                player.sendMessage("§aПароль PRISMA Auth установлен. Вы авторизованы.");
            })).exceptionally(error2 -> {
                runMain(() -> player.sendMessage("§cОшибка связи с PRISMA Auth."));
                return null;
            });
        })).exceptionally(error -> {
            runMain(() -> player.sendMessage("§cОшибка проверки PRISMA Auth."));
            return null;
        });
    }

    public void login(Player player, String password) {
        if (isAuthenticated(player.getUniqueId())) {
            player.sendMessage("§eВы уже авторизованы.");
            return;
        }
        if (!validPassword(password)) {
            player.sendMessage("§cПароль должен быть длиной 8–72 байта.");
            return;
        }

        JsonObject body = identity(player);
        body.addProperty("p_password", password);

        supabase.postRpcAsync(RpcNames.MC_AUTH_LOGIN, body).thenAccept(result -> runMain(() -> {
            String error = stringField(result, "error");
            if (error != null) {
                tellAuthError(player, error);
                return;
            }
            authenticated.add(player.getUniqueId());
            player.sendMessage("§aАвторизация PRISMA успешна. Добро пожаловать.");
        })).exceptionally(error -> {
            runMain(() -> {
                if (player.isOnline()) player.sendMessage("§cОшибка связи с PRISMA Auth.");
            });
            return null;
        });
    }

    public void changePassword(Player player, String currentPassword, String newPassword) {
        if (!isAuthenticated(player.getUniqueId())) {
            player.sendMessage("§cСначала войдите через /login.");
            return;
        }
        if (!validPassword(currentPassword) || !validPassword(newPassword)) {
            player.sendMessage("§cПароли должны быть длиной 8–72 байта.");
            return;
        }
        status(player).thenAccept(statusResult -> runMain(() -> {
            String error = stringField(statusResult, "error");
            if (error != null) {
                tellAuthError(player, error);
                return;
            }
            String userId = stringField(statusResult, "user_id");
            if (userId == null) {
                player.sendMessage("§cPRISMA не вернул ID аккаунта.");
                return;
            }

            JsonObject body = new JsonObject();
            body.addProperty("p_user_id", userId);
            body.addProperty("p_current_password", currentPassword);
            body.addProperty("p_new_password", newPassword);

            supabase.postRpcAsync(RpcNames.MC_AUTH_CHANGE_PASSWORD, body).thenAccept(result -> runMain(() -> {
                String changeError = stringField(result, "error");
                if (changeError != null) {
                    tellAuthError(player, changeError);
                    return;
                }
                player.sendMessage("§aПароль PRISMA Auth изменён.");
            })).exceptionally(error2 -> {
                runMain(() -> player.sendMessage("§cОшибка связи с PRISMA Auth."));
                return null;
            });
        })).exceptionally(error -> {
            runMain(() -> player.sendMessage("§cОшибка проверки PRISMA Auth."));
            return null;
        });
    }

    public static boolean isAuthenticationCommand(String raw) {
        if (raw == null || raw.isBlank()) return false;
        String command = raw.trim();
        if (command.startsWith("/")) command = command.substring(1);
        int space = command.indexOf(' ');
        if (space >= 0) command = command.substring(0, space);
        return switch (command.toLowerCase(java.util.Locale.ROOT)) {
            case "login", "register", "changepass", "prismaauth", "auth" -> true;
            default -> false;
        };
    }

    public void sendHelp(Player player) {
        player.sendMessage("§6§lPRISMA AUTH");
        player.sendMessage("§7/register <пароль> <пароль> §8— первый пароль");
        player.sendMessage("§7/login <пароль> §8— вход");
        player.sendMessage("§7/changepass <текущий> <новый> §8— смена пароля");
    }

    private JsonObject identity(Player player) {
        JsonObject body = new JsonObject();
        body.addProperty("p_nickname", player.getName());
        body.addProperty("p_minecraft_uuid", player.getUniqueId().toString());
        return body;
    }

    private void tellAuthError(Player player, String code) {
        String message = switch (code) {
            case "USER_NOT_FOUND" -> "Minecraft-аккаунт не найден в PRISMA.";
            case "PLATFORM_NOT_JAVA" -> "Этот аккаунт не относится к Java Edition.";
            case "IDENTITY_MISMATCH" -> "Minecraft UUID не совпадает с привязанным аккаунтом.";
            case "AUTH_NOT_CONFIGURED" -> "Пароль ещё не установлен. Используйте /register или настройте пароль на сайте.";
            case "AUTH_ALREADY_CONFIGURED" -> "Пароль уже установлен. Используйте /login.";
            case "INVALID_PASSWORD" -> "Неверный пароль.";
            case "CURRENT_PASSWORD_INVALID" -> "Текущий пароль неверный.";
            case "AUTH_LOCKED" -> "Авторизация временно заблокирована после нескольких неверных попыток.";
            default -> "Авторизация не выполнена: " + code;
        };
        player.sendMessage("§c" + message);
    }

    private void runMain(Runnable task) {
        Bukkit.getScheduler().runTask(plugin, task);
    }

    private static boolean bool(JsonObject object, String key) {
        return object.has(key) && !object.get(key).isJsonNull() && object.get(key).getAsBoolean();
    }

    private static String stringField(JsonObject object, String key) {
        return object.has(key) && !object.get(key).isJsonNull() ? object.get(key).getAsString() : null;
    }
}
