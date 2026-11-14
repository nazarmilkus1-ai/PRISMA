package team.prisma.plugin.commands;

import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.command.TabCompleter;
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.plugin.Plugin;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.http.RpcNames;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.menu.MainMenu;

import java.util.List;
import java.util.Map;

/**
 * /pp — PRISMA Points. Opens the PP screen of the menu, sells resources to the server and buys shop items.
 * Prices and the shop live in the database. Items are taken from the player first; if the database refuses, they are given back.
 * A purchase is charged first; if the effect cannot be applied, it is refunded.
 */
public final class PointsCommand implements CommandExecutor, TabCompleter {
    private static final Map<String, String> ERRORS = Map.of(
        "NOT_A_MEMBER", "PP доступны участникам с одобренной заявкой.",
        "ITEM_NOT_SOLD", "Сервер не покупает этот предмет.",
        "DAILY_CAP", "Дневной лимит на этот предмет исчерпан.",
        "TOO_FEW", "Слишком мало предметов — за них не набирается и 1 PP.",
        "INSUFFICIENT_PP", "Не хватает PP.",
        "ITEM_NOT_FOUND", "Такого товара нет."
    );

    private final Plugin plugin;
    private final SupabaseClient supabase;
    private final PlayerStateCache cache;
    private final MainMenu menu;

