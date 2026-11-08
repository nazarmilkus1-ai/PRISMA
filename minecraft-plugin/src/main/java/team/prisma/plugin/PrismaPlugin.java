package team.prisma.plugin;

import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.TabCompleter;
import org.bukkit.command.PluginCommand;
import team.prisma.plugin.cache.PlayerStateCache;
import team.prisma.plugin.auth.MinecraftAuthService;
import team.prisma.plugin.clans.VillageManager;
import team.prisma.plugin.clans.VillageProtectionListener;
import team.prisma.plugin.commands.ClanCommand;
import team.prisma.plugin.commands.DiagnosticsCommand;
import team.prisma.plugin.commands.VillageCommand;
import team.prisma.plugin.config.PluginConfig;
import team.prisma.plugin.http.SupabaseClient;
import team.prisma.plugin.modules.ModuleStateCache;
import team.prisma.plugin.listeners.BlockPlaceListener;
import team.prisma.plugin.listeners.ChatListener;
import team.prisma.plugin.listeners.CommandListener;
import team.prisma.plugin.listeners.JoinQuitListener;
import team.prisma.plugin.listeners.MinecraftAuthListener;
import team.prisma.plugin.listeners.WhitelistListener;
import team.prisma.plugin.staff.StaffPermissionCache;
import team.prisma.plugin.staff.PlayerRoleDisplay;
import team.prisma.plugin.commands.MinecraftCommandCatalogCommand;
import team.prisma.plugin.commands.MinecraftAuthCommand;
import team.prisma.plugin.commands.PlayerHomeCommand;
import team.prisma.plugin.homes.PlayerHomesStore;
import team.prisma.plugin.spawn.SpawnPointsStore;
import team.prisma.plugin.commands.SpawnCommand;
import team.prisma.plugin.commands.TpAllCommand;
import team.prisma.plugin.commands.PrismaHelpCommand;
import team.prisma.plugin.commands.PlayerJourneyCommand;
import team.prisma.plugin.journey.PlayerJourneyStore;
import team.prisma.plugin.listeners.PlayerJourneyListener;
import team.prisma.plugin.commands.GraveCommand;
import team.prisma.plugin.commands.ModerationCommand;
import team.prisma.plugin.graves.GraveStore;
import team.prisma.plugin.listeners.GraveListener;
import team.prisma.plugin.tasks.ModerationPollTask;
import team.prisma.plugin.tasks.MinecraftChatBridgeTask;
import team.prisma.plugin.tasks.ServerMetricsTask;
import team.prisma.plugin.tasks.ServerHudTask;
import team.prisma.plugin.tasks.PlayerStatsTask;
import team.prisma.plugin.teleport.StaffTeleportCommand;
import team.prisma.plugin.teleport.TpaCommand;
import team.prisma.plugin.teleport.TpaManager;
import team.prisma.plugin.teleport.TpaCleanupListener;
import team.prisma.plugin.maze.MazeRunnerController;

import java.time.Duration;

public final class PrismaPlugin extends JavaPlugin {
    private SupabaseClient supabase;
    private PlayerHomesStore playerHomes;
    private SpawnPointsStore spawnPoints;
    private PlayerJourneyStore journeyStore;
    private GraveStore graveStore;
    private GraveListener graveListener;

