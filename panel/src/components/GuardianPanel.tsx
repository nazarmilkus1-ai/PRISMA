"use client";

import { useState } from "react";

type Proposal = {
  id: string; created_at: string; source: string; kind: string; title: string; body: string;
  status: string; result: string | null;
};
type EventRow = { id: number; created_at: string; severity: string; summary: string };
export type GuardianOverview = {
  proposals: Proposal[];
  events: EventRow[];
  state: Record<string, { at?: string; bot_ok?: boolean; down_since?: number | null }>;
};

const STATUS: Record<string, string> = {
  pending: "Ждёт решения", approved: "Подтверждено", rejected: "Отклонено",
  executed: "Выполнено", failed: "Ошибка", expired: "Истекло",
};

export function GuardianPanel({ initial, canManage }: { initial: GuardianOverview; canManage: boolean }) {
  const [data, setData] = useState(initial);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const refresh = async () => {
    const res = await fetch("/admin/api/guardian/proposals", { cache: "no-store" });
    if (res.ok) setData(await res.json());
  };

  const decide = async (id: string, approve: boolean) => {
    setBusy(id);
    setMessage(null);
    const previous = data;
    setData((d) => ({ ...d, proposals: d.proposals.map((p) => (p.id === id ? { ...p, status: approve ? "approved" : "rejected" } : p)) }));
    const res = await fetch("/admin/api/guardian/proposals", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, approve }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) setData(previous);
    setMessage(res.ok ? (body.result ?? (approve ? "Готово." : "Отклонено.")) : (typeof body.error === "string" ? body.error : "Ошибка."));
    setBusy(null);
    await refresh();
  };

  const tick = data.state.last_tick;
  const down = data.state.bot?.down_since;

  return (
    <div className="space-y-6">
      <div className="rounded-lg border p-4 text-sm">
        <div>Последняя проверка: <b>{tick?.at ? new Date(tick.at).toLocaleString("ru-RU") : "ещё не было"}</b></div>
        <div>Бот: <b>{tick?.bot_ok === undefined ? "—" : tick.bot_ok ? "отвечает" : "НЕ отвечает"}</b>{down ? ` (с ${new Date(down).toLocaleTimeString("ru-RU")})` : ""}</div>
      </div>

      {message && <div className="rounded-lg border p-3 text-sm">{message}</div>}

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">Предложения</h2>
        {data.proposals.length === 0 && <p className="text-sm opacity-70">Пока пусто.</p>}
        {data.proposals.map((p) => (
          <div key={p.id} className="rounded-lg border p-4 space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <b>{p.title}</b>
              <span className="text-xs opacity-70">{STATUS[p.status] ?? p.status} · {p.source} · {new Date(p.created_at).toLocaleString("ru-RU")}</span>
            </div>
            {p.body && <p className="text-sm whitespace-pre-wrap">{p.body}</p>}
            {p.result && <p className="text-xs opacity-70">Результат: {p.result}</p>}
            {p.status === "pending" && canManage && (
              <div className="flex gap-2">
                <button disabled={busy === p.id} onClick={() => decide(p.id, true)} className="rounded bg-green-600 px-3 py-1 text-sm text-white disabled:opacity-50">Подтвердить</button>
                <button disabled={busy === p.id} onClick={() => decide(p.id, false)} className="rounded border px-3 py-1 text-sm disabled:opacity-50">Отклонить</button>
              </div>
            )}
          </div>
        ))}
      </section>

      <section className="space-y-2">
        <h2 className="text-lg font-semibold">Журнал</h2>
        <ul className="space-y-1 text-sm">
          {data.events.map((e) => (
            <li key={e.id}>
              <span className="opacity-60">{new Date(e.created_at).toLocaleString("ru-RU")}</span>{" "}
              {e.severity === "error" ? "🔴" : e.severity === "warn" ? "🟡" : "🟢"} {e.summary}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
