package team.prisma.plugin.explore;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.format.TextDecoration;
import org.bukkit.Bukkit;
import org.bukkit.Color;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.server.MapInitializeEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.MapMeta;
import org.bukkit.map.MapCanvas;
import org.bukkit.map.MapCursor;
import org.bukkit.map.MapCursorCollection;
import org.bukkit.map.MapPalette;
import org.bukkit.map.MapRenderer;
import org.bukkit.map.MapView;
import org.bukkit.persistence.PersistentDataType;
import org.bukkit.plugin.java.JavaPlugin;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.homes.PlayerHomesStore;
import team.prisma.plugin.journey.PlayerJourneyStore;
import team.prisma.plugin.spawn.SpawnPointsStore;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Personal "Minecraft-style" world map with fog of war.
 *
 * - Every second the visited chunks of online players are recorded together with a 4x4 colour sample
 *   (only chunks that are ALREADY loaded around the player; nothing is ever force-loaded).
 * - The map item is drawn from that stored sample, never from the world: no chunk loads, no block reads,
 *   and the redraw is throttled (every 2 s or when the player crosses a chunk).
 * - Unvisited areas stay dark. Saved points are shown as markers: homes, checkpoints, last death, spawn.
 * - Data is keyed by the profile, so Java and Bedrock accounts of one profile share the map.
 */
public final class ExploreMapManager implements Listener {
    private static final int BLOCKS_PER_PIXEL = 4;
    private static final int RECORD_RADIUS_CHUNKS = 1;
    private static final long MIN_REDRAW_MS = 2_000L;
    private static final int MAX_RECORDS_PER_TICK = 6;

    private final JavaPlugin plugin;
    private final PlayerStateCache cache;
    private final ExploreStore store;
    private final PlayerHomesStore homes;
    private final PlayerJourneyStore journey;
    private final SpawnPointsStore spawns;
    private final NamespacedKey ownerKey;
    private final File idsFile;
    private final Map<Integer, String> mapOwners = new ConcurrentHashMap<>();
    private final Map<String, Integer> ownerMaps = new ConcurrentHashMap<>();
    private final Map<UUID, long[]> lastDraw = new ConcurrentHashMap<>();
    private final Map<Color, Byte> colorCache = new HashMap<>();
    private final MapRenderer renderer = new ExploreRenderer();
    private int recordTask = -1;
    private int saveTask = -1;

    public ExploreMapManager(JavaPlugin plugin, PlayerStateCache cache, ExploreStore store,
                             PlayerHomesStore homes, PlayerJourneyStore journey, SpawnPointsStore spawns) {
        this.plugin = plugin;
        this.cache = cache;
        this.store = store;
        this.homes = homes;
        this.journey = journey;
        this.spawns = spawns;
        this.ownerKey = new NamespacedKey(plugin, "explore_map_owner");
        this.idsFile = new File(plugin.getDataFolder(), "explore-maps.yml");
        loadIds();
    }

    public void start() {
        recordTask = Bukkit.getScheduler().runTaskTimer(plugin, this::recordTick, 40L, 20L).getTaskId();
        saveTask = Bukkit.getScheduler().runTaskTimer(plugin, store::saveAllAsync, 20L * 120, 20L * 120).getTaskId();
    }

    public void stop() {
        if (recordTask != -1) Bukkit.getScheduler().cancelTask(recordTask);
        if (saveTask != -1) Bukkit.getScheduler().cancelTask(saveTask);
    }

    // ------------------------------------------------------------------ recording

    private void recordTick() {
        int budget = MAX_RECORDS_PER_TICK;
        for (Player player : Bukkit.getOnlinePlayers()) {
            if (budget <= 0) break;
            String profile = cache.userIdOf(player.getUniqueId());
            World world = player.getWorld();
            if (profile == null || world.getEnvironment() != World.Environment.NORMAL) continue;
            ExploreStore.PlayerData data = store.of(profile);
            if (data == null) continue;
            int pcx = player.getLocation().getBlockX() >> 4;
            int pcz = player.getLocation().getBlockZ() >> 4;
            for (int dx = -RECORD_RADIUS_CHUNKS; dx <= RECORD_RADIUS_CHUNKS && budget > 0; dx++) {
                for (int dz = -RECORD_RADIUS_CHUNKS; dz <= RECORD_RADIUS_CHUNKS && budget > 0; dz++) {
                    int cx = pcx + dx;
                    int cz = pcz + dz;
                    if (data.has(world.getName(), cx, cz) || !world.isChunkLoaded(cx, cz)) continue;
                    data.put(world.getName(), cx, cz, sample(world, cx, cz));
                    budget--;
                }
            }
        }
    }

    /** 4x4 map colours for one LOADED chunk (16 heightmap reads, once per chunk per profile). */
    private byte[] sample(World world, int cx, int cz) {
        byte[] out = new byte[ExploreStore.SAMPLES];
        for (int sz = 0; sz < 4; sz++) {
            for (int sx = 0; sx < 4; sx++) {
                int x = (cx << 4) + sx * 4 + 2;
                int z = (cz << 4) + sz * 4 + 2;
                out[sz * 4 + sx] = colorAt(world, x, z);
            }
        }
        return out;
    }

