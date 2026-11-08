"use client";

import { formatDateTime } from "@prisma-eco/shared";

import { EVENT_STATUS_LABELS } from "@prisma-eco/contracts";

import { FormEvent, useState } from "react";
import { Card, Badge, InfoItem } from "@/components/ui";

type Participant = {
  event_id: string;
  user_id: string;
  score: number;
  placement: number | null;
  registered_at: string;
  nickname: string;
};

type EventItem = {
  id: string;
  slug: string;
  title: string;
  description: string;
  status: "draft" | "scheduled" | "live" | "finished" | "cancelled";
  starts_at: string | null;
  ends_at: string | null;
  registration_deadline: string | null;
  max_participants: number | null;
  reward_config: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  participants: Participant[];
};

const STATUS_TONE: Record<string, "success" | "danger" | "warn" | "neutral"> = {
  draft: "neutral",
  scheduled: "warn",
  live: "success",
  finished: "neutral",
  cancelled: "danger",
};

function toInputDate(value: string | null) {
  if (!value) return "";
  const date = new Date(value);
  const offset = date.getTimezoneOffset();
  return new Date(date.getTime() - offset * 60000).toISOString().slice(0, 16);
}

export function EventsPanel({ initialEvents }: { initialEvents: EventItem[] }) {
  const [events, setEvents] = useState(initialEvents);
  const [editing, setEditing] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function createEvent(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy("create");
    setError(null);
    setMessage(null);

    const form = new FormData(event.currentTarget);
    const payload = {
      slug: String(form.get("slug") ?? ""),
      title: String(form.get("title") ?? ""),
      description: String(form.get("description") ?? ""),
      status: String(form.get("status") ?? "draft"),
      starts_at: form.get("starts_at") ? new Date(String(form.get("starts_at"))).toISOString() : null,
      ends_at: form.get("ends_at") ? new Date(String(form.get("ends_at"))).toISOString() : null,
      registration_deadline: form.get("registration_deadline")
        ? new Date(String(form.get("registration_deadline"))).toISOString()
        : null,
      max_participants: form.get("max_participants") ? Number(form.get("max_participants")) : null,
    };

    try {
      const response = await fetch("/admin/api/events", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(result.error ?? "Не удалось создать событие.");
        return;
      }
      window.location.reload();
    } catch {
      setError("Не удалось связаться с PRISMA.");
    } finally {
      setBusy(null);
    }
  }

  async function updateEvent(item: EventItem, event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(item.id);
    setError(null);
    setMessage(null);

    const form = new FormData(event.currentTarget);
    const payload = {
      event_id: item.id,
      slug: String(form.get("slug") ?? ""),
      title: String(form.get("title") ?? ""),
      description: String(form.get("description") ?? ""),
      status: String(form.get("status") ?? item.status),
      starts_at: form.get("starts_at") ? new Date(String(form.get("starts_at"))).toISOString() : null,
      ends_at: form.get("ends_at") ? new Date(String(form.get("ends_at"))).toISOString() : null,
      registration_deadline: form.get("registration_deadline")
        ? new Date(String(form.get("registration_deadline"))).toISOString()
        : null,
      max_participants: form.get("max_participants") ? Number(form.get("max_participants")) : null,
    };

    try {
      const response = await fetch("/admin/api/events", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(result.error ?? "Не удалось сохранить событие.");
        return;
      }
      const nextStatus = payload.status as EventItem["status"];
      setEvents((current) =>
        current.map((entry) =>
          entry.id === item.id
            ? {
                ...entry,
                slug: payload.slug,
                title: payload.title,
                description: payload.description,
                status: nextStatus,
                starts_at: payload.starts_at,
                ends_at: payload.ends_at,
                registration_deadline: payload.registration_deadline,
                max_participants: payload.max_participants,
                updated_at: new Date().toISOString(),
              }
            : entry,
        ),
      );
      setEditing(null);
      setMessage("Событие сохранено.");
    } catch {
      setError("Не удалось связаться с PRISMA.");
    } finally {
      setBusy(null);
    }
  }

  async function cancelEvent(id: string) {
    if (!window.confirm("Отменить это событие?")) return;
    setBusy(id);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch("/admin/api/events", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ event_id: id }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(result.error ?? "Не удалось отменить событие.");
        return;
      }
      setEvents((current) =>
        current.map((entry) => (entry.id === id ? { ...entry, status: "cancelled" } : entry)),
      );
      setMessage("Событие отменено.");
    } catch {
      setError("Не удалось связаться с PRISMA.");
    } finally {
      setBusy(null);
    }
  }

  async function saveResult(eventId: string, participant: Participant, event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(participant.user_id);
    setError(null);
    setMessage(null);
    const form = new FormData(event.currentTarget);
    const score = Number(form.get("score") ?? 0);
    const placementRaw = String(form.get("placement") ?? "").trim();

    try {
      const response = await fetch("/admin/api/events", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          event_id: eventId,
          user_id: participant.user_id,
          score,
          placement: placementRaw ? Number(placementRaw) : null,
        }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(result.error ?? "Не удалось сохранить результат.");
        return;
      }
      setEvents((current) =>
        current.map((entry) =>
          entry.id !== eventId
            ? entry
            : {
                ...entry,
                participants: entry.participants.map((item) =>
                  item.user_id === participant.user_id
                    ? { ...item, score, placement: placementRaw ? Number(placementRaw) : null }
                    : item,
                ),
              },
        ),
      );
      setMessage("Результат сохранён.");
    } catch {
      setError("Не удалось связаться с PRISMA.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-5">
      {error ? <div className="rounded-md border border-danger/30 bg-danger/10 px-4 py-3 text-sm text-danger">{error}</div> : null}
      {message ? <div className="rounded-md border border-success/30 bg-success/10 px-4 py-3 text-sm text-success">{message}</div> : null}

      <Card className="p-5">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-moon-dim">Новое событие</p>
          <h2 className="mt-1 text-base font-medium text-moon">Создать мероприятие</h2>
        </div>
        <form onSubmit={createEvent} className="mt-4 grid gap-3 md:grid-cols-2">
          <input name="title" required maxLength={160} placeholder="Название" className="h-9 rounded-md border bg-background px-3 text-sm md:col-span-2" />
          <input name="slug" required maxLength={120} pattern="[a-z0-9][a-z0-9._-]*" placeholder="slug" className="h-9 rounded-md border bg-background px-3 font-mono text-sm" />
          <select name="status" defaultValue="draft" className="h-9 rounded-md border bg-background px-3 text-sm">
            <option value="draft">Черновик</option>
            <option value="scheduled">Запланировано</option>
            <option value="live">Идёт</option>
          </select>
          <textarea name="description" maxLength={5000} placeholder="Описание" className="min-h-24 rounded-md border bg-background px-3 py-2 text-sm md:col-span-2" />
          <label className="grid gap-1 text-xs text-moon-dim">Начало<input name="starts_at" type="datetime-local" className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
          <label className="grid gap-1 text-xs text-moon-dim">Окончание<input name="ends_at" type="datetime-local" className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
          <label className="grid gap-1 text-xs text-moon-dim">Дедлайн регистрации<input name="registration_deadline" type="datetime-local" className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
          <label className="grid gap-1 text-xs text-moon-dim">Максимум участников<input name="max_participants" type="number" min={1} className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
          <button type="submit" disabled={busy === "create"} className="h-9 rounded-md bg-primary px-3 text-sm font-medium text-primary-foreground md:col-span-2">
            {busy === "create" ? "Создаю…" : "Создать событие"}
          </button>
        </form>
      </Card>

      <div className="space-y-3">
        {events.map((item) => (
          <Card key={item.id} className="overflow-hidden">
            <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border p-5">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-base font-medium text-moon">{item.title}</h2>
                  <Badge tone={STATUS_TONE[item.status] ?? "neutral"}>{EVENT_STATUS_LABELS[item.status] ?? item.status}</Badge>
                </div>
                <p className="mt-1 font-mono text-xs text-moon-dim">/{item.slug}</p>
                <p className="mt-2 max-w-3xl text-sm leading-6 text-moon-dim">{item.description || "Без описания."}</p>
              </div>
              <div className="flex gap-2">
                <button type="button" onClick={() => setEditing(editing === item.id ? null : item.id)} className="h-8 rounded-md border px-3 text-xs font-medium hover:bg-accent">
                  {editing === item.id ? "Закрыть" : "Редактировать"}
                </button>
                {item.status !== "cancelled" && item.status !== "finished" ? (
                  <button type="button" onClick={() => void cancelEvent(item.id)} disabled={busy === item.id} className="h-8 rounded-md border border-danger/40 px-3 text-xs font-medium text-danger hover:bg-danger/10">
                    Отменить
                  </button>
                ) : null}
              </div>
            </div>

            <div className="grid gap-3 border-b border-border p-5 sm:grid-cols-4">
              <InfoItem label="Начало" value={item.starts_at ? formatDateTime(item.starts_at) : "Не указано"} />
              <InfoItem label="Окончание" value={item.ends_at ? formatDateTime(item.ends_at) : "Не указано"} />
              <InfoItem label="Регистрация" value={item.registration_deadline ? formatDateTime(item.registration_deadline) : "Без дедлайна"} />
              <InfoItem label="Участники" value={item.max_participants ? item.participants.length + " / " + item.max_participants : String(item.participants.length)} />
            </div>

            {editing === item.id ? (
              <form onSubmit={(event) => void updateEvent(item, event)} className="grid gap-3 border-b border-border bg-panel-raised/30 p-5 md:grid-cols-2">
                <input name="title" required defaultValue={item.title} maxLength={160} className="h-9 rounded-md border bg-background px-3 text-sm md:col-span-2" />
                <input name="slug" required defaultValue={item.slug} maxLength={120} pattern="[a-z0-9][a-z0-9._-]*" className="h-9 rounded-md border bg-background px-3 font-mono text-sm" />
                <select name="status" defaultValue={item.status} className="h-9 rounded-md border bg-background px-3 text-sm">
                  {Object.entries(EVENT_STATUS_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
                <textarea name="description" defaultValue={item.description} maxLength={5000} className="min-h-24 rounded-md border bg-background px-3 py-2 text-sm md:col-span-2" />
                <label className="grid gap-1 text-xs text-moon-dim">Начало<input name="starts_at" type="datetime-local" defaultValue={toInputDate(item.starts_at)} className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
                <label className="grid gap-1 text-xs text-moon-dim">Окончание<input name="ends_at" type="datetime-local" defaultValue={toInputDate(item.ends_at)} className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
                <label className="grid gap-1 text-xs text-moon-dim">Дедлайн регистрации<input name="registration_deadline" type="datetime-local" defaultValue={toInputDate(item.registration_deadline)} className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
                <label className="grid gap-1 text-xs text-moon-dim">Максимум участников<input name="max_participants" type="number" min={1} defaultValue={item.max_participants ?? ""} className="h-9 rounded-md border bg-background px-3 text-sm text-moon" /></label>
                <button type="submit" disabled={busy === item.id} className="h-9 rounded-md bg-primary px-3 text-sm font-medium text-primary-foreground md:col-span-2">
                  {busy === item.id ? "Сохраняю…" : "Сохранить изменения"}
                </button>
              </form>
            ) : null}

            <div className="p-5">
              <div className="flex items-center justify-between gap-3">
                <h3 className="text-sm font-medium text-moon">Результаты</h3>
                <span className="text-xs text-moon-dim">{item.participants.length} участников</span>
              </div>
              {item.participants.length ? (
                <div className="mt-3 space-y-2">
                  {item.participants.map((participant) => (
                    <form key={participant.user_id} onSubmit={(event) => void saveResult(item.id, participant, event)} className="grid gap-2 rounded-md border border-border bg-panel-raised/20 p-3 sm:grid-cols-[1fr_120px_120px_auto] sm:items-end">
                      <div>
                        <p className="text-sm text-moon">{participant.nickname}</p>
                        <p className="mt-1 text-xs text-moon-dim">{formatDateTime(participant.registered_at)}</p>
                      </div>
                      <label className="grid gap-1 text-[11px] text-moon-dim">Результат<input name="score" type="number" min={0} defaultValue={participant.score} className="h-8 rounded-md border bg-background px-2 text-sm text-moon" /></label>
                      <label className="grid gap-1 text-[11px] text-moon-dim">Место<input name="placement" type="number" min={1} defaultValue={participant.placement ?? ""} className="h-8 rounded-md border bg-background px-2 text-sm text-moon" /></label>
                      <button type="submit" disabled={busy === participant.user_id} className="h-8 rounded-md border px-3 text-xs font-medium hover:bg-accent">
                        {busy === participant.user_id ? "Сохраняю…" : "Сохранить"}
                      </button>
                    </form>
                  ))}
                </div>
              ) : (
                <p className="mt-3 text-sm text-moon-dim">Зарегистрированных участников пока нет.</p>
              )}
            </div>
          </Card>
        ))}
        {!events.length ? <Card className="p-10 text-center text-sm text-moon-dim">Событий пока нет.</Card> : null}
      </div>
    </div>
  );
}

