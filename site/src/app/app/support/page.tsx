"use client";

import { SUPPORT_TICKET_STATUS_LABELS } from "@prisma-eco/contracts";

function statusClass(status: Ticket["status"]) {
  return status === "RESOLVED" || status === "CLOSED"
    ? "prisma-glass-badge border-primary/35 text-primary"
    : status === "IN_REVIEW"
      ? "prisma-glass-badge border-yellow-500/35 text-yellow-500"
      : "prisma-glass-badge border-blue-500/35 text-blue-500";
}

function fmt(value: string) {
  return new Date(value).toLocaleString("ru-RU");
}

import { useEffect, useMemo, useState } from "react";
import { Card } from "@/components/Card";
import { SectionTitle } from "@/components/SitePrimitives";

type Ticket = {
  id: string;
  ticket_no: number;
  status: "OPEN" | "IN_REVIEW" | "RESOLVED" | "CLOSED";
  created_at: string;
  updated_at: string;
  resolved_at: string | null;
  message_count: number;
  last_message_at: string | null;
};
type Message = {
  id: string;
  author_kind: "USER" | "STAFF";
  message: string;
  created_at: string;
  delivery_status: string;
};
type Detail = { ticket: Ticket; messages: Message[] };

export default function SupportPage() {
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [selected, setSelected] = useState<Detail | null>(null);
  const [newMessage, setNewMessage] = useState("");
  const [reply, setReply] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function loadTickets() {
    setLoading(true);
    try {
      const res = await fetch("/api/support", { cache: "no-store" });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось загрузить поддержку.");
      setTickets(Array.isArray(data.tickets) ? data.tickets : []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось загрузить поддержку.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void loadTickets(); }, []);

  useEffect(() => {
    const raw = new URLSearchParams(window.location.search).get("ticket_no");
    const ticketNo = Number(raw);
    if (!raw || !Number.isSafeInteger(ticketNo) || ticketNo <= 0) return;
    let cancelled = false;

    void (async () => {
      try {
        const res = await fetch("/api/support/" + ticketNo, { cache: "no-store" });
        const data = await res.json().catch(() => ({}));
        if (!cancelled && res.ok) setSelected(data);
        else if (!cancelled) setError(data.error ?? "Не удалось открыть обращение.");
      } catch {
        if (!cancelled) setError("Не удалось открыть обращение.");
      }
    })();

    return () => { cancelled = true; };
  }, []);

  async function openTicket(ticketNo: number) {
    setError(null);
    const res = await fetch("/api/support/" + ticketNo, { cache: "no-store" });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) { setError(data.error ?? "Не удалось открыть обращение."); return; }
    setSelected(data);
  }

  async function createTicket() {
    if (!newMessage.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/support", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: newMessage }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось создать обращение.");
      setNewMessage("");
      await loadTickets();
      if (data.ticket_no) await openTicket(Number(data.ticket_no));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось создать обращение.");
    } finally {
      setBusy(false);
    }
  }

  async function sendReply() {
    if (!selected || !reply.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/support/" + selected.ticket.ticket_no, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: reply }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось отправить сообщение.");
      setReply("");
      await openTicket(selected.ticket.ticket_no);
      await loadTickets();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось отправить сообщение.");
    } finally {
      setBusy(false);
    }
  }

  const openCount = useMemo(() => tickets.filter((t) => t.status === "OPEN" || t.status === "IN_REVIEW").length, [tickets]);

  return (
    <div className="space-y-6">
      <SectionTitle
        eyebrow="УЧАСТИЕ"
        title="Техническая поддержка"
        description="Опишите проблему. Ответ сотрудника PRISMA появится здесь и будет отправлен вам в Telegram."
      />

      {error ? <Card className="prisma-glass-surface border-red-500/30 p-4 text-sm text-red-400">{error}</Card> : null}

      <Card>
        <div className="p-5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p className="font-semibold">Новое обращение</p>
              <p className="mt-1 text-sm text-[var(--muted-foreground)]">От 3 до 4000 символов. Не указывайте пароли и коды входа. Максимум 2 новых обращения в день.</p>
            </div>
            <span className="text-xs text-[var(--muted-foreground)]">Активных: {openCount}</span>
          </div>
          <textarea
            value={newMessage}
            onChange={(e) => setNewMessage(e.target.value)}
            rows={5}
            maxLength={4000}
            placeholder="Например: не получается войти на сервер..."
            className="prisma-glass-control mt-4 w-full resize-y rounded-xl border px-3 py-3 text-sm text-foreground outline-none focus:border-[var(--primary)]"
          />
          <div className="mt-3 flex justify-end">
            <button
              onClick={() => void createTicket()}
              disabled={busy || newMessage.trim().length < 3}
              className="prisma-glass-primary prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-semibold text-primary disabled:opacity-40"
            >
              Отправить в поддержку
            </button>
          </div>
        </div>
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b p-5">
          <p className="font-semibold">Мои обращения</p>
        </div>
        {loading ? (
          <p className="p-8 text-center text-sm text-[var(--muted-foreground)]">Загрузка…</p>
        ) : !tickets.length ? (
          <p className="p-8 text-center text-sm text-[var(--muted-foreground)]">Обращений пока нет.</p>
        ) : (
          <div className="divide-y">
            {tickets.map((ticket) => (
              <button key={ticket.id} type="button" onClick={() => void openTicket(ticket.ticket_no)} className="prisma-glass-hover flex w-full items-center gap-3 p-5 text-left transition">
                <span className="font-mono text-sm">#{ticket.ticket_no}</span>
                <span className={"rounded-lg border px-2 py-1 text-xs font-medium " + statusClass(ticket.status)}>{SUPPORT_TICKET_STATUS_LABELS[ticket.status] ?? ticket.status}</span>
                <span className="ml-auto text-xs text-[var(--muted-foreground)]">{ticket.message_count} сообщ. · {fmt(ticket.updated_at)}</span>
              </button>
            ))}
          </div>
        )}
      </Card>

      {selected ? (
        <Card>
          <div className="border-b p-5">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="font-mono text-xs text-[var(--muted-foreground)]">Тикет #{selected.ticket.ticket_no}</p>
                <p className="mt-1 font-semibold">{SUPPORT_TICKET_STATUS_LABELS[selected.ticket.status] ?? selected.ticket.status}</p>
              </div>
              <span className={"rounded-lg border px-2 py-1 text-xs font-medium " + statusClass(selected.ticket.status)}>{SUPPORT_TICKET_STATUS_LABELS[selected.ticket.status] ?? selected.ticket.status}</span>
            </div>
          </div>
          <div className="space-y-3 p-5">
            {selected.messages.map((item) => (
              <div key={item.id} className={"prisma-glass-surface rounded-xl border p-4 " + (item.author_kind === "STAFF" ? "ml-8 border-[var(--primary)]/30" : "mr-8")}>
                <div className="flex items-center justify-between gap-2">
                  <span className="text-xs font-semibold">{item.author_kind === "STAFF" ? "Поддержка PRISMA" : "Вы"}</span>
                  <time className="text-[11px] text-[var(--muted-foreground)]">{fmt(item.created_at)}</time>
                </div>
                <p className="mt-2 whitespace-pre-wrap text-sm leading-6">{item.message}</p>
              </div>
            ))}
          </div>
          {(selected.ticket.status === "OPEN" || selected.ticket.status === "IN_REVIEW") ? (
            <div className="border-t p-5">
              <textarea
                value={reply}
                onChange={(e) => setReply(e.target.value)}
                rows={4}
                maxLength={4000}
                placeholder="Дополнить обращение…"
                className="prisma-glass-control w-full resize-y rounded-xl border px-3 py-3 text-sm text-foreground outline-none focus:border-[var(--primary)]"
              />
              <div className="mt-3 flex justify-end">
                <button disabled={busy || !reply.trim()} onClick={() => void sendReply()} className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-semibold text-foreground disabled:opacity-40">
                  Отправить сообщение
                </button>
              </div>
            </div>
          ) : (
            <div className="border-t p-5 text-sm text-[var(--muted-foreground)]">Обращение закрыто. Для новой проблемы создайте новый тикет.</div>
          )}
        </Card>
      ) : null}
    </div>
  );
}