    private byte colorAt(World world, int x, int z) {
        try {
            int y = world.getHighestBlockYAt(x, z);
            Block block = world.getBlockAt(x, y, z);
            Color color = block.getBlockData().getMapColor();
            Byte cached = colorCache.get(color);
            if (cached == null) {
                cached = MapPalette.matchColor(color.getRed(), color.getGreen(), color.getBlue());
                colorCache.put(color, cached);
            }
            return cached;
        } catch (RuntimeException exception) {
            return 0;
        }
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        lastDraw.remove(event.getPlayer().getUniqueId());
        String profile = cache.userIdOf(event.getPlayer().getUniqueId());
        if (profile == null) return;
        boolean stillOnline = false;
        for (Player other : Bukkit.getOnlinePlayers()) {
            if (!other.getUniqueId().equals(event.getPlayer().getUniqueId())
                && profile.equalsIgnoreCase(cache.userIdOf(other.getUniqueId()))) {
                stillOnline = true;
                break;
            }
        }
        if (stillOnline) store.saveAsync(profile); else store.release(profile);
    }

    // ------------------------------------------------------------------ map item

    public enum GiveResult { GIVEN, ALREADY_HAS, NO_PROFILE, WRONG_WORLD, FAILED }

    public GiveResult give(Player player) {
        String profile = cache.userIdOf(player.getUniqueId());
        if (profile == null || profile.isBlank()) return GiveResult.NO_PROFILE;
        for (ItemStack stack : player.getInventory().getContents()) {
            if (isOwnMap(stack, profile)) return GiveResult.ALREADY_HAS;
        }
        try {
            MapView view = null;
            Integer existing = ownerMaps.get(profile);
            if (existing != null) view = Bukkit.getMap(existing);
            if (view == null) {
                World world = Bukkit.getWorlds().isEmpty() ? player.getWorld() : Bukkit.getWorlds().get(0);
                view = Bukkit.createMap(world);
                rememberId(profile, view.getId());
            }
            attach(view);
            ItemStack item = new ItemStack(Material.FILLED_MAP);
            MapMeta meta = (MapMeta) item.getItemMeta();
            meta.setMapView(view);
            meta.displayName(Component.text("Карта PRISMA", NamedTextColor.GOLD).decoration(TextDecoration.ITALIC, false));
            meta.lore(List.of(
                Component.text("Показывает только места, где вы были.", NamedTextColor.GRAY).decoration(TextDecoration.ITALIC, false),
                Component.text("Метки: дом, контрольные точки, место смерти, спавн.", NamedTextColor.GRAY).decoration(TextDecoration.ITALIC, false),
                Component.text("Держите в руке — карта обновляется сама.", NamedTextColor.DARK_GRAY).decoration(TextDecoration.ITALIC, false)));
            meta.getPersistentDataContainer().set(ownerKey, PersistentDataType.STRING, profile);
            item.setItemMeta(meta);
            Map<Integer, ItemStack> leftover = player.getInventory().addItem(item);
            leftover.values().forEach(rest -> player.getWorld().dropItem(player.getLocation(), rest));
            return GiveResult.GIVEN;
        } catch (RuntimeException exception) {
            plugin.getLogger().warning("Could not create a world map for " + player.getName() + ": " + exception);
            return GiveResult.FAILED;
        }
    }

    private boolean isOwnMap(ItemStack stack, String profile) {
        if (stack == null || stack.getType() != Material.FILLED_MAP || !stack.hasItemMeta()) return false;
        String owner = stack.getItemMeta().getPersistentDataContainer().get(ownerKey, PersistentDataType.STRING);
        return profile.equalsIgnoreCase(owner);
    }

    private void attach(MapView view) {
        for (MapRenderer existing : new ArrayList<>(view.getRenderers())) {
            if (existing != renderer) view.removeRenderer(existing);
        }
        if (!view.getRenderers().contains(renderer)) view.addRenderer(renderer);
        view.setTrackingPosition(false);
        view.setUnlimitedTracking(false);
        view.setScale(MapView.Scale.NORMAL);
    }

    /** After a restart Minecraft loads our maps again with the vanilla renderer: put ours back. */
    @EventHandler
    public void onMapInit(MapInitializeEvent event) {
        MapView view = event.getMap();
        if (mapOwners.containsKey(view.getId())) attach(view);
    }

    private void loadIds() {
        if (!idsFile.isFile()) return;
        YamlConfiguration yaml = YamlConfiguration.loadConfiguration(idsFile);
        for (String profile : yaml.getKeys(false)) {
            int id = yaml.getInt(profile, -1);
            if (id >= 0) {
                mapOwners.put(id, profile);
                ownerMaps.put(profile, id);
            }
        }
    }

    private synchronized void rememberId(String profile, int id) {
        mapOwners.put(id, profile);
        ownerMaps.put(profile, id);
        YamlConfiguration yaml = new YamlConfiguration();
        ownerMaps.forEach(yaml::set);
        try {
            yaml.save(idsFile);
        } catch (IOException exception) {
            plugin.getLogger().warning("Could not save explore-maps.yml: " + exception.getMessage());
        }
    }

