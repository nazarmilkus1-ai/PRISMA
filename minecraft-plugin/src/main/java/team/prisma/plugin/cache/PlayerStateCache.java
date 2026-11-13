package team.prisma.plugin.cache;

import java.time.Instant;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

public final class PlayerStateCache {

    private final Map<UUID, Instant> mutedUntil = new ConcurrentHashMap<>();
    private final Set<UUID> mutedForever = ConcurrentHashMap.newKeySet();
    private final Map<UUID, String> clanId = new ConcurrentHashMap<>();
    private final Map<UUID, String> userId = new ConcurrentHashMap<>();
    private final Map<UUID, String> platform = new ConcurrentHashMap<>();
    private final Map<UUID, Long> blocksPlaced = new ConcurrentHashMap<>();
    private final Map<UUID, Long> blocksBroken = new ConcurrentHashMap<>();
    private final Map<UUID, Long> mobsKilled = new ConcurrentHashMap<>();
    // Do not persist a partial zero-valued snapshot before the database baseline was loaded.
    private final Set<UUID> statsBaselineLoaded = ConcurrentHashMap.newKeySet();

    public void onJoin(UUID playerUuid, String supabaseUserId, String clan, Instant muteExpiry) {
        onJoin(playerUuid, supabaseUserId, clan, muteExpiry, 0L);
    }

    public void onJoin(UUID playerUuid, String supabaseUserId, String clan, Instant muteExpiry, long initialBlocksPlaced) {
        onJoin(playerUuid, supabaseUserId, null, clan, muteExpiry, initialBlocksPlaced);
    }

    public void onJoin(UUID playerUuid, String supabaseUserId, String playerPlatform, String clan, Instant muteExpiry, long initialBlocksPlaced) {
        statsBaselineLoaded.remove(playerUuid);
        userId.put(playerUuid, supabaseUserId);
        if (playerPlatform != null && !playerPlatform.isBlank()) {
            platform.put(playerUuid, playerPlatform.trim().toUpperCase());
        } else {
            platform.remove(playerUuid);
        }
        if (clan != null) clanId.put(playerUuid, clan); else clanId.remove(playerUuid);
        // Preserve actions received while the async identity lookup was still in flight.
        blocksPlaced.merge(playerUuid, Math.max(0L, initialBlocksPlaced), Long::sum);
        if (muteExpiry != null) {
            mutedUntil.put(playerUuid, muteExpiry);
            mutedForever.remove(playerUuid);
        } else {
            mutedUntil.remove(playerUuid);
            mutedForever.remove(playerUuid);
        }
    }

    public void onJoinMutedForever(UUID playerUuid) {
        mutedUntil.remove(playerUuid);
        mutedForever.add(playerUuid);
    }

    public void onQuit(UUID playerUuid) {
        statsBaselineLoaded.remove(playerUuid);
        userId.remove(playerUuid);
        platform.remove(playerUuid);
        blocksPlaced.remove(playerUuid);
        blocksBroken.remove(playerUuid);
        mobsKilled.remove(playerUuid);
        clanId.remove(playerUuid);
        mutedUntil.remove(playerUuid);
        mutedForever.remove(playerUuid);
    }

    public void markStatsBaselineLoaded(UUID playerUuid) {
        statsBaselineLoaded.add(playerUuid);
    }

    public boolean hasStatsBaseline(UUID playerUuid) {
        return statsBaselineLoaded.contains(playerUuid);
    }

    public long blocksPlaced(UUID playerUuid) {
        return blocksPlaced.getOrDefault(playerUuid, 0L);
    }

    public long incrementBlocksPlaced(UUID playerUuid) {
        return blocksPlaced.merge(playerUuid, 1L, Long::sum);
    }

    public long blocksBroken(UUID playerUuid) {
        return blocksBroken.getOrDefault(playerUuid, 0L);
    }

    public long incrementBlocksBroken(UUID playerUuid) {
        return blocksBroken.merge(playerUuid, 1L, Long::sum);
    }

    public long mergeBlocksBrokenBaseline(UUID playerUuid, long persistedCount) {
        return blocksBroken.merge(playerUuid, Math.max(0L, persistedCount), Long::sum);
    }

    public long mobsKilled(UUID playerUuid) {
        return mobsKilled.getOrDefault(playerUuid, 0L);
    }

    public long incrementMobsKilled(UUID playerUuid) {
        return mobsKilled.merge(playerUuid, 1L, Long::sum);
    }

    public long mergeMobsKilledBaseline(UUID playerUuid, long persistedCount) {
        return mobsKilled.merge(playerUuid, Math.max(0L, persistedCount), Long::sum);
    }

    /**
     * Adds the persisted DB baseline without overwriting block placements that
     * happened while the async baseline request was in flight.
     */
    public long mergeBlocksPlacedBaseline(UUID playerUuid, long persistedCount) {
        return blocksPlaced.merge(playerUuid, Math.max(0L, persistedCount), Long::sum);
    }

    public boolean isMuted(UUID playerUuid) {
        if (mutedForever.contains(playerUuid)) return true;
        Instant until = mutedUntil.get(playerUuid);
        if (until == null) return false;
        if (until.isBefore(Instant.now())) {
            mutedUntil.remove(playerUuid);
            return false;
        }
        return true;
    }

    public void setMuted(UUID playerUuid, Instant until) {
        if (until == null) {
            onJoinMutedForever(playerUuid);
            return;
        }
        mutedForever.remove(playerUuid);
        mutedUntil.put(playerUuid, until);
    }

    /** Lifts a mute immediately for an online player -- used when an
     * UNMUTE moderation action is applied while they're on the server, as
     * opposed to isMuted() lazily expiring a MUTE that simply ran out. */
    public void unmute(UUID playerUuid) {
        mutedUntil.remove(playerUuid);
        mutedForever.remove(playerUuid);
    }

    public String clanOf(UUID playerUuid) {
        return clanId.get(playerUuid);
    }

    public void setClan(UUID playerUuid, String clan) {
        if (clan == null) clanId.remove(playerUuid); else clanId.put(playerUuid, clan);
    }

    /**
     * One profile may own a Java and a Bedrock account, but never plays both at once. Returns the UUID of
     * ANOTHER online account of the same profile, or null. Only online players are in this map.
     */
    public UUID otherOnlineAccount(String supabaseUserId, UUID self) {
        if (supabaseUserId == null || supabaseUserId.isBlank()) return null;
        for (Map.Entry<UUID, String> entry : userId.entrySet()) {
            if (!entry.getKey().equals(self) && supabaseUserId.equalsIgnoreCase(entry.getValue())) {
                return entry.getKey();
            }
        }
        return null;
    }

    public String userIdOf(UUID playerUuid) {
        return userId.get(playerUuid);
    }

    public String platformOf(UUID playerUuid) {
        return platform.get(playerUuid);
    }

    public Set<UUID> onlineInClan(String clan) {
        return clanId.entrySet().stream()
            .filter(e -> e.getValue().equals(clan))
            .map(Map.Entry::getKey)
            .collect(java.util.stream.Collectors.toSet());
    }
}