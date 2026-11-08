"use client";

import { SUPPORT_TICKET_STATUS_LABELS } from "@prisma-eco/contracts";

import { fetchJson, formatDateTime } from "@prisma-eco/shared";

import { useEffect, useMemo, useState } from "react";
import { Avatar, Badge, Card, Tabs, InfoItem } from "@/components/ui";
import { SimplePagination } from "@prisma-eco/ui";
import { Modal } from "@/components/Modal";

type Status = "OPEN" | "IN_REVIEW" | "RESOLVED" | "CLOSED";
type Ticket = {
  id: string;
  ticket_no: number;
  user_id: string | null;
  telegram_id: number;
  status: Status;
  admin_note: string | null;
  created_at: string;
  updated_at: string;
  resolved_at: string | null;
  minecraft_nickname: string | null;
  telegram_username: string | null;
  full_name: string | null;
  first_name: string | null;
  last_name: string | null;
  message_count: number;
  last_message_at: string | null;
};
type Recipient = {
  id: string;
  telegram_id: number;
  telegram_username: string | null;
  first_name: string | null;
  full_name: string | null;
  minecraft_nickname: string | null;
  status: string | null;
  platform: string | null;
  is_banned: boolean;
};
type Message = {
  id: string;
  author_kind: "USER" | "STAFF";
  author_name: string;
  telegram_username: string | null;
  minecraft_nickname: string | null;
  message: string;
  delivery_status: string;
  delivery_error: string | null;
  created_at: string;
  sent_at: string | null;
};
type Detail = { ticket: Ticket; messages: Message[] };
type SupportListResponse = { error?: string; tickets?: Ticket[] };
type SupportPlayersResponse = { error?: string; players?: Recipient[] };
type SupportDetailResponse = Detail & { error?: string };

const FILTERS = [
  { key: "OPEN", label: "Открытые" },
  { key: "IN_REVIEW", label: "В работе" },
  { key: "RESOLVED", label: "Решённые" },
  { key: "CLOSED", label: "Закрытые" },
  { key: "ALL", label: "Все" },
] as const;
const PAGE_SIZE = 15;

function person(ticket: Ticket) {
  if (ticket.telegram_username) return "@" + ticket.telegram_username;
  return ticket.minecraft_nickname ?? ticket.full_name ?? ticket.first_name ?? "Без username";
}

function statusTone(status: Status) {
  if (status === "OPEN") return "warn" as const;
  if (status === "IN_REVIEW") return "curse" as const;
  if (status === "RESOLVED") return "success" as const;
  return "neutral" as const;
}