    public PointsCommand(Plugin plugin, SupabaseClient supabase, PlayerStateCache cache, MainMenu menu) {
        this.plugin = plugin;
        this.supabase = supabase;
        this.cache = cache;
        this.menu = menu;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Эта команда доступна только игрокам.");
            return true;
        }
        String userId = cache.userIdOf(player.getUniqueId());
        if (userId == null) {
            player.sendMessage("§cПрофиль ещё не синхронизирован. Перезайдите на сервер.");
            return true;
        }
        String sub = args.length == 0 ? "menu" : args[0].toLowerCase();
        switch (sub) {
            case "sell", "продать" -> {
                if (args.length < 2) {
                    player.sendMessage("§7Использование: /pp sell <предмет> [количество|all]");
                    return true;
                }
                sell(player, userId, args[1], args.length > 2 ? args[2] : "all");
            }
            case "buy", "купить" -> {
                if (args.length < 2) {
                    player.sendMessage("§7Использование: /pp buy <товар>");
                    return true;
                }
                buy(player, userId, args[1]);
            }
            default -> openMenu(player, userId);
        }
        return true;
    }

    private void openMenu(Player player, String userId) {
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        call(player, RpcNames.MC_PP_CATALOG, body, result -> {
            if (!bool(result, "success")) {
                player.sendMessage("§c" + message(result));
                return;
            }
            menu.openPoints(player, result);
        });
    }

    private void sell(Player player, String userId, String itemName, String amount) {
        Material material = Material.matchMaterial(itemName);
        if (material == null) {
            player.sendMessage("§cНеизвестный предмет: " + itemName);
            return;
        }
        int have = count(player, material);
        int want = have;
        if (!amount.equalsIgnoreCase("all")) {
            try {
                want = Math.min(have, Integer.parseInt(amount));
            } catch (NumberFormatException e) {
                player.sendMessage("§cКоличество — число или all.");
                return;
            }
        }
        if (want < 1) {
            player.sendMessage("§cУ вас нет такого предмета (переименованные и с чарами не принимаются).");
            return;
        }
        int taken = take(player, material, want);
        if (taken < 1) {
            player.sendMessage("§cНе удалось взять предметы из инвентаря.");
            return;
        }
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_item", material.name());
        body.addProperty("p_qty", taken);
        final int takenFinal = taken;
        supabase.postRpcAsync(RpcNames.MC_PP_SELL, body)
            .thenAccept(result -> Bukkit.getScheduler().runTask(plugin, () -> {
                if (bool(result, "success")) {
                    player.sendMessage("§aПродано §f" + takenFinal + " §aшт. → §f+" + result.get("paid").getAsLong()
                        + " PP§a. Баланс: §f" + result.get("balance").getAsLong() + " PP");
                } else {
                    give(player, material, takenFinal);
                    player.sendMessage("§c" + message(result));
                }
            }))
            .exceptionally(error -> {
                Bukkit.getScheduler().runTask(plugin, () -> {
                    give(player, material, takenFinal);
                    player.sendMessage("§cОшибка связи с PRISMA, предметы возвращены.");
                });
                return null;
            });
    }

    private void buy(Player player, String userId, String sku) {
        JsonObject body = new JsonObject();
        body.addProperty("p_user_id", userId);
        body.addProperty("p_sku", sku);
        call(player, RpcNames.MC_PP_BUY, body, result -> {
            if (!bool(result, "success")) {
                player.sendMessage("§c" + message(result));
                return;
            }
            String purchaseId = result.get("purchase_id").getAsString();
            boolean applied = false;
            try {
                applied = apply(player, result.getAsJsonObject("payload"));
            } catch (RuntimeException ignored) {
                // falls through to the refund below
            }
            if (applied) {
                player.sendMessage("§aКуплено: §f" + result.get("title").getAsString()
                    + "§a. Баланс: §f" + result.get("balance").getAsLong() + " PP");
                return;
            }
            JsonObject refund = new JsonObject();
            refund.addProperty("p_user_id", userId);
            refund.addProperty("p_purchase_id", purchaseId);
            supabase.postRpcAsync(RpcNames.MC_PP_REFUND, refund);
            player.sendMessage("§cТовар сейчас нельзя применить — PP возвращены.");
        });
    }

    /** Only effect items exist in the first version of the shop. */
    private static boolean apply(Player player, JsonObject payload) {
        if (payload == null || !payload.has("effect")) return false;
        PotionEffectType type = switch (payload.get("effect").getAsString()) {
            case "SPEED" -> PotionEffectType.SPEED;
            case "HASTE" -> PotionEffectType.HASTE;
            case "NIGHT_VISION" -> PotionEffectType.NIGHT_VISION;
            case "REGENERATION" -> PotionEffectType.REGENERATION;
            default -> null;
        };
        if (type == null) return false;
        int seconds = Math.max(1, Math.min(7200, payload.get("seconds").getAsInt()));
        int amplifier = payload.has("amplifier") ? Math.max(0, Math.min(4, payload.get("amplifier").getAsInt())) : 0;
        player.addPotionEffect(new PotionEffect(type, seconds * 20, amplifier));
        return true;
    }

    // ------------------------------------------------------------------ inventory helpers

    /** Plain stacks only: renamed or enchanted items are never sold. */
    private static int count(Player player, Material material) {
        int total = 0;
        for (ItemStack stack : player.getInventory().getStorageContents()) {
            if (stack != null && stack.getType() == material && !stack.hasItemMeta()) total += stack.getAmount();
        }
        return total;
    }

    private static int take(Player player, Material material, int want) {
        int left = want;
        ItemStack[] contents = player.getInventory().getStorageContents();
        for (int i = 0; i < contents.length && left > 0; i++) {
            ItemStack stack = contents[i];
            if (stack == null || stack.getType() != material || stack.hasItemMeta()) continue;
            int remove = Math.min(left, stack.getAmount());
            if (remove == stack.getAmount()) {
                contents[i] = null;
            } else {
                stack.setAmount(stack.getAmount() - remove);
            }
            left -= remove;
        }
        player.getInventory().setStorageContents(contents);
        return want - left;
    }

    private static void give(Player player, Material material, int amount) {
        int left = amount;
        while (left > 0) {
            int part = Math.min(left, material.getMaxStackSize());
            Map<Integer, ItemStack> rest = player.getInventory().addItem(new ItemStack(material, part));
            for (ItemStack extra : rest.values()) player.getWorld().dropItemNaturally(player.getLocation(), extra);
            left -= part;
        }
    }

    // ------------------------------------------------------------------ plumbing

    private void call(Player player, String rpc, JsonObject body, java.util.function.Consumer<JsonObject> callback) {
        supabase.postRpcAsync(rpc, body)
            .thenAccept(result -> Bukkit.getScheduler().runTask(plugin, () -> callback.accept(result)))
            .exceptionally(error -> {
                Bukkit.getScheduler().runTask(plugin, () -> player.sendMessage("§cОшибка связи с PRISMA. Попробуйте позже."));
                return null;
            });
    }

    private static boolean bool(JsonObject o, String key) {
        return o != null && o.has(key) && !o.get(key).isJsonNull() && o.get(key).getAsBoolean();
    }

    private static String message(JsonObject o) {
        String code = o != null && o.has("error") && !o.get("error").isJsonNull() ? o.get("error").getAsString() : "?";
        return ERRORS.getOrDefault(code, "Не получилось: " + code);
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length == 1) return List.of("sell", "buy");
        return List.of();
    }
}
