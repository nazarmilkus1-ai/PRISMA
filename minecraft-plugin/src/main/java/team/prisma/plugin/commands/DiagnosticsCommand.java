package team.prisma.plugin.commands;

import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import team.prisma.plugin.PrismaPlugin;
import team.prisma.plugin.http.SupabaseClient;

public final class DiagnosticsCommand implements CommandExecutor {

    private final PrismaPlugin plugin;
    private final SupabaseClient supabase;

    public DiagnosticsCommand(PrismaPlugin plugin, SupabaseClient supabase) {
        this.plugin = plugin;
        this.supabase = supabase;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!sender.getName().equals("CONSOLE")) {
            sender.sendMessage("§cЭта команда доступна только из консоли сервера.");
            return true;
        }

        if (args.length != 1 || args[0].isBlank()) {
            sender.sendMessage("§eИспользование: /prismadiag <minecraft_nickname>");
            return true;
        }

        String nickname = args[0].trim();
        sender.sendMessage("§7[PRISMA] Проверяю DNS, HTTPS, REST и RPC для §f" + nickname + "§7...");

        supabase.executor().execute(() -> {
            SupabaseClient.DiagnosticResult result = supabase.diagnose(nickname);

            plugin.getServer().getScheduler().runTask(plugin, () -> {
                sender.sendMessage("§7[PRISMA] §f--- диагностика Supabase ---");
                sender.sendMessage("§7DNS: " + result.dns());
                sender.sendMessage("§7HTTPS root: " + result.rootHttp());
                sender.sendMessage("§7REST /rest/v1/: " + result.restHttp());
                sender.sendMessage("§7RPC get_minecraft_user: " + result.rpcHttp());

                if (result.rpcStatus() != null) {
                    sender.sendMessage("§7RPC result: status=" + result.rpcStatus()
                        + ", whitelisted=" + result.rpcWhitelisted()
                        + ", banned=" + result.rpcBanned());
                }

                sender.sendMessage("§7[PRISMA] §fГотово.");
            });
        });

        return true;
    }
}
