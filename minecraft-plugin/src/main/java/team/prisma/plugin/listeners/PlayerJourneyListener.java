package team.prisma.plugin.listeners;

import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.entity.PlayerDeathEvent;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.journey.PlayerJourneyStore;
import team.prisma.plugin.journey.PlayerJourneyStore.Point;
import team.prisma.plugin.modules.ModuleStateCache;

public final class PlayerJourneyListener implements Listener {
    private final JavaPlugin plugin;
    private final PlayerJourneyStore journey;
    private final ModuleStateCache modules;

    public PlayerJourneyListener(JavaPlugin plugin, PlayerJourneyStore journey, ModuleStateCache modules) {
        this.plugin = plugin;
        this.journey = journey;
        this.modules = modules;
    }

    @EventHandler
    public void onDeath(PlayerDeathEvent event) {
        if (!modules.isEnabled("minecraft-journey")) return;
        if (!journey.isStorageHealthy()) return;
        Player player = event.getEntity();
        String nickname = player.getName();
        // Capture Bukkit state synchronously; only immutable values are passed to the writer.
        Point point = Point.capture(player.getLocation().clone(), System.currentTimeMillis());
        if (point == null) return;

        journey.recordDeath(player.getUniqueId(), point).thenAccept(result -> {
            if (result != PlayerJourneyStore.MutationResult.SAVED) {
                plugin.getLogger().warning("[Journey] Не удалось сохранить последнее место смерти игрока "
                    + nickname + ". Проверьте journey.yml и место на диске.");
            }
        }).exceptionally(error -> {
            plugin.getLogger().warning("[Journey] Ошибка записи последнего места смерти: "
                + error.getClass().getSimpleName());
            return null;
        });
    }
}
