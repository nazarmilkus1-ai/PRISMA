package team.prisma.plugin.auth;

import java.lang.reflect.Method;
import java.util.UUID;

/**
 * Optional Floodgate bridge that keeps PRISMA buildable without bundling the
 * Floodgate API. Reflection is used because Floodgate is a server dependency.
 */
public final class FloodgateSupport {
    private FloodgateSupport() {}

    public static boolean isBedrockPlayer(UUID playerUuid) {
        if (playerUuid == null) return false;

        try {
            Class<?> apiClass = Class.forName("org.geysermc.floodgate.api.FloodgateApi");
            Method getInstance = apiClass.getMethod("getInstance");
            Object api = getInstance.invoke(null);
            if (api == null) return false;

            Method isFloodgatePlayer = apiClass.getMethod("isFloodgatePlayer", UUID.class);
            Object result = isFloodgatePlayer.invoke(api, playerUuid);
            return result instanceof Boolean && (Boolean) result;
        } catch (ReflectiveOperationException | LinkageError ignored) {
            // Floodgate is optional. Failure to detect it is intentionally
            // treated as Java so Java authentication cannot be bypassed by
            // a broken/missing Bedrock integration.
            return false;
        }
    }
}
