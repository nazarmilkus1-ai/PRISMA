package team.prisma.plugin.commands;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * /ai &lt;вопрос&gt; — PRISMA_AI прямо из Minecraft. Вопрос уходит на сайт PRISMA (тот же помощник, что в боте),
 * ответ приходит обычным текстом. Ключ API и адрес берутся из config.yml (ai.url / ai.key); без ai.url команда выключена.
 */
public final class AiCommand implements CommandExecutor {
    private static final long COOLDOWN_MS = 8_000L;
    private static final int MAX_QUESTION = 300;
    private static final int MAX_ANSWER = 600;

    private final JavaPlugin plugin;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    private final Gson gson = new Gson();
    private final Map<UUID, Long> lastUse = new ConcurrentHashMap<>();

    public AiCommand(JavaPlugin plugin) {
        this.plugin = plugin;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        String url = plugin.getConfig().getString("ai.url", "").trim();
        if (url.isEmpty()) {
            sender.sendMessage("§cPRISMA_AI на сервере пока не подключён. Спросите в Telegram-боте PRISMA.");
            return true;
        }
        if (args.length == 0) {
            sender.sendMessage("§bPRISMA_AI§7: напишите вопрос, например §f/ai как вступить в клан");
            return true;
        }
        String question = String.join(" ", args).trim();
        if (question.length() > MAX_QUESTION) question = question.substring(0, MAX_QUESTION);

        String who = sender instanceof Player player ? player.getName() : "console";
        if (sender instanceof Player player) {
            long now = System.currentTimeMillis();
            Long last = lastUse.get(player.getUniqueId());
            if (last != null && now - last < COOLDOWN_MS) {
                sender.sendMessage("§7Подождите пару секунд перед следующим вопросом.");
                return true;
            }
            lastUse.put(player.getUniqueId(), now);
        }
        sender.sendMessage("§7PRISMA_AI думает…");

        JsonObject body = new JsonObject();
        body.addProperty("question", question);
        body.addProperty("player", who);
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
            .timeout(Duration.ofSeconds(60))
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(gson.toJson(body), StandardCharsets.UTF_8));
        String key = plugin.getConfig().getString("ai.key", "").trim();
        if (!key.isEmpty()) request.header("x-prisma-plugin-key", key);

        http.sendAsync(request.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8))
            .thenAccept(response -> reply(sender, response))
            .exceptionally(error -> {
                reply(sender, null);
                return null;
            });
        return true;
    }

    private void reply(CommandSender sender, HttpResponse<String> response) {
        String text = "§cPRISMA_AI сейчас недоступен. Попробуйте позже или спросите в боте.";
        if (response != null && response.statusCode() < 500) {
            try {
                JsonObject json = gson.fromJson(response.body(), JsonObject.class);
                if (json != null && json.has("answer")) text = clean(json.get("answer").getAsString());
            } catch (RuntimeException ignored) {
                // keep the generic message
            }
        }
        final String message = text;
        plugin.getServer().getScheduler().runTask(plugin, () -> {
            if (sender instanceof Player player && !player.isOnline()) return;
            for (String line : message.split("\n")) {
                if (!line.isBlank()) sender.sendMessage("§b[PRISMA_AI] §f" + line);
            }
        });
    }

    /** Drop Markdown and colour codes so model text cannot restyle chat. */
    static String clean(String raw) {
        String text = raw.replace("§", "").replaceAll("\\*\\*|__|`", "").replaceAll("(?m)^#+\\s*", "");
        return text.length() > MAX_ANSWER ? text.substring(0, MAX_ANSWER) + "…" : text;
    }
}
