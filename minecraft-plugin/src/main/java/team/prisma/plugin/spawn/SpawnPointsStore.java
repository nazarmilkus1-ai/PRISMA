package team.prisma.plugin.spawn;

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
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;

/**
 * Локальное постоянное хранилище точек появления конкретного Paper-сервера.
 * Слот 0 — необязательная переопределённая основная точка; если её нет, используется spawn первого мира.
 * Файловые записи идут последовательно в отдельном потоке и не блокируют игровой поток.
 */
public final class SpawnPointsStore implements AutoCloseable {
    public static final int MAIN_SPAWN_ID = 0;
    public static final int MAX_CUSTOM_SPAWN_ID = 999;

    public record SpawnPoint(
        int id,
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
    private final Map<Integer, SpawnPoint> spawns = new HashMap<>();
    private final ExecutorService writer = Executors.newSingleThreadExecutor(task -> {
        Thread thread = new Thread(task, "PRISMA-SpawnStorage");
        thread.setDaemon(true);
        return thread;
    });
    private volatile boolean storageHealthy = true;
    private volatile boolean closed;

    public SpawnPointsStore(JavaPlugin plugin) {
        this.plugin = plugin;
        this.storageFile = new File(plugin.getDataFolder(), "spawns.yml");
        load();
    }

    public synchronized boolean isStorageHealthy() {
        return storageHealthy;
    }

    public synchronized SpawnPoint get(int id) {
        if (!validId(id)) return null;
        return spawns.get(id);
    }

    public synchronized Map<Integer, SpawnPoint> list() {
        return Collections.unmodifiableMap(new TreeMap<>(spawns));
    }

    public CompletableFuture<Boolean> set(int id, String name, Location location) {
        if (!storageHealthy || closed || !validId(id) || !validName(name) || !validLocation(location)) {
            return CompletableFuture.completedFuture(false);
        }

        SpawnPoint point = new SpawnPoint(
            id,
            name.trim(),
            location.getWorld().getName(),
            location.getX(),
            location.getY(),
            location.getZ(),
            location.getYaw(),
            location.getPitch()
        );
        return enqueueMutation(() -> {
            Map<Integer, SpawnPoint> persistedSnapshot;
            synchronized (this) {
                if (!storageHealthy) return false;
                persistedSnapshot = new TreeMap<>(spawns);
                persistedSnapshot.put(id, point);
            }

            if (!persist(persistedSnapshot)) return false;
            synchronized (this) {
                spawns.clear();
                spawns.putAll(persistedSnapshot);
            }
            return true;
        });
    }

    public CompletableFuture<Boolean> delete(int id) {
        if (!storageHealthy || closed || !validId(id)) {
            return CompletableFuture.completedFuture(false);
        }

        return enqueueMutation(() -> {
            Map<Integer, SpawnPoint> persistedSnapshot;
            synchronized (this) {
                if (!storageHealthy || !spawns.containsKey(id)) return false;
                persistedSnapshot = new TreeMap<>(spawns);
                persistedSnapshot.remove(id);
            }

            if (!persist(persistedSnapshot)) return false;
            synchronized (this) {
                spawns.clear();
                spawns.putAll(persistedSnapshot);
            }
            return true;
        });
    }

    private CompletableFuture<Boolean> enqueueMutation(java.util.function.Supplier<Boolean> operation) {
        CompletableFuture<Boolean> result = new CompletableFuture<>();
        try {
            writer.execute(() -> {
                try {
                    result.complete(operation.get());
                } catch (RuntimeException error) {
                    storageHealthy = false;
                    plugin.getLogger().log(Level.SEVERE,
                        "Ошибка очереди сохранения spawns.yml; изменения точек отключены.", error);
                    result.complete(false);
                }
            });
        } catch (RejectedExecutionException error) {
            plugin.getLogger().log(Level.WARNING,
                "Очередь записи spawns.yml уже закрыта; изменение не принято.", error);
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
            markUnhealthy("Не удалось прочитать spawns.yml. Изменение точек появления отключено.", error);
            return;
        }

        if (yaml.getKeys(false).isEmpty()) return;
        if (!yaml.getKeys(false).equals(java.util.Set.of("spawns"))) {
            markUnhealthy("В spawns.yml обнаружена неизвестная структура верхнего уровня.");
        }

        ConfigurationSection section = yaml.getConfigurationSection("spawns");
        if (section == null) {
            markUnhealthy("В существующем spawns.yml отсутствует раздел spawns; файл не будет перезаписан.");
            return;
        }

        for (String rawId : section.getKeys(false)) {
            int id;
            try {
                id = Integer.parseInt(rawId);
            } catch (NumberFormatException error) {
                markUnhealthy("В spawns.yml найден неверный номер точки: " + rawId);
                continue;
            }
            if (!validId(id) || !Integer.toString(id).equals(rawId)) {
                markUnhealthy("В spawns.yml найден неподдерживаемый номер точки: " + rawId);
                continue;
            }

            ConfigurationSection point = section.getConfigurationSection(rawId);
            if (point == null) {
                markUnhealthy("Точка " + rawId + " в spawns.yml не является секцией.");
                continue;
            }
            if (!java.util.Set.of("name", "world", "x", "y", "z", "yaw", "pitch")
                .containsAll(point.getKeys(false))) {
                markUnhealthy("Точка " + rawId + " содержит неизвестные поля; файл не будет перезаписан.");
            }

            try {
                spawns.put(id, readPoint(point, id));
            } catch (IllegalArgumentException error) {
                markUnhealthy("Точка " + rawId + " в spawns.yml повреждена; файл не будет перезаписан.", error);
            }
        }
    }

    private SpawnPoint readPoint(ConfigurationSection section, int id) {
        String name = section.getString("name", "");
        String world = section.getString("world", "");
        if (name == null || world == null || !validName(name) || world.isBlank() || world.length() > 128) {
            throw new IllegalArgumentException("Неверное имя точки или мира");
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
            throw new IllegalArgumentException("Недопустимые координаты или направление");
        }
        return new SpawnPoint(id, name.trim(), world.trim(), x, y, z, (float) yawValue, (float) pitchValue);
    }

    private static double number(ConfigurationSection section, String key) {
        Object value = section.get(key);
        if (!(value instanceof Number number)) {
            throw new IllegalArgumentException("Поле " + key + " отсутствует или не является числом");
        }
        return number.doubleValue();
    }

    private boolean persist(Map<Integer, SpawnPoint> persistedSnapshot) {
        Path temporaryFile = storageFile.toPath().resolveSibling("spawns.yml.tmp");
        try {
            Files.createDirectories(storageFile.toPath().getParent());
            YamlConfiguration yaml = new YamlConfiguration();
            for (Map.Entry<Integer, SpawnPoint> entry : persistedSnapshot.entrySet()) {
                int id = entry.getKey();
                SpawnPoint point = entry.getValue();
                String base = "spawns." + id;
                yaml.set(base + ".name", point.name());
                yaml.set(base + ".world", point.world());
                yaml.set(base + ".x", point.x());
                yaml.set(base + ".y", point.y());
                yaml.set(base + ".z", point.z());
                yaml.set(base + ".yaw", point.yaw());
                yaml.set(base + ".pitch", point.pitch());
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
            storageHealthy = false;
            try {
                Files.deleteIfExists(temporaryFile);
            } catch (IOException cleanupError) {
                plugin.getLogger().log(Level.WARNING, "Не удалось удалить временный файл spawns.yml.tmp.", cleanupError);
            }
            plugin.getLogger().log(
                Level.SEVERE,
                "Не удалось сохранить spawns.yml. Изменение отменено, прежние точки сохранены в памяти.",
                error
            );
            return false;
        }
    }

    private void markUnhealthy(String message) {
        storageHealthy = false;
        plugin.getLogger().severe(message);
    }

    private void markUnhealthy(String message, Throwable error) {
        storageHealthy = false;
        plugin.getLogger().log(Level.SEVERE, message, error);
    }

    @Override
    public void close() {
        closed = true;
        writer.shutdown();
        try {
            if (!writer.awaitTermination(5, TimeUnit.SECONDS)) {
                writer.shutdownNow();
                if (!writer.awaitTermination(1, TimeUnit.SECONDS)) {
                    plugin.getLogger().warning("Очередь spawns.yml не завершилась после тайм-аута.");
                }
            }
        } catch (InterruptedException error) {
            writer.shutdownNow();
            Thread.currentThread().interrupt();
            plugin.getLogger().log(Level.WARNING, "Ожидание записи spawns.yml прервано.", error);
        }
    }

    private static boolean validId(int id) {
        return id >= MAIN_SPAWN_ID && id <= MAX_CUSTOM_SPAWN_ID;
    }

    private static boolean validName(String name) {
        return name != null && !name.isBlank() && name.trim().length() <= 40
            && name.trim().chars().noneMatch(Character::isISOControl);
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
}
