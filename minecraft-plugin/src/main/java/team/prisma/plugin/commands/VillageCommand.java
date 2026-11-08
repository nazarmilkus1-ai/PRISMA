package team.prisma.plugin.commands;

import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.command.*;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.clans.Village;
import team.prisma.plugin.clans.VillageManager;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.http.RpcNames;

import java.util.List;
import java.util.stream.Collectors;

public final class VillageCommand implements CommandExecutor, TabCompleter {
    private final JavaPlugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final VillageManager villages;

    public VillageCommand(JavaPlugin plugin, SupabaseClient supabase, PlayerStateCache cache, VillageManager villages) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.villages = villages;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        if (args.length == 0) {
            player.sendMessage("§7/village create <название> [радиус]");
            player.sendMessage("§7/village list");
            player.sendMessage("§7/village info [название]");
            player.sendMessage("§7/village delete <название>");
            player.sendMessage("§7/village radius <название> <24-96>");
            player.sendMessage("§7/village home [название]");
            return true;
        }
        switch (args[0].toLowerCase()) {
            case "create" -> create(player, args);
            case "list" -> list(player);
            case "info" -> info(player, args);
            case "delete" -> delete(player, args);
            case "radius" -> radius(player, args);
            case "home" -> home(player, args);
            default -> player.sendMessage("§cНеизвестная подкоманда.");
        }
        return true;
    }

    private String userId(Player player) {
        String id = cache.userIdOf(player.getUniqueId());
        if (id == null) player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите.");
        return id;
    }

    private String clanId(Player player) {
        return cache.clanOf(player.getUniqueId());
    }

    private void create(Player player, String[] args) {
        String userId = userId(player);
        if (userId == null) return;
        if (args.length < 2) {
            player.sendMessage("§7Использование: /village create <название> [радиус]");
            return;
        }
        int radius = 48;
        if (args.length >= 3) {
            try { radius = Integer.parseInt(args[2]); } catch (NumberFormatException e) {
                player.sendMessage("§cРадиус должен быть числом 24-96."); return;
            }
        }
        String name = args[1];
        var loc = player.getLocation();
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_name", name);
        body.addProperty("p_world", loc.getWorld().getName());
        body.addProperty("p_x", Math.floor(loc.getX()));
        body.addProperty("p_y", loc.getY());
        body.addProperty("p_z", Math.floor(loc.getZ()));
        body.addProperty("p_radius", radius);
        supabase.postRpcAsync(RpcNames.CREATE_VILLAGE, body).thenAccept(result -> {
            if (!result.has("success") || !result.get("success").getAsBoolean()) {
                main(() -> player.sendMessage("§cНе удалось создать село: " + error(result)));
                return;
            }
            main(() -> {
                player.sendMessage("§aСело §f" + name + " §aсоздано. Территория: §f" + result.get("radius").getAsInt() + " блоков§a.");
                villages.refresh();
            });
        }).exceptionally(error -> {
            main(() -> player.sendMessage("§cНе удалось создать село: " + unwrap(error)));
            return null;
        });
    }

    private void list(Player player) {
        String clanId = clanId(player);
        if (clanId == null) {
            player.sendMessage("§cВы не состоите в клане.");
            return;
        }
        var list = villages.forClan(clanId);
        if (list.isEmpty()) {
            player.sendMessage("§7У вашего клана пока нет сёл.");
            return;
        }
        player.sendMessage("§6Сёла клана:");
        for (Village v : list) player.sendMessage("§f• §e" + v.name() + " §7(" + v.world() + ", радиус " + v.radius() + ")");
    }

    private void info(Player player, String[] args) {
        Village v;
        String clanId = clanId(player);
        if (clanId == null) {
            player.sendMessage("§cВы не состоите в клане.");
            return;
        }
        if (args.length >= 2) v = villages.byName(clanId, args[1]);
        else v = villages.at(player.getLocation());
        if (v == null) {
            player.sendMessage("§cСело не найдено.");
            return;
        }
        player.sendMessage("§6Село §f" + v.name());
        player.sendMessage("§7Мир: §f" + v.world());
        player.sendMessage("§7Центр: §f" + (int)v.centerX() + " " + (int)v.centerY() + " " + (int)v.centerZ());
        player.sendMessage("§7Радиус: §f" + v.radius());
    }

    private void delete(Player player, String[] args) {
        String userId = userId(player);
        if (userId == null || args.length < 2) {
            if (args.length < 2) player.sendMessage("§7Использование: /village delete <название>");
            return;
        }
        Village v = villages.byName(clanId(player), args[1]);
        if (v == null) {
            player.sendMessage("§cСело не найдено.");
            return;
        }
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_village_id", v.id().toString());
        supabase.postRpcAsync(RpcNames.DELETE_VILLAGE, body).thenAccept(result -> {
            main(() -> {
                player.sendMessage(result.has("success") && result.get("success").getAsBoolean() ? "§eСело удалено." : "§cНе удалось удалить село: " + error(result));
                villages.refresh();
            });
        });
    }

    private void radius(Player player, String[] args) {
        String userId = userId(player);
        if (userId == null || args.length < 3) {
            player.sendMessage("§7Использование: /village radius <название> <24-96>");
            return;
        }
        Village v = villages.byName(clanId(player), args[1]);
        if (v == null) { player.sendMessage("§cСело не найдено."); return; }
        int radius;
        try { radius = Integer.parseInt(args[2]); } catch (NumberFormatException e) {
            player.sendMessage("§cРадиус должен быть числом."); return;
        }
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_village_id", v.id().toString());
        body.addProperty("p_radius", radius);
        supabase.postRpcAsync(RpcNames.SET_VILLAGE_RADIUS, body).thenAccept(result -> {
            main(() -> {
                player.sendMessage(result.has("success") && result.get("success").getAsBoolean() ? "§aРадиус изменён." : "§cНе удалось изменить радиус: " + error(result));
                villages.refresh();
            });
        });
    }

    private void home(Player player, String[] args) {
        String clanId = clanId(player);
        if (clanId == null) {
            player.sendMessage("§cВы не состоите в клане.");
            return;
        }
        Village v = args.length >= 2 ? villages.byName(clanId, args[1]) : villages.forClan(clanId).stream().findFirst().orElse(null);
        if (v == null) {
            player.sendMessage("§cУ клана нет сёл.");
            return;
        }
        var world = Bukkit.getWorld(v.world());
        if (world == null) { player.sendMessage("§cМир села не загружен."); return; }
        var safe = world.getHighestBlockAt((int)Math.floor(v.centerX()), (int)Math.floor(v.centerZ())).getLocation().add(0.5, 1, 0.5);
        player.teleport(safe);
        player.sendMessage("§aТелепортация в село §f" + v.name() + "§a.");
    }

    private void main(Runnable runnable) { Bukkit.getScheduler().runTask(plugin, runnable); }

    private static String error(JsonObject o) { return o.has("error") ? o.get("error").getAsString() : "неизвестная ошибка"; }
    private static String unwrap(Throwable e) { return e.getCause() == null ? e.getMessage() : e.getCause().getMessage(); }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length == 1) return List.of("create","list","info","delete","radius","home").stream().filter(x -> x.startsWith(args[0].toLowerCase())).collect(Collectors.toList());
        return List.of();
    }
}
