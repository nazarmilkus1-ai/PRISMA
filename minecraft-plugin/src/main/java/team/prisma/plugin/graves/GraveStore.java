package team.prisma.plugin.graves;

import org.bukkit.Location;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.configuration.InvalidConfigurationException;
import org.bukkit.inventory.ItemStack;
import org.bukkit.plugin.java.JavaPlugin;

import java.io.File;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;

/**
 * Local, fail-closed grave storage. Every grave has its own atomic YAML file.
 * The death drop list is only cleared after its file has been durably written.
 */
public final class GraveStore {
    public static final long TTL_MILLIS = TimeUnit.MINUTES.toMillis(10);
    public static final int MAX_GRAVES = 256;
    public static final int MAX_ITEMS_PER_GRAVE = 256;

    private static final Set<String> REQUIRED_FIELDS = Set.of(
        "schema_version", "id", "owner", "owner_name", "world",
        "x", "y", "z", "created_at", "expires_at", "items", "status"
    );
    private static final Set<String> ALLOWED_FIELDS = Set.of(
        "schema_version", "id", "owner", "owner_name", "world",
        "x", "y", "z", "created_at", "expires_at", "items", "status",
        "marker_entity", "claim_id", "claimant"
    );

    public enum Result {
        SAVED, EMPTY, NOT_FOUND, EXPIRED, FORBIDDEN, ALREADY_CLAIMING,
        STORAGE_UNAVAILABLE, CAPACITY, FAILED
    }

    public enum State { PENDING, CLAIMING }

    public record Operation(Result result, Grave grave) {}

    public record Grave(
        String id,
        UUID ownerId,
        String ownerName,
        String world,
        double x,
        double y,
        double z,
        long createdAtEpochMilli,
        long expiresAtEpochMilli,
        List<ItemStack> items,
        UUID markerEntityId,
        State state,
        String claimId,
        UUID claimantId
    ) {
        public Grave {
            items = items == null
                ? List.of()
                : Collections.unmodifiableList(items.stream().map(ItemStack::clone).toList());
        }

        @Override
        public List<ItemStack> items() {
            return items.stream().map(ItemStack::clone).toList();
        }

        public boolean expired(long now) {
            return state == State.PENDING && now >= expiresAtEpochMilli;
        }

        Grave withMarker(UUID markerId) {
            return new Grave(id, ownerId, ownerName, world, x, y, z,
                createdAtEpochMilli, expiresAtEpochMilli, items, markerId, state, claimId, claimantId);
        }

        Grave claiming(String transactionId, UUID claimant) {
            return new Grave(id, ownerId, ownerName, world, x, y, z,
                createdAtEpochMilli, expiresAtEpochMilli, items, markerEntityId,
                State.CLAIMING, transactionId, claimant);
        }

        Grave pending() {
            return new Grave(id, ownerId, ownerName, world, x, y, z,
                createdAtEpochMilli, expiresAtEpochMilli, items, markerEntityId,
                State.PENDING, null, null);
        }
    }

    private final JavaPlugin plugin;
    private final File directory;
    private final Map<String, Grave> graves = new HashMap<>();
    private volatile boolean storageHealthy = true;

    public GraveStore(JavaPlugin plugin) {
        this.plugin = plugin;
        this.directory = new File(plugin.getDataFolder(), "graves");
        load();
    }

    public synchronized boolean isStorageHealthy() {
        return storageHealthy;
    }

