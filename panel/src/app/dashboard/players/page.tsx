import { PlayersPanel } from "@/components/PlayersPanel";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function PlayersPage() {
  const admin = await requireAdmin("player.view");
  if (!admin) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.players, {
    p_search: "",
    p_limit: 500,
  });
  const players = Array.isArray(data) ? data : [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl text-moon">Игроки</h1>
        <p className="mt-1 text-sm text-moon-dim">Единый список игроков PRISMA с профилем, статусом, активностью и модерацией.</p>
      </div>
      {error && <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Не удалось загрузить игроков: {error.message}</div>}
      <PlayersPanel initialPlayers={players} />
    </div>
  );
}
