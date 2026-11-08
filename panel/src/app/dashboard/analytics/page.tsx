import { formatDateTime } from "@prisma-eco/shared";
export const dynamic = "force-dynamic";
export const revalidate = 0;

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { Card, ProgressBar, StatCard } from "@/components/ui";
import { AcceptanceRateChart, AdminActivityChart, ChatActivityComboChart, UserGrowthChart } from "@/components/charts/DashboardCharts";
import { AnalyticsPeriodControls } from "@/components/AnalyticsPeriodControls";
import { AnalyticsDetailsTables } from "@/components/AnalyticsDetailsTables";
import { STAFF_RPC } from "@prisma-eco/contracts";

type ChatRow = { user_id: string | number | null };
type RatingRow = { value: number | null };
type TrendRow = { bucket: string | null; count: number | null };
type ChatActivityRow = { bucket: string | null; messages: number | null; unique_players: number | null };
type AdminActivityRow = { bucket: string | null; total_actions: number | null; active_admins: number | null };
type TopChatUserRow = { user_id: string | number; player: string; last_message_at: string | null; messages: number | null };
type AnalyticsSnapshot = { chat?: ChatRow[]; ratings?: RatingRow[]; audit?: unknown[]; application_trend?: TrendRow[]; chat_activity?: ChatActivityRow[]; admin_activity?: AdminActivityRow[]; top_chat_users?: TopChatUserRow[]; application_status?: Partial<Record<"PENDING" | "ACCEPTED" | "REJECTED", number>>; unique_chat_players?: number; total_admin_actions?: number };
type AdminSummaryRow = { telegram_id?: number; actor?: string | null; role?: string | null; total?: number; applications?: number; reports?: number; moderation?: number; management?: number; auth?: number; other?: number; last_action?: string | null; last_action_at?: string | null };

const PERIODS = new Set(["24h", "7d", "30d", "all"]);

function normalizePeriod(value: string | undefined): "24h" | "7d" | "30d" | "all" {
  return PERIODS.has(value || "") ? (value as "24h" | "7d" | "30d" | "all") : "30d";
}

function periodLabel(period: "24h" | "7d" | "30d" | "all") {
  return period === "24h" ? "День" : period === "7d" ? "Неделя" : period === "30d" ? "Месяц" : "Всё время";
}

