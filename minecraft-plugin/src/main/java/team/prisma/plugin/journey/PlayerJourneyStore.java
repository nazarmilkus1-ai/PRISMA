package team.prisma.plugin.journey;

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
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;
import java.util.logging.Level;
import java.util.regex.Pattern;

/**
 * Локальное хранилище контрольных точек и последнего места смерти.
 * Все изменения сериализуются в отдельной очереди и публикуются в памяти только после записи на диск.
 */
public final class PlayerJourneyStore implements AutoCloseable {
    public static final int MAX_CHECKPOINTS = 5;
    private static final Pattern CHECKPOINT_NAME = Pattern.compile("^[\\p{L}\\p{N}_-]{1,16}$");

    public enum MutationResult {
        SAVED, DELETED, LIMIT_REACHED, NOT_FOUND, UNAVAILABLE, FAILED
    }

    public record Point(
        String world,
        double x,
        double y,
        double z,
        float yaw,
        float pitch,
        long recordedAtEpochMilli
    ) {
        public static Point capture(Location location, long timestamp) {
            if (location == null || location.getWorld() == null
                || !validCoordinates(location.getX(), location.getY(), location.getZ())
                || !Float.isFinite(location.getYaw()) || !Float.isFinite(location.getPitch())) {
                return null;
            }
            String world = location.getWorld().getName();
            if (world == null || world.isBlank() || world.length() > 128) return null;
            return new Point(world, location.getX(), location.getY(), location.getZ(),
                location.getYaw(), location.getPitch(), Math.max(0L, timestamp));
        }
    }

    private record PlayerJourney(Point lastDeath, Map<String, Point> checkpoints) {
        private PlayerJourney {
            checkpoints = Collections.unmodifiableMap(new TreeMap<>(checkpoints));
        }

        static PlayerJourney empty() {
            return new PlayerJourney(null, Map.of());
        }
    }

    private final JavaPlugin plugin;
    private final File storageFile;
    private final Map<UUID, PlayerJourney> journeys = new HashMap<>();
    private final ExecutorService writer = Executors.newSingleThreadExecutor(task -> {
        Thread thread = new Thread(task, "PRISMA-JourneyStorage");
        thread.setDaemon(true);
        return thread;
    });
    private volatile boolean storageHealthy = true;
    private volatile boolean closed;

    public PlayerJourneyStore(JavaPlugin plugin) {
        this.plugin = plugin;
        this.storageFile = new File(plugin.getDataFolder(), "journey.yml");
        load();
    }

    public synchronized boolean isStorageHealthy() {
        return storageHealthy;
    }

    public synchronized Point lastDeath(UUID playerId) {
        PlayerJourney data = journeys.get(playerId);
        return data == null ? null : data.lastDeath();
    }

    public synchronized Map<String, Point> checkpoints(UUID playerId) {
        PlayerJourney data = journeys.get(playerId);
        return data == null ? Map.of() : data.checkpoints();
    }

    public synchronized Point checkpoint(UUID playerId, String name) {
        if (name == null) return null;
        PlayerJourney data = journeys.get(playerId);
        return data == null ? null : data.checkpoints().get(normalizeName(name));
    }

    public CompletableFuture<MutationResult> recordDeath(UUID playerId, Point point) {
        if (playerId == null || !validPoint(point)) {
            return CompletableFuture.completedFuture(MutationResult.FAILED);
        }
        return submit(snapshot -> {
            PlayerJourney current = snapshot.getOrDefault(playerId, PlayerJourney.empty());
            snapshot.put(playerId, new PlayerJourney(point, current.checkpoints()));
            return MutationResult.SAVED;
        });
    }

