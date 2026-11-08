import { formatDateTime } from "@prisma-eco/shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { Card, StatCard } from "@/components/ui";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function AuditPage() {
  const context = await requireAdminContext("admin.view_audit");
  if (!context) return null;
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.auditLogs, { p_limit: 300 });
  const logs = Array.isArray(data) ? data : [];
  return <div className="space-y-6">
    <div><p className="font-mono text-xs uppercase tracking-[0.25em] text-curse">Control trail</p><h1 className="mt-1 font-display text-2xl text-moon">Аудит</h1><p className="mt-1 text-sm text-moon-dim">Неизменяемая история административных действий.</p></div>
    <StatCard label="Админ-действий · все записи" value={(logs ?? []).length} />
    {error && <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Не удалось загрузить журнал: {error.message}</div>}
    <Card className="overflow-hidden"><div className="overflow-x-auto"><table className="w-full min-w-[900px] text-left text-sm">
      <thead><tr className="border-b border-border text-xs uppercase tracking-wide text-moon-dim"><th className="p-3">Время</th><th className="p-3">Администратор</th><th className="p-3">Действие</th><th className="p-3">Ресурс</th><th className="p-3">ID</th><th className="p-3">Детали</th></tr></thead>
      <tbody>{(logs ?? []).map(log => { const actor=log.actor; const name=actor?.telegram_username?"@"+actor.telegram_username:actor?.minecraft_nickname??actor?.full_name??"—"; return <tr key={log.id} className="border-b border-border/60 align-top"><td className="whitespace-nowrap p-3 text-xs text-moon-dim">{formatDateTime(log.created_at)}</td><td className="p-3"><p className="text-moon">{name}</p><p className="font-mono text-[11px] text-moon-dim">{log.actor_tg_id??"—"}</p></td><td className="p-3 font-mono text-xs text-curse">{log.action}</td><td className="p-3 text-moon">{log.target_type??"—"}</td><td className="p-3 font-mono text-[11px] text-moon-dim">{log.target_id??"—"}</td><td className="max-w-[28rem] p-3"><pre className="whitespace-pre-wrap break-words font-mono text-[11px] text-moon-dim">{JSON.stringify({old:log.old_data,new:log.new_data},null,2)}</pre></td></tr>; })}</tbody>
    </table></div>{!(logs ?? []).length&&<div className="p-10 text-center text-sm text-moon-dim">Пока нет записей аудита.</div>}</Card>
  </div>;
}