    public synchronized Operation create(
        UUID ownerId, String ownerName, Location deathLocation, List<ItemStack> drops, long now
    ) {
        if (!storageHealthy) return new Operation(Result.STORAGE_UNAVAILABLE, null);
        if (ownerId == null || ownerName == null || ownerName.isBlank() || ownerName.length() > 64
            || deathLocation == null || deathLocation.getWorld() == null
            || !validLocation(deathLocation.getX(), deathLocation.getY(), deathLocation.getZ())) {
            return new Operation(Result.FAILED, null);
        }

        List<ItemStack> safeItems = new ArrayList<>();
        if (drops != null) {
            for (ItemStack item : drops) {
                if (item == null || item.getType().isAir() || item.getAmount() <= 0) continue;
                safeItems.add(item.clone());
            }
        }
        if (safeItems.isEmpty()) return new Operation(Result.EMPTY, null);
        if (safeItems.size() > MAX_ITEMS_PER_GRAVE) return new Operation(Result.CAPACITY, null);

        pruneExpired(now);
        if (!storageHealthy) return new Operation(Result.STORAGE_UNAVAILABLE, null);
        if (graves.size() >= MAX_GRAVES) return new Operation(Result.CAPACITY, null);

        String id = newId();
        Grave grave = new Grave(id, ownerId, ownerName, deathLocation.getWorld().getName(),
            deathLocation.getX(), deathLocation.getY(), deathLocation.getZ(),
            now, now + TTL_MILLIS, safeItems, null, State.PENDING, null, null);

        if (!saveRecord(grave)) return new Operation(Result.FAILED, null);
        graves.put(id, grave);
        return new Operation(Result.SAVED, grave);
    }

    public synchronized List<Grave> list(UUID ownerId, boolean includeAll, long now) {
        pruneExpired(now);
        return graves.values().stream()
            .filter(grave -> grave.state() == State.PENDING && !grave.expired(now))
            .filter(grave -> includeAll || grave.ownerId().equals(ownerId))
            .sorted((left, right) -> Long.compare(right.createdAtEpochMilli(), left.createdAtEpochMilli()))
            .toList();
    }

    public synchronized Grave pending(String id, long now) {
        pruneExpired(now);
        Grave grave = graves.get(normalizeId(id));
        return grave == null || grave.state() != State.PENDING || grave.expired(now) ? null : grave;
    }

    public synchronized boolean hasActivePending(String id, long now) {
        Grave grave = graves.get(normalizeId(id));
        return grave != null && grave.state() == State.PENDING && !grave.expired(now);
    }

    public synchronized List<Grave> claimingFor(UUID claimantId) {
        return graves.values().stream()
            .filter(grave -> grave.state() == State.CLAIMING && claimantId.equals(grave.claimantId()))
            .toList();
    }

    public synchronized List<Grave> allRecords() {
        return List.copyOf(graves.values());
    }

    public synchronized Operation beginClaim(String id, UUID claimantId, boolean admin, long now) {
        if (!storageHealthy) return new Operation(Result.STORAGE_UNAVAILABLE, null);
        String key = normalizeId(id);
        Grave grave = graves.get(key);
        if (grave == null) return new Operation(Result.NOT_FOUND, null);
        if (grave.state() == State.CLAIMING) return new Operation(Result.ALREADY_CLAIMING, grave);
        if (grave.expired(now)) {
            pruneExpired(now);
            return new Operation(Result.EXPIRED, null);
        }
        if (!admin && !grave.ownerId().equals(claimantId)) {
            return new Operation(Result.FORBIDDEN, null);
        }
        String transactionId = UUID.randomUUID().toString();
        Grave claiming = grave.claiming(transactionId, claimantId);
        if (!saveRecord(claiming)) return new Operation(Result.FAILED, null);
        graves.put(key, claiming);
        return new Operation(Result.SAVED, claiming);
    }

    public synchronized boolean completeClaim(String id, String transactionId) {
        if (!storageHealthy) return false;
        Grave grave = graves.get(normalizeId(id));
        if (grave == null || grave.state() != State.CLAIMING
            || transactionId == null || !transactionId.equals(grave.claimId())) {
            return false;
        }
        if (!deleteRecordFile(grave.id())) return false;
        graves.remove(grave.id());
        return true;
    }

    public synchronized boolean rollbackClaim(String id, String transactionId) {
        if (!storageHealthy) return false;
        Grave grave = graves.get(normalizeId(id));
        if (grave == null || grave.state() != State.CLAIMING
            || transactionId == null || !transactionId.equals(grave.claimId())) {
            return false;
        }
        Grave pending = grave.pending();
        if (!saveRecord(pending)) return false;
        graves.put(pending.id(), pending);
        return true;
    }

