"use client";

import { formatDateTime } from "@prisma-eco/shared";

import { APPEAL_STATUS_LABELS } from "@prisma-eco/contracts";

import { useEffect, useMemo, useState } from "react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue, Textarea } from "@prisma-eco/ui";

type Appeal = {
  id: string;
  user_id: string;
  telegram_id: number;
  punishment_id: string | null;
  reason: string;
  status: "OPEN" | "IN_REVIEW" | "APPROVED" | "REJECTED";
  review_note: string | null;
  created_at: string;
  updated_at: string;
  user?: { minecraft_nickname?: string | null; telegram_username?: string | null; full_name?: string | null };
  punishment?: { type?: string; reason?: string; duration_minutes?: number | null; expires_at?: string | null; revoked?: boolean };
};

const FILTERS = [
  { value: "OPEN", label: "Открытые" },
  { value: "IN_REVIEW", label: "В работе" },
  { value: "APPROVED", label: "Одобренные" },
  { value: "REJECTED", label: "Отклонённые" },
  { value: "ALL", label: "Все" },
] as const;

export function AppealsPanel({ initialAppeals }: { initialAppeals: Appeal[] }) {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]["value"]>("OPEN");
  const [rows, setRows] = useState<Appeal[]>(initialAppeals);
  const [selected, setSelected] = useState<Appeal | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function load(nextFilter = filter) {
    setError("");
    const response = await fetch("/admin/api/appeals?status=" + encodeURIComponent(nextFilter), { cache: "no-store" });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Не удалось загрузить апелляции.");
    setRows(payload.appeals || []);
  }

  useEffect(() => {
    void load(filter).catch((e) => setError(e instanceof Error ? e.message : "Не удалось загрузить апелляции."));
  }, [filter]);

  const visible = useMemo(() => rows, [rows]);

  async function openAppeal(id: string) {
    setError("");
    const response = await fetch("/admin/api/appeals/" + id, { cache: "no-store" });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Не удалось открыть апелляцию.");
    setSelected(payload);
    setNote(payload.review_note || "");
  }

  async function change(action: "REVIEW" | "APPROVE" | "REJECT") {
    if (!selected) return;
    setBusy(true);
    setError("");
    try {
      const response = await fetch("/admin/api/appeals/" + selected.id, {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action, note: note.trim() || undefined }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Не удалось обновить апелляцию.");
      await load(filter);
      if (selected?.id) await openAppeal(selected.id);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось обновить апелляцию.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.25fr)]">
      <Card className="overflow-hidden">
        <CardHeader>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <CardTitle>Очередь</CardTitle>
            <Select value={filter} onValueChange={(value) => setFilter(value as typeof filter)}>
              <SelectTrigger size="sm" className="w-[150px]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="end">
                <SelectGroup>
                  {FILTERS.map((item) => (
                    <SelectItem key={item.value} value={item.value}>{item.label}</SelectItem>
                  ))}
                </SelectGroup>
              </SelectContent>
            </Select>
          </div>
        </CardHeader>
        <CardContent className="p-2">
          {visible.length === 0 ? (
            <p className="p-5 text-sm text-moon-dim">Апелляций по текущему фильтру нет.</p>
          ) : visible.map((appeal) => {
            const name = appeal.user?.minecraft_nickname || appeal.user?.telegram_username || appeal.user?.full_name || String(appeal.telegram_id);
            return (
              <button
                key={appeal.id}
                type="button"
                onClick={() => void openAppeal(appeal.id).catch((e) => setError(e instanceof Error ? e.message : "Ошибка"))}
                className={"w-full rounded-lg px-3 py-3 text-left hover:bg-panel-raised " + (selected?.id === appeal.id ? "bg-panel-raised" : "")}
              >
                <div className="flex items-center gap-2">
                  <span className="font-medium text-moon">{name}</span>
                  <Badge variant={appeal.status === "APPROVED" ? "success" : appeal.status === "REJECTED" ? "destructive" : appeal.status === "IN_REVIEW" ? "warning" : "secondary"}>
                    {APPEAL_STATUS_LABELS[appeal.status]}
                  </Badge>
                </div>
                <p className="mt-1 truncate text-xs text-moon-dim">{appeal.punishment?.type || "Наказание"} · {appeal.reason}</p>
                <p className="mt-1 text-[11px] text-moon-dim">{formatDateTime(appeal.created_at)}</p>
              </button>
            );
          })}
        </CardContent>
      </Card>

      <Card>
        {!selected ? (
          <CardContent className="p-5 text-sm text-moon-dim">Выберите апелляцию слева.</CardContent>
        ) : (
          <>
            <CardHeader>
              <CardTitle>
                {selected.user?.minecraft_nickname || selected.user?.telegram_username || "Игрок"}
              </CardTitle>
              <p className="text-sm text-moon-dim">{APPEAL_STATUS_LABELS[selected.status]} · {formatDateTime(selected.created_at)}</p>
            </CardHeader>
            <CardContent className="space-y-5">
              <section className="rounded-lg border border-border bg-panel-raised p-3">
                <p className="text-xs text-moon-dim">Наказание</p>
                <p className="mt-1 font-medium text-moon">{selected.punishment?.type || "—"}</p>
                <p className="mt-1 text-sm text-moon-dim">{selected.punishment?.reason || "Причина не указана"}</p>
                {selected.punishment?.expires_at ? <p className="mt-1 text-xs text-moon-dim">До: {formatDateTime(selected.punishment.expires_at)}</p> : null}
              </section>

              <section>
                <p className="text-xs text-moon-dim">Текст апелляции</p>
                <p className="mt-1 whitespace-pre-wrap rounded-lg border border-border p-3 text-sm leading-6 text-moon">{selected.reason}</p>
              </section>

              <section>
                <p className="text-xs text-moon-dim">Комментарий администрации</p>
                <Textarea value={note} onChange={(e) => setNote(e.target.value)} maxLength={5000} placeholder="Комментарий, который увидит игрок." />
              </section>

              {error ? <p className="rounded-lg border border-danger/30 bg-danger/10 p-3 text-sm text-danger">{error}</p> : null}

              <div className="flex flex-wrap justify-end gap-2">
                {selected.status === "OPEN" ? <Button variant="outline" disabled={busy} onClick={() => void change("REVIEW")}>Взять в работу</Button> : null}
                {(selected.status === "OPEN" || selected.status === "IN_REVIEW") ? (
                  <>
                    <Button variant="destructive" disabled={busy} onClick={() => void change("REJECT")}>Отклонить</Button>
                    <Button disabled={busy} onClick={() => void change("APPROVE")}>Одобрить</Button>
                  </>
                ) : null}
              </div>
            </CardContent>
          </>
        )}
      </Card>
    </div>
  );
}