    @Override
    public void onEnable() {
        saveDefaultConfig();
        PluginConfig config;
        try { config = PluginConfig.from(getConfig()); }
        catch (IllegalStateException e) {
            getLogger().severe(e.getMessage());
            getServer().getPluginManager().disablePlugin(this);
            return;
        }

        supabase = new SupabaseClient(config);
        ModuleStateCache modules = new ModuleStateCache(this, supabase);
        modules.start();
        MazeRunnerController mazeRunner = new MazeRunnerController(this, modules);

        boolean geyserPresent = getServer().getPluginManager().getPlugin("Geyser-Spigot") != null;
        boolean floodgatePresent = getServer().getPluginManager().getPlugin("floodgate") != null;
        if (!geyserPresent || !floodgatePresent) getLogger().warning("Geyser/Floodgate integration is incomplete: Bedrock authentication must be checked before release.");

        PlayerStateCache cache = new PlayerStateCache();
        playerHomes = new PlayerHomesStore(this);
        spawnPoints = new SpawnPointsStore(this);
        journeyStore = new PlayerJourneyStore(this);
        graveStore = new GraveStore(this);
        MinecraftAuthService minecraftAuth = new MinecraftAuthService(this, supabase, getLogger());
        VillageManager villages = new VillageManager(this, supabase, cache);
        StaffPermissionCache staff = new StaffPermissionCache(this, supabase, cache);
        PlayerStatsTask playerStatsTask = new PlayerStatsTask(this, supabase, cache, modules, getLogger());
        PlayerRoleDisplay roleDisplay = new PlayerRoleDisplay(this, supabase, cache);

        getServer().getPluginManager().registerEvents(new WhitelistListener(supabase, getLogger()), this);
        getServer().getPluginManager().registerEvents(
            new MinecraftAuthListener(this, minecraftAuth, config.authTimeoutSeconds()), this
        );
        getServer().getPluginManager().registerEvents(new ChatListener(this, supabase, cache, modules), this);
        MinecraftChatBridgeTask chatBridge = new MinecraftChatBridgeTask(this, supabase, modules);
        getServer().getPluginManager().registerEvents(new CommandListener(supabase, cache, modules), this);
        getServer().getPluginManager().registerEvents(new JoinQuitListener(this, supabase, cache, playerStatsTask, roleDisplay, modules), this);
        getServer().getPluginManager().registerEvents(new PlayerJourneyListener(this, journeyStore, modules), this);
        graveListener = new GraveListener(this, graveStore, modules);
        getServer().getPluginManager().registerEvents(graveListener, this);
        graveListener.initialize();
        getServer().getPluginManager().registerEvents(new BlockPlaceListener(cache, modules), this);
        getServer().getPluginManager().registerEvents(new VillageProtectionListener(villages, cache, staff, modules), this);
        getServer().getPluginManager().registerEvents(mazeRunner, this);

        PrismaHelpCommand helpCommand = new PrismaHelpCommand(cache, modules);
        var help = getCommand("help");
        if (help != null) {
            bindGatedCommand(help, helpCommand, null, modules, "minecraft");
        } else {
            getLogger().warning("'help' command not found -- check plugin.yml.");
        }

        ServerHudTask serverHud = new ServerHudTask(this, cache, modules);
        getServer().getPluginManager().registerEvents(serverHud, this);
        var hud = getCommand("hud");
        if (hud != null) {
            bindGatedCommand(hud, serverHud, null, modules, "minecraft-hud");
        } else {
            getLogger().warning("'hud' command not found -- check plugin.yml.");
        }
        getServer().getScheduler().runTaskTimer(this, serverHud, 20L, 40L);

        MinecraftAuthCommand minecraftAuthCommand = new MinecraftAuthCommand(minecraftAuth);
        for (String name : new String[]{"register", "login", "changepass", "prismaauth"}) {
            var command = getCommand(name);
            if (command != null) {
                command.setExecutor(minecraftAuthCommand);
                command.setTabCompleter(minecraftAuthCommand);
            } else {
                getLogger().warning("'" + name + "' command not found -- check plugin.yml.");
            }
        }

        ClanCommand clanCommand = new ClanCommand(this, supabase, cache, villages);
        var clan = getCommand("clan");
        if (clan != null) {
            bindGatedCommand(clan, clanCommand, clanCommand, modules, "minecraft-clan-commands");
        } else {
            getLogger().warning("'clan' command not found -- check plugin.yml.");
        }

        VillageCommand villageCommand = new VillageCommand(this, supabase, cache, villages);
        var village = getCommand("village");
        if (village != null) {
            bindGatedCommand(village, villageCommand, villageCommand, modules, "minecraft-village-commands");
        }

        PlayerHomeCommand homeCommand = new PlayerHomeCommand(this, cache, playerHomes);
        for (String name : new String[]{"sethome", "home", "homes", "delhome"}) {
            var home = getCommand(name);
            if (home != null) {
                bindGatedCommand(home, homeCommand, homeCommand, modules, "minecraft-homes");
            } else {
                getLogger().warning("'" + name + "' command not found -- check plugin.yml.");
            }
        }

        SpawnCommand spawnCommand = new SpawnCommand(this, spawnPoints, cache);
        for (String name : new String[]{"spawn", "spawns", "setspawn", "delspawn"}) {
            var spawn = getCommand(name);
            if (spawn != null) {
                bindGatedCommand(spawn, spawnCommand, spawnCommand, modules, "minecraft-spawns");
            } else {
                getLogger().warning("'" + name + "' command not found -- check plugin.yml.");
            }
        }

        PlayerJourneyCommand journeyCommand = new PlayerJourneyCommand(this, cache, journeyStore);
        for (String name : new String[]{"coords", "lastdeath", "checkpoint"}) {
            var journey = getCommand(name);
            if (journey != null) {
                bindGatedCommand(journey, journeyCommand, journeyCommand, modules, "minecraft-journey");
            } else {
                getLogger().warning("'" + name + "' command not found -- check plugin.yml.");
            }
        }

        ModerationCommand moderationCommand = new ModerationCommand(this, supabase, cache);
        getServer().getPluginManager().registerEvents(moderationCommand, this);
        for (String name : new String[]{"warn", "mute", "unmute", "kick", "ban", "tempban", "unban", "history"}) {
            var moderation = getCommand(name);
            if (moderation != null) {
                bindGatedCommand(moderation, moderationCommand, moderationCommand, modules, "minecraft-moderation");
            } else {
                getLogger().warning("'" + name + "' command not found -- check plugin.yml.");
            }
        }

        GraveCommand graveCommand = new GraveCommand(this, cache, graveStore, graveListener);
        var grave = getCommand("grave");
        if (grave != null) {
            bindGatedCommand(grave, graveCommand, graveCommand, modules, "minecraft-graves");
        } else {
            getLogger().warning("'grave' command not found -- check plugin.yml.");
        }

        TpAllCommand tpAllCommand = new TpAllCommand(this, cache, supabase);
        var tpall = getCommand("tpall");
        if (tpall != null) {
            bindGatedCommand(tpall, tpAllCommand, tpAllCommand, modules, "minecraft-tpall");
        } else {
            getLogger().warning("'tpall' command not found -- check plugin.yml.");
        }

        DiagnosticsCommand diagnosticsCommand = new DiagnosticsCommand(this, supabase);
        var diagnostics = getCommand("prismadiag");
        if (diagnostics != null) {
            diagnostics.setExecutor(diagnosticsCommand);
        } else {
            getLogger().warning("'prismadiag' command not found -- check plugin.yml.");
        }

        StaffTeleportCommand staffTeleport = new StaffTeleportCommand(staff);
        var ptp = getCommand("ptp");
        if (ptp != null) {
            bindGatedCommand(ptp, staffTeleport, staffTeleport, modules, "minecraft-staff-teleport");
        }
        var commands = getCommand("prismacommands");
        if (commands != null) {
            MinecraftCommandCatalogCommand commandCatalog = new MinecraftCommandCatalogCommand(cache, modules);
            bindGatedCommand(commands, commandCatalog, null, modules, "minecraft");
        }

        var ptphere = getCommand("ptphere");
        if (ptphere != null) {
            bindGatedCommand(ptphere, staffTeleport, staffTeleport, modules, "minecraft-staff-teleport");
        }

        var maze = getCommand("maze");
        if (maze != null) {
            maze.setExecutor(mazeRunner);
        } else {
            getLogger().warning("'maze' command not found -- check plugin.yml.");
        }
        getServer().getScheduler().runTaskTimer(this, mazeRunner, 200L, 200L);

        TpaManager tpaManager = new TpaManager(Duration.ofSeconds(30));
        TpaCommand tpaCommand = new TpaCommand(tpaManager);
        getServer().getPluginManager().registerEvents(new TpaCleanupListener(tpaManager), this);
        for (String name : new String[]{"tpa", "tpaccept", "tpdeny"}) {
            var command = getCommand(name);
            if (command != null) bindGatedCommand(command, tpaCommand, tpaCommand, modules, "minecraft-teleport-requests");
        }

        villages.start();
        staff.start();
        roleDisplay.start();

        long intervalTicks = config.moderationPollIntervalSeconds() * 20L;
        getServer().getScheduler().runTaskTimerAsynchronously(this,
            new ModerationPollTask(this, supabase, cache, modules, getLogger()),
            intervalTicks, intervalTicks);
        getServer().getScheduler().runTaskTimerAsynchronously(this, chatBridge, 40L, 40L);

        long metricsTicks = 30L * 20L;
        getServer().getScheduler().runTaskTimer(this,
            new ServerMetricsTask(this, supabase, modules, getLogger()),
            metricsTicks, metricsTicks);

        long statsTicks = 5L * 60L * 20L;
        long statsInitialDelayTicks = 30L * 20L;
        getServer().getScheduler().runTaskTimer(this,
            playerStatsTask,
            statsInitialDelayTicks, statsTicks);

        getLogger().info("PRISMA plugin enabled -- clans, villages, personal homes, spawn points, graves, protected territories, TPA, staff teleport and configurable Maze Runner are loaded.");
    }

    private void bindGatedCommand(
        PluginCommand command,
        CommandExecutor executor,
        TabCompleter tabCompleter,
        ModuleStateCache modules,
        String... requiredModules
    ) {
        command.setExecutor((sender, invoked, label, args) -> {
            if (!modules.allow(sender, requiredModules)) return true;
            return executor.onCommand(sender, invoked, label, args);
        });
        if (tabCompleter != null) {
            command.setTabCompleter((sender, invoked, alias, args) -> {
                for (String moduleId : requiredModules) {
                    if (!modules.isEnabled(moduleId)) return java.util.List.of();
                }
                return tabCompleter.onTabComplete(sender, invoked, alias, args);
            });
        }
    }

    @Override
    public void onDisable() {
        if (playerHomes != null) playerHomes.close();
        if (spawnPoints != null) spawnPoints.close();
        if (journeyStore != null) journeyStore.close();
        if (supabase != null) supabase.shutdown();
    }
}