    public synchronized boolean attachMarker(String id, UUID markerEntityId) {
        if (!storageHealthy || markerEntityId == null) return false;
        Grave grave = graves.get(normalizeId(id));
        if (grave == null || grave.state() != State.PENDING) return false;
        Grave updated = grave.withMarker(markerEntityId);
        if (!saveRecord(updated)) return false;
        graves.put(updated.id(), updated);
        return true;
    }

    public synchronized void pruneExpired(long now) {
        if (!storageHealthy) return;
        for (Grave grave : new ArrayList<>(graves.values())) {
            if (grave.state() != State.PENDING || !grave.expired(now)) continue;
            if (!deleteRecordFile(grave.id())) return;
            graves.remove(grave.id());
        }
    }

    private void load() {
        try {
            Files.createDirectories(directory.toPath());
            File[] files = directory.listFiles((parent, name) -> name.endsWith(".yml"));
            if (files == null) {
                markUnhealthy("Не удалось прочитать каталог могил; изменения отключены.");
                return;
            }
            for (File file : files) {
                String filename = file.getName();
                if (!filename.matches("[a-f0-9]{8}\\.yml")) {
                    markUnhealthy("В каталоге могил найден файл неизвестного формата: " + filename);
                    continue;
                }
                Grave grave = readRecord(file);
                if (grave == null) continue;
                if (!grave.id().equals(filename.substring(0, filename.length() - 4))
                    || graves.putIfAbsent(grave.id(), grave) != null) {
                    markUnhealthy("В каталоге могил найден повторяющийся или несогласованный ID.");
                }
            }
            if (graves.size() > MAX_GRAVES) {
                markUnhealthy("Количество могил превышает безопасный лимит; файлы не изменяются.");
            }
        } catch (IOException error) {
            markUnhealthy("Не удалось открыть каталог могил; данные не будут перезаписаны.", error);
        }
    }

    private Grave readRecord(File file) {
        YamlConfiguration yaml = new YamlConfiguration();
        try {
            yaml.load(file);
        } catch (IOException | InvalidConfigurationException error) {
            markUnhealthy("Повреждён файл могилы " + file.getName() + "; файл не будет перезаписан.", error);
            return null;
        }
        Set<String> fields = yaml.getKeys(false);
        if (!fields.containsAll(REQUIRED_FIELDS) || !ALLOWED_FIELDS.containsAll(fields)
            || yaml.getInt("schema_version", -1) != 1) {
            markUnhealthy("Неизвестная структура файла могилы " + file.getName() + "; файл не будет перезаписан.");
            return null;
        }

        try {
            String id = yaml.getString("id");
            UUID ownerId = UUID.fromString(yaml.getString("owner", ""));
            String ownerName = yaml.getString("owner_name", "");
            String world = yaml.getString("world", "");
            double x = yaml.getDouble("x");
            double y = yaml.getDouble("y");
            double z = yaml.getDouble("z");
            long created = yaml.getLong("created_at", -1L);
            long expires = yaml.getLong("expires_at", -1L);
            State state = State.valueOf(yaml.getString("status", ""));
            if (id == null || !id.matches("[a-f0-9]{8}") || ownerName.isBlank() || ownerName.length() > 64
                || world.isBlank() || world.length() > 128 || !validLocation(x, y, z)
                || created <= 0L || expires <= created || expires - created != TTL_MILLIS) {
                throw new IllegalArgumentException("Invalid grave metadata");
            }

            Object rawItems = yaml.get("items");
            if (!(rawItems instanceof List<?> values) || values.isEmpty() || values.size() > MAX_ITEMS_PER_GRAVE) {
                throw new IllegalArgumentException("Invalid grave item list");
            }
            List<ItemStack> items = new ArrayList<>();
            for (Object value : values) {
                if (!(value instanceof ItemStack item) || item.getType().isAir() || item.getAmount() <= 0) {
                    throw new IllegalArgumentException("Invalid serialized item");
                }
                items.add(item.clone());
            }

            String markerRaw = yaml.getString("marker_entity");
            UUID markerId = markerRaw == null || markerRaw.isBlank() ? null : UUID.fromString(markerRaw);
            String claimId = yaml.getString("claim_id");
            String claimantRaw = yaml.getString("claimant");
            UUID claimant = claimantRaw == null || claimantRaw.isBlank() ? null : UUID.fromString(claimantRaw);
            if (state == State.CLAIMING) {
                if (claimId == null || claimant == null) throw new IllegalArgumentException("Incomplete claim transaction");
                UUID.fromString(claimId);
            } else if (claimId != null || claimant != null) {
                throw new IllegalArgumentException("Unexpected claim transaction fields");
            }
            return new Grave(id, ownerId, ownerName, world, x, y, z, created, expires,
                items, markerId, state, claimId, claimant);
        } catch (RuntimeException error) {
            markUnhealthy("Некорректная запись могилы " + file.getName() + "; файл не будет перезаписан.", error);
            return null;
        }
    }

