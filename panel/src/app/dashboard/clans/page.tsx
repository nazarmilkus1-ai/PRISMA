import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { Card } from "@/components/ui";
import { ClansPanel, type Clan, type ClanDetail } from "@/components/ClansPanel";
import { STAFF_RPC } from "@prisma-eco/contracts";

type ClanRegistryRow = Clan & {
  members?: ClanDetail["members"];
  activity?: ClanDetail["activity"];
  invitations?: ClanDetail["invitations"];
  wars?: ClanDetail["wars"];
  announcements?: ClanDetail["announcements"];
};

export default async function ClansPage() {
  const admin = await requireAdminContext("clan.view_all");
  if (!admin) return null;
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.clans, { p_limit: 300 });
  const clans = Array.isArray(data) ? data as ClanRegistryRow[] : [];
  const details: Record<string, Omit<ClanDetail, "clan">> = Object.fromEntries(
    clans.map((clan) => [clan.id, {
      members: clan.members ?? [],
      activity: clan.activity ?? [],
      invitations: clan.invitations ?? [],
      wars: clan.wars ?? [],
      announcements: clan.announcements ?? [],
    }]),
  );
  return <div className="space-y-6"><div><h1 className="font-display text-2xl text-moon">Кланы</h1><p className="mt-1 text-sm text-moon-dim">Профиль клана, участники, рейтинг, войны, активность, заявки-приглашения и объявления.</p></div>{error && <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Не удалось загрузить кланы: {error.message}</div>}{!clans?.length && !error && <Card className="p-10 text-center text-sm text-moon-dim">Пока ни одного клана не создано.</Card>}{clans?.length ? <ClansPanel initialClans={clans} initialDetails={details} /> : null}</div>;
}