export function SupportPanel({ initialRecipientId }: { initialRecipientId?: string }) {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]["key"]>("OPEN");
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [page, setPage] = useState(1);
  const [message, setMessage] = useState("");
  const [closeAfterReply, setCloseAfterReply] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showNewConversation, setShowNewConversation] = useState(false);
  const [recipientQuery, setRecipientQuery] = useState("");
  const [recipients, setRecipients] = useState<Recipient[]>([]);
  const [selectedRecipient, setSelectedRecipient] = useState<Recipient | null>(null);
  const [searchingRecipients, setSearchingRecipients] = useState(false);
  const [initialMessage, setInitialMessage] = useState("");

  async function load(nextFilter = filter) {
    setLoading(true);
    try {
      const { response: res, data } = await fetchJson<SupportListResponse>("/admin/api/support?status=" + encodeURIComponent(nextFilter), { cache: "no-store" });
      if (!res.ok) throw new Error(data.error ?? "Не удалось загрузить обращения.");
      setTickets(Array.isArray(data.tickets) ? data.tickets : []);
      setPage(1);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось загрузить обращения.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, [filter]);

  useEffect(() => {
    if (!initialRecipientId) return;
    let cancelled = false;
    setShowNewConversation(true);
    setRecipientQuery(initialRecipientId);
    setSearchingRecipients(true);

    void (async () => {
      try {
        const { response: res, data } = await fetchJson<SupportPlayersResponse>("/admin/api/support/players?q=" + encodeURIComponent(initialRecipientId), { cache: "no-store" });
        if (!res.ok) throw new Error(data.error ?? "Не удалось загрузить игрока.");
        const players = Array.isArray(data.players) ? data.players as Recipient[] : [];
        if (cancelled) return;
        setRecipients(players);
        const recipient = players.find((player) => player.id === initialRecipientId);
        if (recipient) setSelectedRecipient(recipient);
        else setError("Не удалось найти игрока по ссылке из его профиля.");
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : "Не удалось загрузить игрока.");
      } finally {
        if (!cancelled) setSearchingRecipients(false);
      }
    })();

    return () => { cancelled = true; };
  }, [initialRecipientId]);

  async function searchRecipients() {
    const query = recipientQuery.trim();
    if (query.length < 2) {
      setRecipients([]);
      setError("Введите минимум 2 символа для поиска.");
      return;
    }
    setSearchingRecipients(true);
    setError(null);
    try {
      const { response: res, data } = await fetchJson<SupportPlayersResponse>("/admin/api/support/players?q=" + encodeURIComponent(query), { cache: "no-store" });
      if (!res.ok) throw new Error(data.error ?? "Не удалось найти игрока.");
      setRecipients(Array.isArray(data.players) ? data.players : []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось найти игрока.");
    } finally {
      setSearchingRecipients(false);
    }
  }

  async function startConversation() {
    if (!selectedRecipient || !initialMessage.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/admin/api/support", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: selectedRecipient.id, message: initialMessage }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось начать диалог с игроком.");
      setShowNewConversation(false);
      setRecipientQuery("");
      setRecipients([]);
      setSelectedRecipient(null);
      setInitialMessage("");
      setFilter("OPEN");
      await load("OPEN");
      if (data.ticket_no) await openTicket(Number(data.ticket_no));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось начать диалог с игроком.");
    } finally {
      setBusy(false);
    }
  }

  async function openTicket(ticketNo: number) {
    setError(null);
    const { response: res, data } = await fetchJson<SupportDetailResponse>("/admin/api/support/" + ticketNo, { cache: "no-store" });
    if (!res.ok) { setError(data?.error ?? "Не удалось открыть тикет."); return; }
    setDetail(data);
    setMessage("");
    setCloseAfterReply(false);
  }

  async function reply() {
    if (!detail || !message.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/admin/api/support/" + detail.ticket.ticket_no, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message, close: closeAfterReply }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось отправить ответ.");
      setMessage("");
      setCloseAfterReply(false);
      await openTicket(detail.ticket.ticket_no);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось отправить ответ.");
    } finally {
      setBusy(false);
    }
  }

  async function setStatus(status: Status) {
    if (!detail) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/admin/api/support/" + detail.ticket.ticket_no, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось изменить статус.");
      await openTicket(detail.ticket.ticket_no);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось изменить статус.");
    } finally {
      setBusy(false);
    }
  }

  const totalPages = Math.max(1, Math.ceil(tickets.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visible = useMemo(() => tickets.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE), [tickets, currentPage]);

  return (
    <>
      <div className="space-y-4">
        {error && <div className="rounded-xl border border-danger/30 bg-danger/10 p-3 text-sm text-danger">{error}</div>}
        <div className="flex justify-end">
          <button
            type="button"
            onClick={() => setShowNewConversation((value) => !value)}
            className="rounded-lg bg-ember/15 px-4 py-2.5 text-sm text-ember hover:bg-ember/25"
          >
            {showNewConversation ? "Отменить" : "Написать игроку"}
          </button>
        </div>

        {showNewConversation && (
          <Card className="p-4">
            <div className="space-y-3">
              <div>
                <h2 className="font-medium text-moon">Новое обращение от PRISMA</h2>
                <p className="mt-1 text-xs text-moon-dim">Первое сообщение создаст тикет и уйдёт игроку в Telegram. Дальше переписка будет в истории обращения.</p>
              </div>

              <div className="flex flex-col gap-2 sm:flex-row">
                <input
                  value={recipientQuery}
                  onChange={(e) => { setRecipientQuery(e.target.value); setSelectedRecipient(null); setRecipients([]); }}
                  onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void searchRecipients(); } }}
                  placeholder="Minecraft-ник, @username, имя или Telegram ID…"
                  className="min-w-0 flex-1 rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse"
                />
                <button
                  type="button"
                  onClick={() => void searchRecipients()}
                  disabled={searchingRecipients || recipientQuery.trim().length < 2}
                  className="rounded-lg border border-border px-4 py-2.5 text-sm text-moon-dim hover:text-moon disabled:opacity-40"
                >
                  {searchingRecipients ? "Ищу…" : "Найти"}
                </button>
              </div>

              {recipients.length > 0 && !selectedRecipient && (
                <div className="max-h-56 divide-y divide-border overflow-y-auto rounded-lg border border-border">
                  {recipients.map((player) => (
                    <button
                      key={player.id}
                      type="button"
                      onClick={() => setSelectedRecipient(player)}
                      className="flex w-full items-center gap-3 p-3 text-left hover:bg-panel-raised/50"
                    >
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm text-moon">{player.minecraft_nickname ?? player.full_name ?? player.first_name ?? "Без имени"}</span>
                        <span className="mt-0.5 block truncate text-xs text-moon-dim">
                          {player.telegram_username ? "@" + player.telegram_username : "username не указан"}
                          {" · Telegram ID "}{player.telegram_id}
                          {player.is_banned ? " · бан" : ""}
                        </span>
                      </span>
                      <span className="text-xs text-ember">Выбрать</span>
                    </button>
                  ))}
                </div>
              )}

              {recipients.length === 0 && recipientQuery.trim().length >= 2 && !searchingRecipients && (
                <p className="text-xs text-moon-dim">Ничего не найдено. Нажмите «Найти» после изменения запроса.</p>
              )}

              {selectedRecipient && (
                <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-curse/20 bg-curse/5 p-3">
                  <div>
                    <p className="text-sm font-medium text-moon">{selectedRecipient.minecraft_nickname ?? selectedRecipient.full_name ?? selectedRecipient.first_name ?? "Без имени"}</p>
                    <p className="text-xs text-moon-dim">{selectedRecipient.telegram_username ? "@" + selectedRecipient.telegram_username : "username не указан"} · ID {selectedRecipient.telegram_id}</p>
                  </div>
                  <button type="button" onClick={() => setSelectedRecipient(null)} className="text-xs text-moon-dim hover:text-moon">Изменить</button>
                </div>
              )}

              <textarea
                value={initialMessage}
                onChange={(e) => setInitialMessage(e.target.value)}
                rows={4}
                maxLength={4000}
                placeholder="Первое сообщение игроку…"
                className="w-full resize-y rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse"
              />
              <div className="flex justify-end">
                <button
                  type="button"
                  onClick={() => void startConversation()}
                  disabled={busy || !selectedRecipient || !initialMessage.trim()}
                  className="rounded-lg bg-ember/15 px-4 py-2.5 text-sm text-ember hover:bg-ember/25 disabled:opacity-40"
                >
                  {busy ? "Отправляю…" : "Создать тикет и отправить"}
                </button>
              </div>
            </div>
          </Card>
        )}

        <Card className="overflow-hidden">
          <div className="border-b border-border p-3">
            <Tabs
              tabs={FILTERS as unknown as { key: typeof filter; label: string }[]}
              active={filter}
              onChange={(value) => { setFilter(value as typeof filter); setPage(1); }}
            />
          </div>
          <div className="divide-y divide-border">
            {loading ? (
              <p className="p-8 text-center text-sm text-moon-dim">Загрузка…</p>
            ) : visible.length === 0 ? (
              <p className="p-8 text-center text-sm text-moon-dim">Обращений нет.</p>
            ) : visible.map((ticket) => (
              <button
                key={ticket.id}
                type="button"
                onClick={() => void openTicket(ticket.ticket_no)}
                className="flex w-full items-center gap-3 p-4 text-left hover:bg-panel-raised/50"
              >
                <Avatar name={person(ticket)} size="md" />
                <span className="min-w-0 flex-1">
                  <span className="flex flex-wrap items-center gap-2">
                    <span className="font-mono text-sm text-moon">#{ticket.ticket_no}</span>
                    <Badge tone={statusTone(ticket.status)}>{SUPPORT_TICKET_STATUS_LABELS[ticket.status] ?? ticket.status}</Badge>
                    <span className="text-xs text-moon-dim">{ticket.message_count} сообщений</span>
                  </span>
                  <span className="mt-1 block truncate text-sm text-moon">{person(ticket)}</span>
                  <span className="mt-0.5 block truncate text-xs text-moon-dim">
                    {ticket.minecraft_nickname ? ticket.minecraft_nickname + " · " : ""}
                    {ticket.telegram_username ? "@" + ticket.telegram_username : "Telegram username не указан"}
                    {" · "}обновлён {formatDateTime(ticket.updated_at)}
                  </span>
                </span>
                <span className="hidden text-right text-xs text-moon-dim sm:block">
                  <span className="block">создан {formatDateTime(ticket.created_at)}</span>
                  <span className="mt-1 block">ответов: {Math.max(0, ticket.message_count - 1)}</span>
                </span>
              </button>
            ))}
          </div>
          {totalPages > 1 && <div className="border-t border-border p-3"><SimplePagination page={currentPage} totalPages={totalPages} onChange={setPage} /></div>}
        </Card>
      </div>

      <Modal open={!!detail} onClose={() => setDetail(null)}>
        {detail && (
          <div className="space-y-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="font-mono text-xs text-curse">Тикет #{detail.ticket.ticket_no}</p>
                <h2 className="mt-1 font-display text-2xl text-moon">{person(detail.ticket)}</h2>
                <p className="mt-1 text-sm text-moon-dim">
                  {detail.ticket.minecraft_nickname ?? "Без Minecraft-ника"}
                  {" · "}
                  {detail.ticket.telegram_username ? "@" + detail.ticket.telegram_username : "Telegram username не указан"}
                </p>
              </div>
              <Badge tone={statusTone(detail.ticket.status)}>{SUPPORT_TICKET_STATUS_LABELS[detail.ticket.status] ?? detail.ticket.status}</Badge>
            </div>

            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <InfoItem label="Telegram ID" value={String(detail.ticket.telegram_id)} />
              <InfoItem label="Имя" value={detail.ticket.full_name ?? "—"} />
              <InfoItem label="Minecraft" value={detail.ticket.minecraft_nickname ?? "—"} />
            </div>

            <div className="max-h-[460px] space-y-3 overflow-y-auto rounded-xl border border-border bg-panel-raised/30 p-3">
              {detail.messages.map((item) => (
                <div key={item.id} className={"rounded-xl border p-3 " + (item.author_kind === "STAFF" ? "ml-8 border-curse/20 bg-curse/10" : "mr-8 border-border bg-panel")}>
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-xs font-medium text-moon">
                      {item.author_kind === "STAFF" ? "PRISMA · " : ""}{item.author_name}
                    </span>
                    <span className="text-[11px] text-moon-dim">{formatDateTime(item.created_at)}</span>
                  </div>
                  <p className="mt-2 whitespace-pre-wrap break-words text-sm text-moon">{item.message}</p>
                  {item.author_kind === "STAFF" && <p className="mt-2 text-[11px] text-moon-dim">Доставка: {item.delivery_status === "pending" ? "ожидает отправки" : item.delivery_status === "sent" ? "отправлено" : item.delivery_status === "failed" ? "ошибка" : item.delivery_status}</p>}
                </div>
              ))}
              {!detail.messages.length && <p className="p-6 text-center text-sm text-moon-dim">История сообщений пуста.</p>}
            </div>

            <div className="space-y-2">
              <textarea
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                rows={5}
                maxLength={4000}
                placeholder="Напишите ответ пользователю…"
                className="w-full resize-y rounded-xl border border-border bg-panel-raised px-3 py-3 text-sm text-moon outline-none focus:border-curse"
              />
              <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <label className="flex items-center gap-2 text-xs text-moon-dim">
                  <input type="checkbox" checked={closeAfterReply} onChange={(e) => setCloseAfterReply(e.target.checked)} />
                  После ответа закрыть тикет
                </label>
                <div className="flex flex-wrap gap-2">
                  {detail.ticket.status === "OPEN" && <button disabled={busy} onClick={() => void setStatus("IN_REVIEW")} className="rounded-lg border border-border px-3 py-2 text-xs text-moon-dim hover:text-moon">В работу</button>}
                  {(detail.ticket.status === "RESOLVED" || detail.ticket.status === "CLOSED") && <button disabled={busy} onClick={() => void setStatus("OPEN")} className="rounded-lg border border-border px-3 py-2 text-xs text-moon-dim hover:text-moon">Открыть снова</button>}
                  <button disabled={busy || !message.trim()} onClick={() => void reply()} className="rounded-lg bg-ember/15 px-4 py-2 text-sm text-ember hover:bg-ember/25 disabled:opacity-40">
                    {busy ? "Отправляю…" : closeAfterReply ? "Ответить и закрыть" : "Ответить"}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </Modal>
    </>
  );
}

