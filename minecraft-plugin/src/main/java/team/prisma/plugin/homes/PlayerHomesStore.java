package team.prisma.plugin.homes;

import org.bukkit.Location;
import org.bukkit.configuration.ConfigurationSection;
import org.bukkit.configuration.InvalidConfigurationException;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.plugin.java.JavaPlugin;

import java.io.File;
import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;

/**
 * Локальное постоянное хранилище личных домов Minecraft.
 * Файл принадлежит конкретному серверу и не является источником данных аккаунта PRISMA.
 */
public final class PlayerHomesStore implements AutoCloseable {
    public static final int MAX_HOMES = 2;

    public record HomePoint(
        String name,
        String world,
        double x,
        double y,
        double z,
        float yaw,
        float pitch
    ) {}

    private final JavaPlugin plugin;
    private final File storageFile;
    private final Map<UUID, Map<Integer, HomePoint>> homes = new HashMap<>();
    private final ExecutorService writer = Executors.newSingleThreadExecutor(task -> {
        Thread thread = new Thread(task, "prisma-home-storage");
        thread.setDaemon(true);
        return thread;
    });

    private Map<UUID, Map<Integer, HomePoint>> persistedSnapshot = Map.of();
    private boolean storageHealthy = true;
    private boolean closed;
    private long revision;

    public PlayerHomesStore(JavaPlugin plugin) {
        this.plugin = plugin;
        this.storageFile = new File(plugin.getDataFolder(), "homes.yml");
        load();
        synchronized (this) {
            persistedSnapshot = snapshotLocked();
        }
    }

    public synchronized boolean isStorageHealthy() {
        return storageHealthy;
    }

    public synchronized HomePoint get(UUID playerId, int slot) {
        if (!validSlot(slot)) return null;
        return homes.getOrDefault(playerId, Map.of()).get(slot);
    }

    public synchronized Map<Integer, HomePoint> list(UUID playerId) {
        return Collections.unmodifiableMap(
            new TreeMap<>(homes.getOrDefault(playerId, Map.of()))
        );
    }

    public synchronized CompletableFuture<Boolean> set(UUID playerId, int slot, Location location) {
        if (closed || !storageHealthy || playerId == null
            || !validSlot(slot) || !validLocation(location)) {
            return CompletableFuture.completedFuture(false);
        }

        HomePoint point = new HomePoint(
            "Дом " + slot,
            location.getWorld().getName(),
            location.getX(),
            location.getY(),
            location.getZ(),
            location.getYaw(),
            location.getPitch()
        );

        Map<Integer, HomePoint> next = new HashMap<>(homes.getOrDefault(playerId, Map.of()));
        next.put(slot, point);
        homes.put(playerId, next);
        long operationRevision = ++revision;
        return queuePersist(operationRevision);
    }

    public synchronized CompletableFuture<Boolean> delete(UUID playerId, int slot) {
        if (closed || !storageHealthy || playerId == null || !validSlot(slot)) {
            return CompletableFuture.completedFuture(false);
        }

        Map<Integer, HomePoint> current = homes.get(playerId);
        if (current == null || !current.containsKey(slot)) {
            return CompletableFuture.completedFuture(false);
        }

        Map<Integer, HomePoint> next = new HashMap<>(current);
        next.remove(slot);
        if (next.isEmpty()) homes.remove(playerId);
        else homes.put(playerId, next);

        long operationRevision = ++revision;
        return queuePersist(operationRevision);
    }

    private CompletableFuture<Boolean> queuePersist(long operationRevision) {
        Map<UUID, Map<Integer, HomePoint>> snapshot = snapshotLocked();
        CompletableFuture<Boolean> result = new CompletableFuture<>();

        try {
            writer.execute(() -> {
                boolean saved = persistSnapshot(snapshot);
                synchronized (PlayerHomesStore.this) {
                    if (saved) {
                        persistedSnapshot = snapshot;
                    } else if (revision == operationRevision) {
                        restorePersistedSnapshotLocked();
                    }
                }
                result.complete(saved);
            });
        } catch (RejectedExecutionException error) {
            if (revision == operationRevision) restorePersistedSnapshotLocked();
            result.complete(false);
        }
        return result;
    }

