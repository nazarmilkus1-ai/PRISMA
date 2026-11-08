import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { Badge, Card, StatCard } from "@/components/ui";
import { STAFF_RPC } from "@prisma-eco/contracts";
import { formatDateTime } from "@prisma-eco/shared";

type SecurityLogin = { id: string | number; success: boolean; method: string; telegram_id: number | null; created_at: string; ip_hash: string | null; user_agent: string | null };
type SecurityEvent = { id: string | number; risk_score: number | null; event_type: string; telegram_id: number | null; created_at: string; payload: unknown };
type SecuritySnapshot = { events?: SecurityEvent[]; logins?: SecurityLogin[] };

export default async function SecurityPage() {
  const admin = await requireAdmin("admin.view_audit");
  if (!admin) return null;
  const db=await createSupabaseServerClient();
  const { data: snapshot, error: snapshotError } = await db.rpc(STAFF_RPC.securitySnapshot, { p_limit: 200 });
  const payload=(snapshot??{}) as SecuritySnapshot;
  const risks=Array.isArray(payload.events)?payload.events:[];
  const rows=Array.isArray(payload.logins)?payload.logins:[];
  const successes=rows.filter((x)=>x.success).length,failures=rows.length-successes;
  return <div className="space-y-6">
    <div><p className="font-mono text-xs uppercase tracking-[0.25em] text-curse">Security center</p><h1 className="mt-1 font-display text-2xl text-moon">Безопасность</h1><p className="mt-1 text-sm text-moon-dim">История входов, подозрительная активность и risk events.</p></div>
    {(snapshotError)&&<div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Частина security-даних недоступна.</div>}
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-3"><StatCard label="Всего входов" value={rows.length}/><StatCard label="Успешные входы" value={successes}/><StatCard label="Неудачные входы" value={failures}/></div>
    <Card className="overflow-hidden"><div className="border-b border-border p-4"><h2 className="font-medium text-moon">История входов</h2><p className="mt-1 text-xs text-moon-dim">Успешные и неудачные попытки входа в панель.</p></div><div className="divide-y divide-border">
      {rows.map(e=><div key={e.id} className="p-4"><div className="flex flex-wrap items-center gap-2"><Badge tone={e.success?"success":"danger"}>{e.success?"Успешно":"Помилка"}</Badge><span className="font-mono text-xs text-curse">{e.method}</span><span className="text-moon">Telegram {e.telegram_id??"—"}</span><span className="ml-auto text-xs text-moon-dim">{formatDateTime(e.created_at)}</span></div><p className="mt-1 text-xs text-moon-dim">{e.ip_hash?("IP fingerprint: "+e.ip_hash):"IP fingerprint отсутствует"}{e.user_agent?(" · "+e.user_agent):""}</p></div>)}
      {!rows.length&&<p className="p-10 text-center text-sm text-moon-dim">История входов пока пуста. Следующий вход будет автоматически записан.</p>}
    </div></Card>
    <Card className="overflow-hidden"><div className="border-b border-border p-4"><h2 className="font-medium text-moon">Security events</h2></div><div className="divide-y divide-border">{risks.map(e=><div key={e.id} className="p-4"><div className="flex flex-wrap items-center gap-2"><Badge tone={(e.risk_score ?? 0)>=70?"danger":(e.risk_score ?? 0)>=40?"warn":"neutral"}>risk {e.risk_score??0}</Badge><span className="font-mono text-xs text-curse">{e.event_type}</span><span className="text-xs text-moon-dim">{e.telegram_id??"—"}</span><span className="ml-auto text-xs text-moon-dim">{formatDateTime(e.created_at)}</span></div>{e.payload !== null && e.payload !== undefined && <pre className="mt-2 max-h-32 overflow-auto rounded-lg bg-panel-raised p-2 font-mono text-[11px] text-moon-dim">{JSON.stringify(e.payload,null,2)}</pre>}</div>)}{!risks.length&&<p className="p-10 text-center text-sm text-moon-dim">Security events пока отсутствуют.</p>}</div></Card>
  </div>;
}
