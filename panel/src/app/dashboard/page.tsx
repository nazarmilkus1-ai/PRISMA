import Link from "next/link";
import { requireAdmin } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Badge, Card, CardContent, CardHeader, CardTitle, Metric, PageHeader } from "@prisma-eco/ui";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function DashboardPage() {
  const admin = await requireAdmin("dashboard.view");
  if (!admin) return null;

  const db = await createSupabaseServerClient();
  const { data: overview, error } = await db.rpc(STAFF_RPC.dashboardOverview);
  const payload = (overview ?? {}) as {
    pending_applications?: number;
    open_reports?: number;
    accepted_players?: number;
    active_clans?: number;
    server?: { status?: string; online_players?: number; max_players?: number; version?: string; last_heartbeat_at?: string | null };
  };
  const pending = { count: payload.pending_applications ?? 0 };
  const openReports = { count: payload.open_reports ?? 0 };
  const players = { count: payload.accepted_players ?? 0 };
  const clans = { count: payload.active_clans ?? 0 };
  const server = { data: payload.server ?? null };

  const online =
    server.data?.status === "ONLINE" &&
    !!server.data?.last_heartbeat_at &&
    Date.now() - new Date(server.data.last_heartbeat_at).getTime() < 120_000;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Обзор"
        title="Панель PRISMA"
        description="Текущее состояние сообщества, модерации и Minecraft-сервера."
        actions={<Badge variant={online ? "success" : "secondary"}>{online ? "Сервер онлайн" : "Сервер офлайн"}</Badge>}
      />

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Metric label="Заявки" value={pending.count ?? 0} hint="ожидают рассмотрения" icon="applications" />
        <Metric label="Репорты" value={openReports.count ?? 0} hint="открытые" icon="flag" />
        <Metric label="Игроки" value={players.count ?? 0} hint="принятые аккаунты" icon="players" />
        <Metric label="Кланы" value={clans.count ?? 0} hint="активные" icon="clans" />
      </div>

      <div className="grid gap-4 lg:grid-cols-[1.15fr_.85fr]">
        <Card>
          <CardHeader><CardTitle>Сервер</CardTitle></CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-3">
            <div><p className="text-xs text-muted-foreground">Статус</p><p className="mt-1 font-semibold">{online ? "ONLINE" : "OFFLINE"}</p></div>
            <div><p className="text-xs text-muted-foreground">Игроки</p><p className="mt-1 font-semibold">{server.data?.online_players ?? 0} / {server.data?.max_players ?? "—"}</p></div>
            <div><p className="text-xs text-muted-foreground">Версия</p><p className="mt-1 font-semibold">{server.data?.version || "—"}</p></div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Быстрые действия</CardTitle></CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            <Link href="/dashboard/applications" className="inline-flex h-9 items-center rounded-md bg-primary px-3.5 text-sm font-medium text-primary-foreground">Открыть заявки</Link>
            <Link href="/dashboard/players" className="inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium hover:bg-accent">Игроки</Link>
            <Link href="/dashboard/reports" className="inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium hover:bg-accent">Репорты</Link>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader><CardTitle>Контур PRISMA</CardTitle></CardHeader>
        <CardContent>
          <p className="text-sm leading-6 text-muted-foreground">
            Админ-панель, сайт для участников, Telegram-бот и Minecraft-плагин используют общую модель данных.
            Действия персонала проходят проверку прав и фиксируются в аудите.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
