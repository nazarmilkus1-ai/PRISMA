package team.prisma.plugin.auth;

import java.util.UUID;
import java.util.regex.Pattern;
import java.util.logging.Logger;

/***
 * Валидация входных данных для MinecraftAuthService.
 * Централизованная проверка UUID, ников игроков и IP-адресов.
 */
public final class AuthValidation {
    private static final Pattern UUID_PATTERN = Pattern.compile(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    );
    private static final Pattern PLAYER_NAME_PATTERN = Pattern.compile("^[a-zA-Z0-9_]{1,16}$");
    private static final Pattern IPV4_PATTERN = Pattern.compile(
        "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    );
    private static final Pattern IPV6_PATTERN = Pattern.compile(
        "^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$"
    );

    private AuthValidation() {}

    /** Проверяет, что строка — валидный UUID в стандартном формате. */
    public static boolean isValidUuid(String uuidStr) {
        if (uuidStr == null || uuidStr.isBlank()) return false;
        return UUID_PATTERN.matcher(uuidStr).matches();
    }

    /** Пытается распарсить UUID, возвращает null если невалиден. */
    public static UUID parseUuidOrNull(String uuidStr) {
        if (!isValidUuid(uuidStr)) return null;
        try {
            return UUID.fromString(uuidStr);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /** Проверяет ник игрока Minecraft (1-16 символов, буквы/цифры/подчёркивание). */
    public static boolean isValidPlayerName(String name) {
        if (name == null || name.isBlank()) return false;
        return PLAYER_NAME_PATTERN.matcher(name).matches();
    }

    /** Проверяет IP-адрес (IPv4 или IPv6 в полном формате). */
    public static boolean isValidIp(String ip) {
        if (ip == null || ip.isBlank()) return false;
        return IPV4_PATTERN.matcher(ip).matches() || IPV6_PATTERN.matcher(ip).matches();
    }

    /** Логирует предупреждение о невалидных входных данных с контекстом. */
    public static void logInvalidInput(Logger log, String context, String field, String value) {
        String safeValue = value == null ? "null" : value.length() > 50 ? value.substring(0, 50) + "..." : value;
        log.warning(() -> String.format("[AuthValidation] %s: невалидное поле %s = '%s'", context, field, safeValue));
    }
}