    private void load() {
        if (!storageFile.exists()) return;

        YamlConfiguration yaml = new YamlConfiguration();
        try {
            yaml.load(storageFile);
        } catch (IOException | InvalidConfigurationException error) {
            storageHealthy = false;
            plugin.getLogger().log(
                Level.SEVERE,
                "Не удалось прочитать homes.yml. Изменение домов отключено, чтобы не потерять старые данные.",
                error
            );
            return;
        }

        if (!yaml.contains("players")) return;
        ConfigurationSection players = yaml.getConfigurationSection("players");
        if (players == null) {
            storageHealthy = false;
            plugin.getLogger().severe("Раздел players в homes.yml имеет неверный формат. Файл оставлен без изменений.");
            return;
        }

        for (String playerKey : players.getKeys(false)) {
            UUID playerId;
            try {
                playerId = UUID.fromString(playerKey);
            } catch (IllegalArgumentException error) {
                storageHealthy = false;
                plugin.getLogger().severe("В homes.yml найден неверный UUID. Файл оставлен без изменений.");
                continue;
            }

            ConfigurationSection playerSection = players.getConfigurationSection(playerKey);
            if (playerSection == null) {
                storageHealthy = false;
                plugin.getLogger().severe("Запись игрока " + playerKey
                    + " в homes.yml имеет неверный формат. Файл оставлен без изменений.");
                continue;
            }
            ConfigurationSection homeSection = playerSection.getConfigurationSection("homes");
            if (homeSection == null) {
                storageHealthy = false;
                plugin.getLogger().severe("У записи игрока " + playerKey
                    + " отсутствует корректный раздел homes. Файл оставлен без изменений.");
                continue;
            }

            for (String storedSlot : homeSection.getKeys(false)) {
                if (!storedSlot.equals("1") && !storedSlot.equals("2")) {
                    storageHealthy = false;
                    plugin.getLogger().severe("В homes.yml найден неизвестный слот " + storedSlot
                        + ". Файл оставлен без изменений.");
                }
            }

            Map<Integer, HomePoint> loaded = new HashMap<>();
            for (int slot = 1; slot <= MAX_HOMES; slot++) {
                ConfigurationSection section = homeSection.getConfigurationSection(Integer.toString(slot));
                if (section == null) {
                    if (homeSection.contains(Integer.toString(slot))) {
                        storageHealthy = false;
                        plugin.getLogger().severe("Слот " + slot + " игрока " + playerKey
                            + " в homes.yml имеет неверный формат. Файл оставлен без изменений.");
                    }
                    continue;
                }

                try {
                    loaded.put(slot, readPoint(section, slot));
                } catch (IllegalArgumentException error) {
                    storageHealthy = false;
                    plugin.getLogger().log(
                        Level.SEVERE,
                        "Дом " + slot + " игрока " + playerId
                            + " в homes.yml повреждён. Изменение домов отключено, файл не перезаписывается.",
                        error
                    );
                }
            }

            if (!loaded.isEmpty()) homes.put(playerId, loaded);
        }
    }

    private HomePoint readPoint(ConfigurationSection section, int slot) {
        String world = section.getString("world", "");
        if (world == null) world = "";
        world = world.trim();
        if (world.isEmpty() || world.length() > 128) {
            throw new IllegalArgumentException("Неверное имя мира");
        }

        double x = number(section, "x");
        double y = number(section, "y");
        double z = number(section, "z");
        double yawValue = section.contains("yaw") ? number(section, "yaw") : 0.0;
        double pitchValue = section.contains("pitch") ? number(section, "pitch") : 0.0;
        if (!validCoordinates(x, y, z)
            || !Double.isFinite(yawValue)
            || !Double.isFinite(pitchValue)
            || Math.abs(yawValue) > 36000.0
            || Math.abs(pitchValue) > 360.0) {
            throw new IllegalArgumentException("Неверные координаты или направление");
        }

        String name = section.getString("name", "Дом " + slot);
        if (name == null || name.isBlank() || name.length() > 32) name = "Дом " + slot;
        return new HomePoint(name, world, x, y, z, (float) yawValue, (float) pitchValue);
    }

