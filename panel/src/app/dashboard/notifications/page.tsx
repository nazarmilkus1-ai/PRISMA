import { formatDateTime } from "@prisma-eco/shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { Badge, Card, StatCard } from "@/components/ui";
import { STAFF_RPC } from "@prisma-eco/contracts";

type NotificationRow = { id: string | number; status: string; kind: string; channel: string; telegram_id: number | null; created_at: string; title: string | null; body: string; last_error: string | null };

export default async function NotificationsPage() {
  const admin = await requireAdmin("admin.view_audit");
  if (!admin) return null;
  const db = await createSupabaseServerClient();
  const statusLabels: Record<string, string> = { pending: "В очереди", sending: "Отправляется", sent: "Отправлено", failed: "Ошибка", cancelled: "Отменено", read: "Прочитано" };
  const { data, error } = await db.rpc(STAFF_RPC.notifications, { p_limit: 200 });
  const notifications = Array.isArray(data) ? data as NotificationRow[] : [];
  const pending = notifications.filter((n) => n.status === "pending").length;
  const failed = notifications.filter((n) => n.status === "failed").length;
  return <div className="space-y-6"><div><h1 className="font-display text-2xl text-moon">Уведомления</h1><p className="mt-1 text-sm text-moon-dim">Центральная очередь Telegram-уведомлений для заявок, модерации, репортов и системных событий.</p></div>
    {error&&<div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Не удалось загрузить очередь: {error.message}</div>}
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-3"><StatCard label="В очереди" value={pending??0}/><StatCard label="Ошибки доставки" value={failed??0}/><StatCard label="Показано" value={notifications?.length??0}/></div>
    <Card className="divide-y divide-border overflow-hidden">{(notifications??[]).map((n)=><div key={n.id} className="p-4"><div className="flex flex-wrap items-center gap-2"><Badge tone={n.status==="sent"?"success":n.status==="failed"?"danger":n.status==="pending"?"warn":"neutral"}>{statusLabels[n.status] ?? n.status}</Badge><span className="font-mono text-xs text-curse">{n.kind}</span><span className="text-xs text-moon-dim">{n.channel} · {n.telegram_id??"—"}</span><span className="ml-auto text-xs text-moon-dim">{formatDateTime(n.created_at)}</span></div><p className="mt-2 text-sm font-medium text-moon">{n.title??"Уведомления"}</p><p className="mt-1 whitespace-pre-wrap text-sm text-moon-dim">{n.body}</p>{n.last_error&&<p className="mt-1 text-xs text-danger">{n.last_error}</p>}</div>)}{!(notifications??[]).length&&<p className="p-10 text-center text-sm text-moon-dim">Очередь пуста.</p>}</Card>
  </div>;
}