    public CompletableFuture<MutationResult> setCheckpoint(UUID playerId, String name, Point point) {
        if (playerId == null || !validName(name) || !validPoint(point)) {
            return CompletableFuture.completedFuture(MutationResult.FAILED);
        }
        String key = normalizeName(name);
        return submit(snapshot -> {
            PlayerJourney current = snapshot.getOrDefault(playerId, PlayerJourney.empty());
            if (!current.checkpoints().containsKey(key)
                && current.checkpoints().size() >= MAX_CHECKPOINTS) {
                return MutationResult.LIMIT_REACHED;
            }
            Map<String, Point> next = new TreeMap<>(current.checkpoints());
            next.put(key, point);
            snapshot.put(playerId, new PlayerJourney(current.lastDeath(), next));
            return MutationResult.SAVED;
        });
    }

    public CompletableFuture<MutationResult> deleteCheckpoint(UUID playerId, String name) {
        if (playerId == null || !validName(name)) {
            return CompletableFuture.completedFuture(MutationResult.FAILED);
        }
        String key = normalizeName(name);
        return submit(snapshot -> {
            PlayerJourney current = snapshot.get(playerId);
            if (current == null || !current.checkpoints().containsKey(key)) {
                return MutationResult.NOT_FOUND;
            }
            Map<String, Point> next = new TreeMap<>(current.checkpoints());
            next.remove(key);
            if (next.isEmpty() && current.lastDeath() == null) snapshot.remove(playerId);
            else snapshot.put(playerId, new PlayerJourney(current.lastDeath(), next));
            return MutationResult.DELETED;
        });
    }

    private CompletableFuture<MutationResult> submit(Function<Map<UUID, PlayerJourney>, MutationResult> change) {
        CompletableFuture<MutationResult> result = new CompletableFuture<>();
        if (!storageHealthy || closed) {
            return CompletableFuture.completedFuture(MutationResult.UNAVAILABLE);
        }
        try {
            writer.execute(() -> {
                try {
                    Map<UUID, PlayerJourney> snapshot;
                    synchronized (this) {
                        // close() rejects new work but lets already queued writes drain.
                        if (!storageHealthy) {
                            result.complete(MutationResult.UNAVAILABLE);
                            return;
                        }
                        snapshot = new HashMap<>(journeys);
                    }
                    MutationResult outcome = change.apply(snapshot);
                    if (outcome != MutationResult.SAVED && outcome != MutationResult.DELETED) {
                        result.complete(outcome);
                        return;
                    }
                    if (!persist(snapshot)) {
                        storageHealthy = false;
                        result.complete(MutationResult.FAILED);
                        return;
                    }
                    synchronized (this) {
                        journeys.clear();
                        journeys.putAll(snapshot);
                    }
                    result.complete(outcome);
                } catch (RuntimeException error) {
                    storageHealthy = false;
                    plugin.getLogger().log(Level.SEVERE,
                        "Ошибка очереди сохранения journey.yml; изменение контрольных точек отключено.", error);
                    result.complete(MutationResult.FAILED);
                }
            });
        } catch (RejectedExecutionException error) {
            plugin.getLogger().log(Level.WARNING,
                "Очередь journey.yml уже закрыта; изменение не принято.", error);
            result.complete(MutationResult.UNAVAILABLE);
        }
        return result;
    }