    private boolean saveRecord(Grave grave) {
        if (!storageHealthy) return false;
        Path temp = null;
        try {
            Files.createDirectories(directory.toPath());
            YamlConfiguration yaml = new YamlConfiguration();
            yaml.set("schema_version", 1);
            yaml.set("id", grave.id());
            yaml.set("owner", grave.ownerId().toString());
            yaml.set("owner_name", grave.ownerName());
            yaml.set("world", grave.world());
            yaml.set("x", grave.x());
            yaml.set("y", grave.y());
            yaml.set("z", grave.z());
            yaml.set("created_at", grave.createdAtEpochMilli());
            yaml.set("expires_at", grave.expiresAtEpochMilli());
            yaml.set("items", grave.items());
            yaml.set("status", grave.state().name());
            if (grave.markerEntityId() != null) yaml.set("marker_entity", grave.markerEntityId().toString());
            if (grave.claimId() != null) yaml.set("claim_id", grave.claimId());
            if (grave.claimantId() != null) yaml.set("claimant", grave.claimantId().toString());

            temp = Files.createTempFile(directory.toPath(), "." + grave.id() + "-", ".tmp");
            yaml.save(temp.toFile());
            try (FileChannel channel = FileChannel.open(temp, StandardOpenOption.WRITE)) {
                channel.force(true);
            }
            Path target = fileFor(grave.id()).toPath();
            try {
                Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException error) {
                Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING);
            }
            return true;
        } catch (IOException | RuntimeException error) {
            markUnhealthy("Не удалось атомарно сохранить могилу " + grave.id() + "; новые изменения отключены.", error);
            return false;
        } finally {
            if (temp != null) {
                try {
                    Files.deleteIfExists(temp);
                } catch (IOException ignored) {
                    // Temporary files are ignored when graves are loaded.
                }
            }
        }
    }

    private boolean deleteRecordFile(String id) {
        try {
            Path path = fileFor(id).toPath();
            if (!Files.exists(path)) {
                markUnhealthy("Файл могилы " + id + " неожиданно отсутствует; изменения отключены.");
                return false;
            }
            Files.delete(path);
            return true;
        } catch (IOException error) {
            markUnhealthy("Не удалось удалить файл могилы " + id + "; изменение отменено.", error);
            return false;
        }
    }

    private File fileFor(String id) {
        return new File(directory, normalizeId(id) + ".yml");
    }

    private String newId() {
        String id;
        do {
            id = UUID.randomUUID().toString().replace("-", "").substring(0, 8).toLowerCase(Locale.ROOT);
        } while (graves.containsKey(id) || fileFor(id).exists());
        return id;
    }

    private static String normalizeId(String id) {
        return id == null ? "" : id.toLowerCase(Locale.ROOT);
    }

    private static boolean validLocation(double x, double y, double z) {
        return Double.isFinite(x) && Double.isFinite(y) && Double.isFinite(z)
            && Math.abs(x) <= 30_000_000d && Math.abs(z) <= 30_000_000d
            && Math.abs(y) <= 4096d;
    }

    private void markUnhealthy(String message) {
        storageHealthy = false;
        plugin.getLogger().severe(message);
    }

    private void markUnhealthy(String message, Throwable error) {
        storageHealthy = false;
        plugin.getLogger().log(Level.SEVERE, message, error);
    }
}
