package team.prisma.plugin.commands;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.modules.ModuleStateCache;

import java.util.Locale;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

public final class MinecraftCommandCatalogCommand implements CommandExecutor {
    private static final int LINES_PER_PAGE = 12;
    private final PlayerStateCache cache;
    private final ModuleStateCache modules;

    public MinecraftCommandCatalogCommand(PlayerStateCache cache, ModuleStateCache modules) {
        this.cache = cache;
        this.modules = modules;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Команды PRISMA предназначены для игроков.");
            return true;
        }

        JsonObject catalog = loadCatalog();
        List<String> lines = new ArrayList<>();
        lines.add("");

        JsonArray commands = catalog.getAsJsonArray("commands");
        for (JsonElement element : commands) {
            JsonObject item = element.getAsJsonObject();
            String root = item.get("command").getAsString();
            String requiredModule = requiredModule(root);
            if (requiredModule != null && !modules.isEnabled(requiredModule)) continue;
            String description = item.get("description").getAsString();
            lines.add("§e" + root + " §7— §f" + description);

            if (item.has("aliases") && item.get("aliases").getAsJsonArray().size() > 0) {
                lines.add("  §8Псевдонимы: §7" + join(item.getAsJsonArray("aliases")));
            }

            JsonArray subcommands = item.has("subcommands")
                ? item.getAsJsonArray("subcommands") : new JsonArray();
            for (JsonElement sub : subcommands) {
                JsonArray row = sub.getAsJsonArray();
                lines.add("  §7" + root + " " + row.get(0).getAsString()
                    + " §8— §f" + row.get(1).getAsString());
            }
        }

        JsonArray clanWars = catalog.has("clan_war_subcommands")
            ? catalog.getAsJsonArray("clan_war_subcommands") : new JsonArray();
        if (!clanWars.isEmpty() && modules.isEnabled("minecraft-clan-commands")) {
            lines.add("");
            lines.add("§6Войны кланов");
            for (JsonElement element : clanWars) {
                JsonArray row = element.getAsJsonArray();
                lines.add("  §7/clan war " + row.get(0).getAsString()
                    + " §8— §f" + row.get(1).getAsString());
            }
        }

        String platform = cache.platformOf(player.getUniqueId());
        JsonArray authentication = catalog.has("authentication")
            ? catalog.getAsJsonArray("authentication") : new JsonArray();
        boolean authShown = false;
        for (JsonElement element : authentication) {
            JsonObject auth = element.getAsJsonObject();
            String authPlatform = auth.has("platform") ? auth.get("platform").getAsString() : "";
            if (platform != null && !platform.isBlank() && !platform.equalsIgnoreCase(authPlatform)) continue;

            if (!authShown) {
                lines.add("");
                lines.add("§bАвторизация");
                authShown = true;
            }
            lines.add("§b" + auth.get("name").getAsString() + " §7— §f"
                + auth.get("description").getAsString());
            JsonArray authCommands = auth.has("commands")
                ? auth.getAsJsonArray("commands") : new JsonArray();
            for (JsonElement authCommand : authCommands) {
                JsonArray row = authCommand.getAsJsonArray();
                lines.add("  §7" + row.get(0).getAsString()
                    + " §8— §f" + row.get(1).getAsString());
            }
        }
        if (!authShown) {
            lines.add("");
            lines.add("§bАвторизация");
            lines.add("§7Java — PRISMA Auth; Bedrock — Geyser + Floodgate.");
        }

        int totalPages = Math.max(1, (lines.size() + LINES_PER_PAGE - 1) / LINES_PER_PAGE);
        int page = 1;
        if (args.length > 0) {
            try {
                page = Integer.parseInt(args[0]);
            } catch (NumberFormatException ignored) {
                player.sendMessage("§cУкажите номер страницы: /prismacommands <страница>");
                return true;
            }
        }
        if (args.length > 1 || page < 1 || page > totalPages) {
            player.sendMessage("§cДоступные страницы: 1–" + totalPages
                + ". Используйте /prismacommands <страница>.");
            return true;
        }

        player.sendMessage("§a§lPRISMA §7— §fКоманды §8(" + page + "/" + totalPages + ")");
        int start = (page - 1) * LINES_PER_PAGE;
        int end = Math.min(start + LINES_PER_PAGE, lines.size());
        for (int index = start; index < end; index++) {
            player.sendMessage(lines.get(index));
        }
        player.sendMessage("§8Страницы: /prismacommands <1–" + totalPages + ">");
        return true;
    }

    private static String requiredModule(String root) {
        String command = root.toLowerCase(Locale.ROOT).replaceFirst("^/", "");
        return switch (command) {
            case "clan", "клан" -> "minecraft-clan-commands";
            case "village", "село" -> "minecraft-village-commands";
            case "sethome", "home", "homes", "delhome", "deletehome" -> "minecraft-homes";
            case "spawn", "spawns", "setspawn", "delspawn" -> "minecraft-spawns";
            case "coords", "lastdeath", "checkpoint" -> "minecraft-journey";
            case "grave", "graves" -> "minecraft-graves";
            case "hud" -> "minecraft-hud";
            case "warn", "mute", "unmute", "kick", "ban", "tempban", "unban", "history" -> "minecraft-moderation";
            case "tpall" -> "minecraft-tpall";
            case "ptp", "prismatp", "ptphere", "prismatphere" -> "minecraft-staff-teleport";
            case "tpa", "tpaccept", "tpdeny" -> "minecraft-teleport-requests";
            default -> null;
        };
    }

    private JsonObject loadCatalog() {
        try (InputStream stream = getClass().getClassLoader()
                .getResourceAsStream("prisma/minecraft-commands.json")) {
            if (stream == null) {
                throw new IllegalStateException("Missing prisma/minecraft-commands.json in plugin JAR");
            }
            try (InputStreamReader reader = new InputStreamReader(stream, StandardCharsets.UTF_8)) {
                return JsonParser.parseReader(reader).getAsJsonObject();
            }
        } catch (Exception e) {
            throw new IllegalStateException("Unable to load PRISMA command catalog", e);
        }
    }

    private static String join(JsonArray values) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) result.append(", ");
            result.append(values.get(i).getAsString());
        }
        return result.toString();
    }
}