function formatBucket(value: string | null | undefined, period: string, detailed: boolean) {
  if (!value) return "—";
  const d = new Date(value);
  if (detailed) {
    return d.toLocaleString("ru-RU", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  }
  if (period === "24h") {
    return d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
  }
  return d.toLocaleDateString("ru-RU", {
    day: "2-digit",
    month: "2-digit",
  });
}

export default async function AnalyticsPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string; detail?: string }>;
}) {
  const admin = await requireAdmin("analytics.view");
  if (!admin) return null;

  const sp = await searchParams;
  const period = normalizePeriod(sp.period);
  const detailed = sp.detail === "1";
  const db = await createSupabaseServerClient();
  const [{ data: snapshot, error: snapshotError }, { data: adminSummaryPayload, error: adminSummaryError }] = await Promise.all([
    db.rpc(STAFF_RPC.analytics, {
      p_days: period === "24h" ? 1 : period === "7d" ? 7 : 30,
      p_chat_days: period === "24h" ? 1 : period === "7d" ? 7 : 30,
      p_period: period,
      p_detail: detailed,
    }),
    db.rpc(STAFF_RPC.analyticsAdminSummary, { p_period: period }),
  ]);

  const payload = (snapshot ?? {}) as AnalyticsSnapshot;
  const chats = Array.isArray(payload.chat) ? payload.chat : [];
  const ratings = Array.isArray(payload.ratings) ? payload.ratings : [];
  const audits = Array.isArray(payload.audit) ? payload.audit : [];
  const applicationTrend = Array.isArray(payload.application_trend) ? payload.application_trend : [];
  const chatActivity = Array.isArray(payload.chat_activity) ? payload.chat_activity : [];
  const adminActivity = Array.isArray(payload.admin_activity) ? payload.admin_activity : [];
  const topChatUsers = Array.isArray(payload.top_chat_users) ? payload.top_chat_users : [];

  const statusSummary = payload.application_status && typeof payload.application_status === "object"
    ? payload.application_status
    : {};
  const acceptance: Record<string, number> = {
    PENDING: Number(statusSummary.PENDING || 0),
    ACCEPTED: Number(statusSummary.ACCEPTED || 0),
    REJECTED: Number(statusSummary.REJECTED || 0),
  };

  const numericRatings = ratings.filter((x) => typeof x.value === "number");
  const avgRating = numericRatings.length
    ? (numericRatings.reduce((sum: number, x) => sum + Number(x.value), 0) / numericRatings.length).toFixed(1)
    : "—";

  const chatTotal = chatActivity.reduce((sum: number, x) => sum + Number(x.messages || 0), 0);
  const chatPeak = chatActivity.reduce((peak: number, x) => Math.max(peak, Number(x.unique_players || 0)), 0);
  const uniquePlayersPeriod = Number(payload.unique_chat_players ?? new Set(chats.map((x) => x.user_id).filter(Boolean)).size);
  const adminActionTotal = Number(payload.total_admin_actions ?? audits.length);
  const totalApplications = Object.values(acceptance).reduce((a, b) => a + b, 0);

  const adminSummary = Array.isArray(adminSummaryPayload) ? adminSummaryPayload as AdminSummaryRow[] : [];
  const adminTable = adminSummary
    .filter((item) => typeof item.telegram_id === "number")
    .map((item) => ({
      actor: String(item.actor ?? item.telegram_id),
      role: String(item.role ?? "—"),
      telegramId: Number(item.telegram_id),
      total: Number(item.total ?? 0),
      applications: Number(item.applications ?? 0),
      reports: Number(item.reports ?? 0),
      moderation: Number(item.moderation ?? 0),
      management: Number(item.management ?? 0),
      auth: Number(item.auth ?? 0),
      other: Number(item.other ?? 0),
      lastAction: item.last_action ? String(item.last_action) : null,
      lastActionAt: item.last_action_at ? String(item.last_action_at) : null,
    }));

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <h1 className="font-display text-2xl text-moon">Аналитика</h1>
          <p className="mt-1 text-sm text-moon-dim">
            Для «День» данные идут по часам, для «Неделя», «Месяц» и «Всё время» — по дням. Подробный режим оставляет выбранный период, но показывает его по часам.
          </p>
        </div>
        <AnalyticsPeriodControls period={period} detailed={detailed} />
      </div>

      {(snapshotError || adminSummaryError) && (
        <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">
          Часть аналитики не загрузилась. Доступные данные всё равно показаны.
        </div>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        <StatCard label={`Заявок · ${periodLabel(period)}`} value={totalApplications} />
        <StatCard label={`Уникальных игроков в чате · ${periodLabel(period)}`} value={uniquePlayersPeriod} />
        <StatCard label={`Сообщений Minecraft-чата · ${periodLabel(period)}`} value={chatTotal} />
        <StatCard label="Пик уникальных · за интервал" value={chatPeak} />
        <StatCard label="Средняя оценка сервера" value={avgRating} />
        <StatCard label={`Действий админов · ${periodLabel(period)}`} value={adminActionTotal} />
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <div className="min-w-0 rounded-xl border border-border bg-panel p-4 sm:p-5">
          <div className="mb-4">
            <h2 className="text-sm font-medium text-moon">Заявки во времени · {detailed ? "по часам" : period === "24h" ? "по часам" : "по дням"}</h2>
            <p className="mt-1 text-xs text-moon-dim">Количество новых заявок внутри выбранного периода.</p>
          </div>
          <UserGrowthChart data={applicationTrend.map((x) => ({ date: formatBucket(x.bucket, period, detailed), count: Number(x.count || 0) }))} />
        </div>

        <div className="min-w-0 rounded-xl border border-border bg-panel p-4 sm:p-5">
          <div className="mb-4">
            <h2 className="text-sm font-medium text-moon">Minecraft-чат · активность · {detailed ? "по часам" : period === "24h" ? "по часам" : "по дням"}</h2>
            <p className="mt-1 text-xs text-moon-dim">Две метрики в одном графике: сообщения и уникальные игроки.</p>
          </div>
          <ChatActivityComboChart data={chatActivity.map((x) => ({
            date: formatBucket(x.bucket, period, detailed),
            messages: Number(x.messages || 0),
            unique_players: Number(x.unique_players || 0),
          }))} />
          <p className="mt-2 text-xs text-moon-dim">Активный = хотя бы одно сообщение в сохранённом Minecraft-чате.</p>
        </div>

        <div className="min-w-0 rounded-xl border border-border bg-panel p-4 sm:p-5">
          <div className="mb-4">
            <h2 className="text-sm font-medium text-moon">Статусы заявок</h2>
            <p className="mt-1 text-xs text-moon-dim">Распределение заявок за тот же период.</p>
          </div>
          <AcceptanceRateChart data={acceptance} />
          <div className="mt-2 space-y-3">
            <ProgressBar tone="success" label="Принято" value={acceptance.ACCEPTED ?? 0} max={totalApplications || 1} />
            <ProgressBar tone="warn" label="Ожидают" value={acceptance.PENDING ?? 0} max={totalApplications || 1} />
            <ProgressBar tone="danger" label="Отклонено" value={acceptance.REJECTED ?? 0} max={totalApplications || 1} />
          </div>
        </div>

        <div className="min-w-0 rounded-xl border border-border bg-panel p-4 sm:p-5">
          <div className="mb-4">
            <h2 className="text-sm font-medium text-moon">Активность администраторов · {detailed ? "по часам" : period === "24h" ? "по часам" : "по дням"}</h2>
            <p className="mt-1 text-xs text-moon-dim">Действия и количество администраторов, которые реально действовали в каждом интервале.</p>
          </div>
          <AdminActivityChart data={adminActivity.map((x) => ({
            date: formatBucket(x.bucket, period, detailed),
            total_actions: Number(x.total_actions || 0),
            active_admins: Number(x.active_admins || 0),
          }))} />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-[1.5fr_1fr]">
        <Card className="overflow-hidden">
          <div className="border-b border-border p-5">
            <h2 className="font-medium text-moon">Активность администраторов · состав</h2>
            <p className="mt-1 text-xs text-moon-dim">Все действующие администраторы видны даже при 0 действий за выбранный период. Рядом показано последнее действие именно в этом периоде.</p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1050px] text-left text-sm">
              <thead>
                <tr className="border-b border-border text-[11px] uppercase tracking-wide text-moon-dim">
                  <th className="p-3">Админ</th>
                  <th className="p-3">Роль</th>
                  <th className="p-3">Всего</th>
                  <th className="p-3">Заявки</th>
                  <th className="p-3">Репорты</th>
                  <th className="p-3">Модерация</th>
                  <th className="p-3">Управление</th>
                  <th className="p-3">Auth</th>
                  <th className="p-3">Другое</th>
                  <th className="p-3">Последнее</th>
                </tr>
              </thead>
              <tbody>
                {adminTable.map((m) => (
                  <tr key={m.telegramId} className="border-b border-border/60">
                    <td className="p-3">
                      <p className="text-moon">{m.actor}</p>
                      <p className="font-mono text-[11px] text-moon-dim">{m.telegramId}</p>
                    </td>
                    <td className="p-3 text-moon-dim">{m.role}</td>
                    <td className="p-3 font-semibold text-moon">{m.total}</td>
                    <td className="p-3 text-moon">{m.applications}</td>
                    <td className="p-3 text-moon">{m.reports}</td>
                    <td className="p-3 text-moon">{m.moderation}</td>
                    <td className="p-3 text-moon">{m.management}</td>
                    <td className="p-3 text-moon">{m.auth}</td>
                    <td className="p-3 text-moon">{m.other}</td>
                    <td className="p-3">
                      <p className="font-mono text-xs text-moon">{m.lastAction ?? "—"}</p>
                      <p className="mt-0.5 text-[11px] text-moon-dim">{m.lastActionAt ? formatDateTime(m.lastActionAt) : "Нет действий"}</p>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {!adminTable.length && <p className="p-8 text-center text-sm text-moon-dim">Администраторов в реестре нет.</p>}
        </Card>

        <Card className="overflow-hidden">
          <div className="border-b border-border p-5">
            <h2 className="font-medium text-moon">Кто пишет в чат</h2>
            <p className="mt-1 text-xs text-moon-dim">Самые активные игроки по количеству сообщений за выбранный период.</p>
          </div>
          <div className="divide-y divide-border">
            {topChatUsers.map((x, i: number) => (
              <div key={String(x.user_id)} className="flex items-center gap-3 p-3">
                <span className="w-6 font-mono text-xs text-moon-dim">{i + 1}</span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm text-moon">{x.player}</p>
                  <p className="text-[11px] text-moon-dim">{x.last_message_at ? formatDateTime(x.last_message_at) : "—"}</p>
                </div>
                <span className="font-semibold text-moon">{Number(x.messages || 0)}</span>
              </div>
            ))}
            {!topChatUsers.length && <p className="p-8 text-center text-sm text-moon-dim">Сообщений за период нет.</p>}
          </div>
        </Card>
      </div>

      {detailed && <AnalyticsDetailsTables key={period} period={period} />}

    </div>
  );
}