    private static double number(ConfigurationSection section, String key) {
        Object value = section.get(key);
        if (!(value instanceof Number number)) {
            throw new IllegalArgumentException("Поле " + key + " отсутствует или не является числом");
        }
        return number.doubleValue();
    }

    private boolean persistSnapshot(Map<UUID, Map<Integer, HomePoint>> snapshot) {
        Path temporaryFile = storageFile.toPath().resolveSibling("homes.yml.tmp");
        try {
            Files.createDirectories(storageFile.toPath().getParent());
            YamlConfiguration yaml = new YamlConfiguration();

            for (Map.Entry<UUID, Map<Integer, HomePoint>> playerEntry : snapshot.entrySet()) {
                for (Map.Entry<Integer, HomePoint> homeEntry : playerEntry.getValue().entrySet()) {
                    String base = "players." + playerEntry.getKey()
                        + ".homes." + homeEntry.getKey();
                    HomePoint point = homeEntry.getValue();
                    yaml.set(base + ".name", point.name());
                    yaml.set(base + ".world", point.world());
                    yaml.set(base + ".x", point.x());
                    yaml.set(base + ".y", point.y());
                    yaml.set(base + ".z", point.z());
                    yaml.set(base + ".yaw", point.yaw());
                    yaml.set(base + ".pitch", point.pitch());
                }
            }

            yaml.save(temporaryFile.toFile());
            try {
                Files.move(
                    temporaryFile,
                    storageFile.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.ATOMIC_MOVE
                );
            } catch (AtomicMoveNotSupportedException ignored) {
                Files.move(temporaryFile, storageFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
            return true;
        } catch (IOException | RuntimeException error) {
            try {
                Files.deleteIfExists(temporaryFile);
            } catch (IOException cleanupError) {
                plugin.getLogger().log(Level.WARNING, "Не удалось удалить временный файл homes.yml.tmp.", cleanupError);
            }
            plugin.getLogger().log(
                Level.SEVERE,
                "Не удалось сохранить homes.yml. Изменение будет отменено, если после него не было новых операций.",
                error
            );
            return false;
        }
    }

    private Map<UUID, Map<Integer, HomePoint>> snapshotLocked() {
        Map<UUID, Map<Integer, HomePoint>> snapshot = new HashMap<>();
        for (Map.Entry<UUID, Map<Integer, HomePoint>> entry : homes.entrySet()) {
            snapshot.put(entry.getKey(), Map.copyOf(entry.getValue()));
        }
        return Map.copyOf(snapshot);
    }

    private void restorePersistedSnapshotLocked() {
        homes.clear();
        for (Map.Entry<UUID, Map<Integer, HomePoint>> entry : persistedSnapshot.entrySet()) {
            homes.put(entry.getKey(), new HashMap<>(entry.getValue()));
        }
        revision++;
    }

    private static boolean validSlot(int slot) {
        return slot >= 1 && slot <= MAX_HOMES;
    }

    private static boolean validLocation(Location location) {
        return location != null
            && location.getWorld() != null
            && location.getWorld().getName().length() <= 128
            && validCoordinates(location.getX(), location.getY(), location.getZ())
            && Float.isFinite(location.getYaw())
            && Float.isFinite(location.getPitch());
    }

    private static boolean validCoordinates(double x, double y, double z) {
        return Double.isFinite(x)
            && Double.isFinite(y)
            && Double.isFinite(z)
            && Math.abs(x) <= 30_000_000.0
            && y >= -2048.0
            && y <= 4096.0
            && Math.abs(z) <= 30_000_000.0;
    }

    @Override
    public void close() {
        synchronized (this) {
            closed = true;
        }
        writer.shutdown();
        try {
            if (!writer.awaitTermination(5, TimeUnit.SECONDS)) {
                plugin.getLogger().warning("Сохранение домов ещё выполняется после 5 секунд ожидания.");
            }
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            plugin.getLogger().warning("Ожидание сохранения домов было прервано; очередь не будет принудительно очищена.");
        }
    }
}