    private void load() {
        if (!storageFile.exists()) return;
        YamlConfiguration yaml = new YamlConfiguration();
        try {
            yaml.load(storageFile);
        } catch (IOException | InvalidConfigurationException error) {
            markUnhealthy("Не удалось прочитать journey.yml. Изменение контрольных точек отключено.", error);
            return;
        }

        if (yaml.getKeys(false).isEmpty()) return;
        if (!yaml.getKeys(false).equals(java.util.Set.of("players"))) {
            markUnhealthy("В journey.yml обнаружена неизвестная структура верхнего уровня.");
        }
        ConfigurationSection players = yaml.getConfigurationSection("players");
        if (players == null) {
            markUnhealthy("В существующем journey.yml отсутствует раздел players; файл не будет перезаписан.");
            return;
        }

        for (String rawUuid : players.getKeys(false)) {
            UUID playerId;
            try {
                playerId = UUID.fromString(rawUuid);
            } catch (IllegalArgumentException error) {
                markUnhealthy("В journey.yml найден неверный UUID; исходный файл не будет перезаписан.");
                continue;
            }
            ConfigurationSection player = players.getConfigurationSection(rawUuid);
            if (player == null || !java.util.Set.of("last_death", "checkpoints").containsAll(player.getKeys(false))) {
                markUnhealthy("Запись игрока " + playerId + " имеет неизвестную структуру в journey.yml.");
                continue;
            }

            if (player.isSet("last_death") && player.getConfigurationSection("last_death") == null) {
                markUnhealthy("Поле last_death игрока " + playerId + " не является секцией; файл не будет перезаписан.");
            }
            if (player.isSet("checkpoints") && player.getConfigurationSection("checkpoints") == null) {
                markUnhealthy("Поле checkpoints игрока " + playerId + " не является секцией; файл не будет перезаписан.");
            }

            Point lastDeath = null;
            ConfigurationSection deathSection = player.getConfigurationSection("last_death");
            if (deathSection != null) {
                if (!validFields(deathSection)) {
                    markUnhealthy("Последнее место смерти игрока " + playerId + " содержит неизвестные поля.");
                }
                try {
                    lastDeath = readPoint(deathSection);
                } catch (IllegalArgumentException error) {
                    markUnhealthy("Последнее место смерти игрока " + playerId + " повреждено.", error);
                }
            }

            Map<String, Point> points = new TreeMap<>();
            ConfigurationSection checkpointSection = player.getConfigurationSection("checkpoints");
            if (checkpointSection != null) {
                for (String name : checkpointSection.getKeys(false)) {
                    if (!validName(name) || !name.equals(normalizeName(name))) {
                        markUnhealthy("В journey.yml найдено неверное имя контрольной точки: " + name);
                        continue;
                    }
                    ConfigurationSection pointSection = checkpointSection.getConfigurationSection(name);
                    if (pointSection == null || !validFields(pointSection)) {
                        markUnhealthy("Контрольная точка «" + name + "» игрока " + playerId + " имеет неизвестную структуру.");
                        continue;
                    }
                    try {
                        points.put(name, readPoint(pointSection));
                    } catch (IllegalArgumentException error) {
                        markUnhealthy("Контрольная точка «" + name + "» игрока " + playerId + " повреждена.", error);
                    }
                }
            }
            if (points.size() > MAX_CHECKPOINTS) {
                markUnhealthy("У игрока " + playerId + " больше " + MAX_CHECKPOINTS + " контрольных точек; файл не будет перезаписан.");
            }
            if (lastDeath != null || !points.isEmpty()) {
                journeys.put(playerId, new PlayerJourney(lastDeath, points));
            }
        }
    }

    private static boolean validFields(ConfigurationSection section) {
        return java.util.Set.of("world", "x", "y", "z", "yaw", "pitch", "recorded_at")
            .equals(section.getKeys(false));
    }

    private static Point readPoint(ConfigurationSection section) {
        String world = section.getString("world", "");
        if (world == null || world.isBlank() || world.length() > 128) {
            throw new IllegalArgumentException("Неверное имя мира");
        }
        double x = number(section, "x");
        double y = number(section, "y");
        double z = number(section, "z");
        double yaw = number(section, "yaw");
        double pitch = number(section, "pitch");
        long recordedAt = section.getLong("recorded_at", 0L);
        if (!validCoordinates(x, y, z) || !Double.isFinite(yaw) || !Double.isFinite(pitch)
            || Math.abs(yaw) > 36000.0 || Math.abs(pitch) > 360.0 || recordedAt < 0L) {
            throw new IllegalArgumentException("Недопустимые координаты или timestamp");
        }
        return new Point(world, x, y, z, (float) yaw, (float) pitch, recordedAt);
    }

