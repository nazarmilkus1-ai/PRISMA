package team.prisma.plugin.teleport;

import org.bukkit.entity.Player;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

public final class TpaManager {
    public record Request(UUID requester, UUID target, Instant expiresAt) {}
    private final Map<UUID, Request> requestsByTarget = new ConcurrentHashMap<>();
    private final Duration lifetime;

    public TpaManager(Duration lifetime) {
        this.lifetime = lifetime;
    }

    /**
     * Creates a request only when the target has no live request.
     * Returns false rather than silently replacing another player's request.
     */
    public boolean request(Player requester, Player target) {
        Instant now = Instant.now();
        AtomicBoolean created = new AtomicBoolean(false);
        requestsByTarget.compute(target.getUniqueId(), (id, current) -> {
            if (current != null && current.expiresAt().isAfter(now)) return current;
            created.set(true);
            return new Request(requester.getUniqueId(), target.getUniqueId(), now.plus(lifetime));
        });
        return created.get();
    }

    public Request get(Player target) {
        UUID targetId = target.getUniqueId();
        Request r = requestsByTarget.get(targetId);
        if (r == null) return null;
        if (!r.expiresAt().isAfter(Instant.now())) {
            requestsByTarget.remove(targetId, r);
            return null;
        }
        return r;
    }

    public void clear(Player target) {
        requestsByTarget.remove(target.getUniqueId());
    }

    public void clearFor(UUID player) {
        requestsByTarget.remove(player);
        requestsByTarget.entrySet().removeIf(e -> e.getValue().requester().equals(player));
    }
}
