import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { Card, StatCard } from "@/components/ui";
import { STAFF_RPC } from "@prisma-eco/contracts";
import { formatDateTime, formatMegabytes, formatUptimeUk } from "@prisma-eco/shared";

type HeartbeatMetric = { id: string | number; recorded_at: string; online_players: number; max_players: number; tps: number | null; cpu_percent: number | null; memory_used_mb: number; memory_max_mb: number | null; uptime_seconds: number; version: string | null };
type MinecraftEvent = { id: string | number; event_type: string; nickname: string | null; created_at: string; command: string | null; message: string | null; world: string | null };
type MinecraftChatLog = { id: string | number; world: string | null; created_at: string; message: string };

const HEARTBEAT_TIMEOUT_MS = 2 * 60_000;
export default async function MonitoringPage() {
  const context = await requireAdminContext();
  if (!context || (!context.permissions.has("*") && !context.permissions.has("system.health") && !context.permissions.has("server.monitor"))) return null;
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.monitoring);
  const payload = (data ?? {}) as {
    metrics?: HeartbeatMetric[];
    events?: MinecraftEvent[];
    chat_logs?: MinecraftChatLog[];
  };
  const metrics = Array.isArray(payload.metrics) ? payload.metrics : [];
  const events = Array.isArray(payload.events) ? payload.events : [];
  const chatLogs = Array.isArray(payload.chat_logs) ? payload.chat_logs : [];
  const latest = metrics?.[0] ?? null;
  const fresh = !!latest && Date.now() - new Date(latest.recorded_at).getTime() <= HEARTBEAT_TIMEOUT_MS;
  const memoryPercent = latest?.memory_used_mb != null && latest.memory_max_mb ? Math.min(100, Math.round((latest.memory_used_mb / latest.memory_max_mb) * 100)) : null;

  return (
    <div className="space-y-6">
      <div><p className="font-mono text-xs uppercase tracking-[0.25em] text-curse">Minecraft bridge</p><h1 className="mt-1 font-display text-2xl text-moon">Мониторинг</h1><p className="mt-1 text-sm text-moon-dim">Paper → Supabase → PRISMA control-plane: heartbeat, чат, команды и join/leave.</p></div>
      {error && <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Метрики сервера недоступны: {error.message}</div>}
      {latest ? <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4"><StatCard label="Онлайн" value={`${latest.online_players}/${latest.max_players}`} hint={fresh ? "heartbeat актуален" : "heartbeat устарел"} /><StatCard label="TPS" value={latest.tps?.toFixed(2) ?? "—"} hint="цель 20.00" /><StatCard label="Память" value={formatMegabytes(latest.memory_used_mb)} hint={latest.memory_max_mb ? `з ${formatMegabytes(latest.memory_max_mb)} · ${memoryPercent}%` : undefined} /><StatCard label="Uptime" value={formatUptimeUk(latest.uptime_seconds)} hint={latest.version ?? undefined} /></div> : <Card className="p-8 text-center text-sm text-moon-dim">Heartbeat ещё не поступал.</Card>}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card className="overflow-hidden"><div className="border-b border-border p-4"><h2 className="font-medium text-moon">События Minecraft</h2><p className="text-xs text-moon-dim">JOIN, QUIT, CHAT, COMMAND</p></div><div className="max-h-[32rem] divide-y divide-border overflow-y-auto">{(events ?? []).map((e) => <div key={e.id} className="p-3"><div className="flex items-center gap-2"><span className="rounded-full bg-panel-raised px-2 py-0.5 font-mono text-[10px] text-curse">{e.event_type}</span><span className="font-mono text-xs text-moon">{e.nickname ?? "—"}</span><span className="ml-auto text-[11px] text-moon-dim">{formatDateTime(e.created_at)}</span></div>{e.command && <p className="mt-1 break-all font-mono text-xs text-moon">{e.command}</p>}{e.message && <p className="mt-1 whitespace-pre-wrap text-sm text-moon">{e.message}</p>}{e.world && <p className="mt-1 text-[11px] text-moon-dim">Мир: {e.world}</p>}</div>)}{!(events ?? []).length && <p className="p-8 text-center text-sm text-moon-dim">Событий ещё нет.</p>}</div></Card>
        <Card className="overflow-hidden"><div className="border-b border-border p-4"><h2 className="font-medium text-moon">Minecraft-чат</h2><p className="text-xs text-moon-dim">Последние сообщения</p></div><div className="max-h-[32rem] divide-y divide-border overflow-y-auto">{(chatLogs ?? []).map((e) => <div key={e.id} className="p-3"><p className="text-xs text-moon-dim">{e.world ?? "—"} · {formatDateTime(e.created_at)}</p><p className="mt-1 whitespace-pre-wrap text-sm text-moon">{e.message}</p></div>)}{!(chatLogs ?? []).length && <p className="p-8 text-center text-sm text-moon-dim">Сообщений ещё нет.</p>}</div></Card>
      </div>
      <Card className="overflow-hidden"><div className="border-b border-border p-4"><h2 className="font-medium text-moon">История heartbeat</h2></div><div className="overflow-x-auto"><table className="w-full min-w-[700px] text-left text-sm"><thead><tr className="border-b border-border text-xs uppercase tracking-wide text-moon-dim"><th className="p-3">Час</th><th className="p-3">Онлайн</th><th className="p-3">TPS</th><th className="p-3">CPU</th><th className="p-3">Память</th><th className="p-3">Версия</th></tr></thead><tbody>{(metrics ?? []).slice(0, 30).map((m) => <tr key={m.id} className="border-b border-border/60"><td className="p-3 text-moon-dim">{formatDateTime(m.recorded_at)}</td><td className="p-3 text-moon">{m.online_players}/{m.max_players}</td><td className="p-3 text-moon">{m.tps?.toFixed(2) ?? "—"}</td><td className="p-3 text-moon">{typeof m.cpu_percent === "number" ? m.cpu_percent.toFixed(1) : "—"}</td><td className="p-3 text-moon">{formatMegabytes(m.memory_used_mb)}</td><td className="p-3 text-moon-dim">{m.version ?? "—"}</td></tr>)}</tbody></table></div></Card>
    </div>
  );
}