    private boolean persist(Map<UUID, PlayerJourney> snapshot) {
        Path temporary = storageFile.toPath().resolveSibling("journey.yml.tmp");
        try {
            Files.createDirectories(storageFile.toPath().getParent());
            YamlConfiguration yaml = new YamlConfiguration();
            for (Map.Entry<UUID, PlayerJourney> entry : snapshot.entrySet()) {
                String base = "players." + entry.getKey();
                PlayerJourney data = entry.getValue();
                if (data.lastDeath() != null) writePoint(yaml, base + ".last_death", data.lastDeath());
                for (Map.Entry<String, Point> checkpoint : data.checkpoints().entrySet()) {
                    writePoint(yaml, base + ".checkpoints." + checkpoint.getKey(), checkpoint.getValue());
                }
            }
            yaml.save(temporary.toFile());
            try {
                Files.move(temporary, storageFile.toPath(),
                    StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException ignored) {
                Files.move(temporary, storageFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
            return true;
        } catch (IOException | RuntimeException error) {
            try {
                Files.deleteIfExists(temporary);
            } catch (IOException cleanupError) {
                plugin.getLogger().log(Level.WARNING, "Не удалось удалить временный файл journey.yml.tmp.", cleanupError);
            }
            plugin.getLogger().log(Level.SEVERE,
                "Не удалось сохранить journey.yml. Изменение отменено; проверьте свободное место и журнал.", error);
            return false;
        }
    }

    private static void writePoint(YamlConfiguration yaml, String base, Point point) {
        yaml.set(base + ".world", point.world());
        yaml.set(base + ".x", point.x());
        yaml.set(base + ".y", point.y());
        yaml.set(base + ".z", point.z());
        yaml.set(base + ".yaw", point.yaw());
        yaml.set(base + ".pitch", point.pitch());
        yaml.set(base + ".recorded_at", point.recordedAtEpochMilli());
    }

    private void markUnhealthy(String message) {
        storageHealthy = false;
        plugin.getLogger().severe(message);
    }

    private void markUnhealthy(String message, Throwable error) {
        storageHealthy = false;
        plugin.getLogger().log(Level.SEVERE, message, error);
    }

    private static boolean validName(String name) {
        return name != null && CHECKPOINT_NAME.matcher(name).matches();
    }

    private static String normalizeName(String name) {
        return name.trim().toLowerCase(Locale.ROOT);
    }

    private static boolean validPoint(Point point) {
        return point != null && point.world() != null && !point.world().isBlank()
            && point.world().length() <= 128
            && validCoordinates(point.x(), point.y(), point.z())
            && Float.isFinite(point.yaw()) && Float.isFinite(point.pitch())
            && point.recordedAtEpochMilli() >= 0L;
    }

    private static boolean validCoordinates(double x, double y, double z) {
        return Double.isFinite(x) && Double.isFinite(y) && Double.isFinite(z)
            && Math.abs(x) <= 30_000_000.0 && y >= -2048.0 && y <= 4096.0
            && Math.abs(z) <= 30_000_000.0;
    }

    private static double number(ConfigurationSection section, String key) {
        Object value = section.get(key);
        if (!(value instanceof Number number)) {
            throw new IllegalArgumentException("Поле " + key + " отсутствует или не является числом");
        }
        return number.doubleValue();
    }

    @Override
    public void close() {
        closed = true;
        writer.shutdown();
        try {
            if (!writer.awaitTermination(5, TimeUnit.SECONDS)) {
                writer.shutdownNow();
                if (!writer.awaitTermination(1, TimeUnit.SECONDS)) {
                    plugin.getLogger().warning("Очередь journey.yml не завершилась после тайм-аута.");
                }
            }
        } catch (InterruptedException error) {
            writer.shutdownNow();
            Thread.currentThread().interrupt();
            plugin.getLogger().log(Level.WARNING, "Ожидание записи journey.yml прервано.", error);
        }
    }
}
