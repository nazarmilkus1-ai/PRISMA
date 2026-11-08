package team.prisma.plugin.config;

import org.bukkit.configuration.file.FileConfiguration;

import java.net.URI;

public record PluginConfig(
    String supabaseUrl,
    String serviceRoleKey,
    String serverName,
    int moderationPollIntervalSeconds,
    int httpTimeoutSeconds,
    int authTimeoutSeconds
) {
    public static PluginConfig from(FileConfiguration cfg) {
        String url = cfg.getString("supabase.url", "");
        String key = cfg.getString("supabase.service-role-key", "");
        URI parsedUrl;
        try {
            parsedUrl = URI.create(url);
        } catch (IllegalArgumentException e) {
            parsedUrl = null;
        }
        if (parsedUrl == null
            || (!"https".equalsIgnoreCase(parsedUrl.getScheme()) && !"http".equalsIgnoreCase(parsedUrl.getScheme()))
            || parsedUrl.getHost() == null
            || url.contains("YOUR-PROJECT-REF")
            || key.isBlank()
            || key.contains("YOUR_SUPABASE")
            || key.length() < 32) {
            throw new IllegalStateException(
                "config.yml is invalid -- set a real Supabase URL and service-role key " +
                "in plugins/PrismaPlugin/config.yml, then restart the server."
            );
        }
        return new PluginConfig(
            url.replaceAll("/+$", ""),
            key,
            cfg.getString("server-name", "primary").trim().isBlank() ? "primary" : cfg.getString("server-name", "primary").trim(),
            Math.min(300, Math.max(5, cfg.getInt("moderation-poll-interval-seconds", 20))),
            Math.min(60, Math.max(3, cfg.getInt("http-timeout-seconds", 8))),
            Math.min(600, Math.max(30, cfg.getInt("auth-timeout-seconds", 120)))
        );
    }
}