package team.prisma.plugin.clans;

import org.bukkit.Location;

import java.util.UUID;

public record Village(
    UUID id,
    UUID clanId,
    String name,
    String world,
    double centerX,
    double centerY,
    double centerZ,
    int radius
) {
    public boolean contains(Location location) {
        if (location.getWorld() == null || !location.getWorld().getName().equals(world)) return false;
        double dx = location.getX() - centerX;
        double dz = location.getZ() - centerZ;
        return (dx * dx + dz * dz) <= (double) radius * radius;
    }

    public Location center(org.bukkit.Server server) {
        var worldObject = server.getWorld(world);
        if (worldObject == null) return null;
        return new Location(worldObject, centerX + 0.5, centerY, centerZ + 0.5);
    }
}