    // ------------------------------------------------------------------ drawing

    private final class ExploreRenderer extends MapRenderer {
        private ExploreRenderer() {
            super(true); // contextual: every player has their own picture
        }

        @Override
        public void render(MapView map, MapCanvas canvas, Player player) {
            try {
                String owner = mapOwners.get(map.getId());
                String profile = cache.userIdOf(player.getUniqueId());
                if (owner == null || profile == null || !owner.equalsIgnoreCase(profile)) return;
                World world = player.getWorld();
                int centerX = player.getLocation().getBlockX();
                int centerZ = player.getLocation().getBlockZ();
                long now = System.currentTimeMillis();
                long[] last = lastDraw.get(player.getUniqueId());
                long cellKey = ExploreStore.PlayerData.key(centerX >> 4, centerZ >> 4);
                if (last != null && last[1] == cellKey && now - last[0] < MIN_REDRAW_MS) return;
                lastDraw.put(player.getUniqueId(), new long[]{now, cellKey});
                draw(canvas, player, profile, world, centerX, centerZ);
            } catch (RuntimeException exception) {
                // a broken frame must never disturb the player or the server
            }
        }
    }

    private void draw(MapCanvas canvas, Player player, String profile, World world, int centerX, int centerZ) {
        ExploreStore.PlayerData data = store.of(profile);
        byte fog = MapPalette.matchColor(34, 30, 26);
        String worldName = world.getName();
        boolean overworld = world.getEnvironment() == World.Environment.NORMAL;
        long lastKey = Long.MIN_VALUE;
        byte[] lastCell = null;
        for (int py = 0; py < 128; py++) {
            for (int px = 0; px < 128; px++) {
                byte color = fog;
                if (overworld && data != null) {
                    int wx = centerX + (px - 64) * BLOCKS_PER_PIXEL;
                    int wz = centerZ + (py - 64) * BLOCKS_PER_PIXEL;
                    int cx = Math.floorDiv(wx, 16);
                    int cz = Math.floorDiv(wz, 16);
                    long key = ExploreStore.PlayerData.key(cx, cz);
                    if (key != lastKey) {
                        lastKey = key;
                        lastCell = data.get(worldName, cx, cz);
                    }
                    if (lastCell != null) {
                        int sx = Math.floorMod(wx, 16) / 4;
                        int sz = Math.floorMod(wz, 16) / 4;
                        color = lastCell[sz * 4 + sx];
                    }
                }
                canvas.setPixel(px, py, color);
            }
        }
        MapCursorCollection cursors = new MapCursorCollection();
        if (overworld) {
            addMarkers(cursors, player, worldName, centerX, centerZ);
        }
        cursors.addCursor(new MapCursor((byte) 0, (byte) 0, direction(player.getLocation().getYaw()), MapCursor.Type.PLAYER, true));
        canvas.setCursors(cursors);
    }

    private void addMarkers(MapCursorCollection cursors, Player player, String worldName, int centerX, int centerZ) {
        UUID id = player.getUniqueId();
        SpawnPointsStore.SpawnPoint spawn = spawns.get(SpawnPointsStore.MAIN_SPAWN_ID);
        if (spawn != null) mark(cursors, spawn.world(), worldName, spawn.x(), spawn.z(), centerX, centerZ, MapCursor.Type.TARGET_POINT);
        for (PlayerHomesStore.HomePoint home : homes.list(id).values()) {
            mark(cursors, home.world(), worldName, home.x(), home.z(), centerX, centerZ, MapCursor.Type.BLUE_MARKER);
        }
        for (PlayerJourneyStore.Point point : journey.checkpoints(id).values()) {
            mark(cursors, point.world(), worldName, point.x(), point.z(), centerX, centerZ, MapCursor.Type.RED_MARKER);
        }
        PlayerJourneyStore.Point death = journey.lastDeath(id);
        if (death != null) mark(cursors, death.world(), worldName, death.x(), death.z(), centerX, centerZ, MapCursor.Type.TARGET_X);
    }

    private static void mark(MapCursorCollection cursors, String pointWorld, String worldName,
                             double x, double z, int centerX, int centerZ, MapCursor.Type type) {
        if (pointWorld == null || !pointWorld.equals(worldName)) return;
        int cursorX = (int) Math.round((x - centerX) / BLOCKS_PER_PIXEL) * 2;
        int cursorY = (int) Math.round((z - centerZ) / BLOCKS_PER_PIXEL) * 2;
        if (cursorX < -127 || cursorX > 127 || cursorY < -127 || cursorY > 127) return;
        cursors.addCursor(new MapCursor((byte) cursorX, (byte) cursorY, (byte) 8, type, true));
    }

    private static byte direction(float yaw) {
        float normalized = ((yaw % 360f) + 360f) % 360f;
        return (byte) (((int) Math.floor(normalized / 22.5f + 0.5f)) & 15);
    }
}
