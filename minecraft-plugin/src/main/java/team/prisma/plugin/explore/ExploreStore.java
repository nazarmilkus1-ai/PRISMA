package team.prisma.plugin.explore;

import org.bukkit.plugin.java.JavaPlugin;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

/**
 * Fog-of-war data for the personal world map: which 16x16 chunks a PROFILE has visited and a tiny colour
 * sample (4x4 map colours per chunk) taken while the chunk was loaded around the player. Rendering the map
 * later never touches the world, so it costs the server no chunk loads and almost no memory
 * (16 bytes per explored chunk, capped). Keyed by the profile id, so a Java and a Bedrock account of one
 * profile share one map.
 */
public final class ExploreStore implements AutoCloseable {
    public static final int MAX_CELLS = 20_000;
    public static final int SAMPLES = 16;
    private static final int MAGIC = 0x50584D31; // "PXM1"
    private static final Pattern SAFE_ID = Pattern.compile("^[0-9a-fA-F-]{8,64}$");

    public static final class PlayerData {
        private final Map<String, Map<Long, byte[]>> worlds = new HashMap<>();
        private int total;
        private boolean dirty;

        public static long key(int cx, int cz) {
            return ((long) cx << 32) | (cz & 0xffffffffL);
        }

        public synchronized boolean has(String world, int cx, int cz) {
            Map<Long, byte[]> cells = worlds.get(world);
            return cells != null && cells.containsKey(key(cx, cz));
        }

        public synchronized byte[] get(String world, int cx, int cz) {
            Map<Long, byte[]> cells = worlds.get(world);
            return cells == null ? null : cells.get(key(cx, cz));
        }

        /** @return true when a new chunk was recorded. */
        public synchronized boolean put(String world, int cx, int cz, byte[] samples) {
            if (samples == null || samples.length != SAMPLES || total >= MAX_CELLS) return false;
            Map<Long, byte[]> cells = worlds.computeIfAbsent(world, w -> new HashMap<>());
            if (cells.putIfAbsent(key(cx, cz), samples.clone()) != null) return false;
            total++;
            dirty = true;
            return true;
        }

        public synchronized int size() {
            return total;
        }

        synchronized byte[] snapshotIfDirty() throws IOException {
            if (!dirty) return null;
            ByteArrayOutputStream bytes = new ByteArrayOutputStream(16 + total * 24);
            try (DataOutputStream out = new DataOutputStream(bytes)) {
                out.writeInt(MAGIC);
                out.writeInt(worlds.size());
                for (Map.Entry<String, Map<Long, byte[]>> world : worlds.entrySet()) {
                    out.writeUTF(world.getKey());
                    out.writeInt(world.getValue().size());
                    for (Map.Entry<Long, byte[]> cell : world.getValue().entrySet()) {
                        out.writeLong(cell.getKey());
                        out.write(cell.getValue());
                    }
                }
            }
            dirty = false;
            return bytes.toByteArray();
        }

        synchronized void markDirty() {
            dirty = true;
        }

        synchronized void readFrom(byte[] data) throws IOException {
            try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(data))) {
                if (in.readInt() != MAGIC) throw new IOException("bad magic");
                int worldCount = in.readInt();
                if (worldCount < 0 || worldCount > 64) throw new IOException("bad world count");
                for (int w = 0; w < worldCount && total < MAX_CELLS; w++) {
                    String name = in.readUTF();
                    int count = in.readInt();
                    if (count < 0 || count > MAX_CELLS) throw new IOException("bad cell count");
                    Map<Long, byte[]> cells = worlds.computeIfAbsent(name, n -> new HashMap<>());
                    for (int i = 0; i < count; i++) {
                        long key = in.readLong();
                        byte[] samples = new byte[SAMPLES];
                        in.readFully(samples);
                        if (total < MAX_CELLS && cells.putIfAbsent(key, samples) == null) total++;
                    }
                }
            }
        }
    }

    private final JavaPlugin plugin;
    private final File dir;
    private final Map<String, PlayerData> cache = new ConcurrentHashMap<>();
    private final ExecutorService writer = Executors.newSingleThreadExecutor(task -> {
        Thread thread = new Thread(task, "prisma-explore-storage");
        thread.setDaemon(true);
        return thread;
    });
    private volatile boolean closed;

    public ExploreStore(JavaPlugin plugin) {
        this.plugin = plugin;
        this.dir = new File(plugin.getDataFolder(), "explored");
        if (!dir.exists() && !dir.mkdirs()) {
            plugin.getLogger().warning("Could not create " + dir + "; the world map will not be saved.");
        }
    }

    /** Loads on first use (one small file); later calls are map lookups. */
    public PlayerData of(String profileId) {
        if (profileId == null || !SAFE_ID.matcher(profileId).matches()) return null;
        return cache.computeIfAbsent(profileId, this::load);
    }

    private PlayerData load(String profileId) {
        PlayerData data = new PlayerData();
        File file = new File(dir, profileId + ".bin");
        if (file.isFile() && file.length() < 2_000_000L) {
            try {
                data.readFrom(Files.readAllBytes(file.toPath()));
            } catch (IOException | RuntimeException exception) {
                plugin.getLogger().warning("Explored-map file for " + profileId + " is unreadable and was ignored: " + exception.getMessage());
            }
        }
        return data;
    }

    public void saveAsync(String profileId) {
        PlayerData data = cache.get(profileId);
        if (data == null || closed) return;
        writeOut(profileId, data);
    }

    public void saveAllAsync() {
        if (closed) return;
        cache.forEach(this::writeOut);
    }

    /** Frees the memory of a player who left (saves first if needed). */
    public void release(String profileId) {
        PlayerData data = cache.remove(profileId);
        if (data != null) writeOut(profileId, data);
    }

    private void writeOut(String profileId, PlayerData data) {
        final byte[] bytes;
        try {
            bytes = data.snapshotIfDirty();
        } catch (IOException exception) {
            plugin.getLogger().warning("Explored-map snapshot failed for " + profileId + ": " + exception.getMessage());
            return;
        }
        if (bytes == null) return;
        try {
            writer.execute(() -> {
                File target = new File(dir, profileId + ".bin");
                File temp = new File(dir, profileId + ".bin.tmp");
                try {
                    Files.write(temp.toPath(), bytes);
                    Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
                } catch (IOException exception) {
                    data.markDirty();
                    plugin.getLogger().warning("Explored-map save failed for " + profileId + ": " + exception.getMessage());
                }
            });
        } catch (RuntimeException rejected) {
            data.markDirty();
        }
    }

    @Override
    public void close() {
        if (closed) return;
        cache.forEach(this::writeOut);
        closed = true;
        writer.shutdown();
        try {
            writer.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }
}
