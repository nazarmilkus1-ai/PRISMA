"use client";

import { EVENT_STATUS_LABELS } from "@prisma-eco/contracts";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";

type EventItem = {
  id: string;
  slug: string;
  title: string;
  description?: string | null;
  status?: string | null;
  starts_at?: string | null;
  ends_at?: string | null;
  registration_deadline?: string | null;
  max_participants?: number | null;
  participant_count?: number | null;
  registered?: boolean;
  my_result?: {
    score?: number | null;
    placement?: number | null;
    registered_at?: string | null;
  } | null;
};

const DAY_MS = 86400000;

function dayKey(date: Date) {
  const value = new Date(date);
  value.setHours(0, 0, 0, 0);
  return value.toISOString().slice(0, 10);
}

function formatDay(date: Date) {
  return new Intl.DateTimeFormat("ru-RU", {
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(date);
}

function eventDate(event: EventItem) {
  return event.starts_at ? new Date(event.starts_at) : null;
}

function eventHour(event: EventItem) {
  const date = eventDate(event);
  return date ? date.getHours() + date.getMinutes() / 60 : 12;
}

function eventStatusLabel(status: EventItem["status"]) {
  if (!status) return "—";
  return EVENT_STATUS_LABELS[status as keyof typeof EVENT_STATUS_LABELS] ?? status;
}

export function CalendarTimeline({ events }: { events: EventItem[] }) {
  const now = new Date();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const selected = events.find((event) => event.id === selectedId) ?? null;
  const dayRefs = useRef<Array<HTMLElement | null>>([]);

  const days = useMemo(
    () =>
      Array.from({ length: 7 }, (_, index) => {
        const date = new Date();
        date.setHours(0, 0, 0, 0);
        date.setTime(date.getTime() + (index - 3) * DAY_MS);
        return date;
      }),
    [],
  );

  useEffect(() => {
    dayRefs.current[3]?.scrollIntoView({ block: "center", behavior: "auto" });
  }, []);

  const grouped = (day: Date) =>
    events
      .filter((event) => {
        const date = eventDate(event);
        return date ? dayKey(date) === dayKey(day) : false;
      })
      .sort((a, b) => eventHour(a) - eventHour(b));

  const todayPercent =
    ((now.getHours() + now.getMinutes() / 60 + now.getSeconds() / 3600) / 24) * 100;

  return (
    <div className="space-y-4">
      {selected ? (
        <section className="rounded-md border bg-card p-5" aria-live="polite">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="min-w-0">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Событие
              </p>
              <h2 className="mt-1 text-xl font-semibold tracking-tight">{selected.title}</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                {selected.starts_at
                  ? new Date(selected.starts_at).toLocaleString("ru-RU")
                  : "Дата уточняется"}
                {selected.ends_at
                  ? " → " + new Date(selected.ends_at).toLocaleString("ru-RU")
                  : ""}
              </p>
            </div>
            <button
              type="button"
              onClick={() => setSelectedId(null)}
              className="prisma-glass-control prisma-glass-hover inline-flex h-8 items-center rounded-md border px-3 text-xs font-medium"
            >
              Закрыть
            </button>
          </div>

          <p className="mt-4 whitespace-pre-wrap text-sm leading-6 text-muted-foreground">
            {selected.description || "Описание события пока не добавлено."}
          </p>

          <div className="mt-4 flex flex-wrap gap-2 text-xs">
            <span className="prisma-glass-surface rounded-md border px-2.5 py-1.5">
              {eventStatusLabel(selected.status)}
            </span>
            {selected.registered ? (
              <span className="rounded-md border border-primary/30 bg-primary/5 px-2.5 py-1.5 text-primary">
                Вы зарегистрированы
              </span>
            ) : null}
            {typeof selected.participant_count === "number" ? (
              <span className="prisma-glass-surface rounded-md border px-2.5 py-1.5">
                {selected.participant_count}{selected.max_participants ? " / " + selected.max_participants : ""} участников
              </span>
            ) : null}
            {selected.my_result ? (
              <span className="rounded-md border border-primary/30 bg-primary/5 px-2.5 py-1.5 text-primary">
                Результат: {selected.my_result.placement ? "#" + selected.my_result.placement : "без места"}
                {selected.my_result.score != null ? " · " + selected.my_result.score + " очк." : ""}
              </span>
            ) : null}
            {selected.registration_deadline ? (
              <span className="prisma-glass-surface rounded-md border px-2.5 py-1.5">
                Регистрация до {new Date(selected.registration_deadline).toLocaleString("ru-RU")}
              </span>
            ) : null}
            {selected.max_participants ? (
              <span className="prisma-glass-surface rounded-md border px-2.5 py-1.5">
                До {selected.max_participants} участников
              </span>
            ) : null}
          </div>

          <Link
            href={"/events/" + selected.slug}
            className="mt-4 inline-flex h-9 items-center rounded-md bg-primary px-3.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
          >
            Открыть полную страницу
          </Link>
        </section>
      ) : null}

      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold">Временная лента</h2>
          <p className="mt-1 text-xs text-muted-foreground">
            Сегодня в центре. Используйте прокрутку, чтобы посмотреть ближайшие дни.
          </p>
        </div>
        <span className="rounded-md border bg-background px-2.5 py-1 text-xs text-muted-foreground">
          {events.length} событий
        </span>
      </div>

      <div className="h-[72vh] min-h-[520px] overflow-y-auto rounded-md border bg-card p-2">
        {days.map((day, index) => {
          const isToday = index === 3;
          const dayEvents = grouped(day);

          return (
            <section
              key={day.toISOString()}
              ref={(element) => {
                dayRefs.current[index] = element;
              }}
              className={[
                "min-h-[46vh] p-4 sm:p-5",
                index > 0 ? "border-t" : "",
                isToday ? "bg-muted/20" : "",
              ].join(" ")}
            >
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p
                    className={[
                      "text-xs font-medium uppercase tracking-wide",
                      isToday ? "text-primary" : "text-muted-foreground",
                    ].join(" ")}
                  >
                    {isToday
                      ? "Сегодня"
                      : index < 3
                        ? "−" + (3 - index) + " дня"
                        : "+" + (index - 3) + " дня"}
                  </p>
                  <h3 className="mt-1 text-lg font-semibold">{formatDay(day)}</h3>
                </div>
                <span className="text-xs text-muted-foreground">
                  {dayEvents.length} событий
                </span>
              </div>

              {isToday ? (
                <div className="relative mt-5 overflow-hidden rounded-md border bg-background p-3 sm:p-4">
                  <div className="grid h-8 grid-cols-24">
                    {Array.from({ length: 24 }, (_, hour) => (
                      <span key={hour} className="relative border-l first:border-l-0">
                        <span className="absolute -left-1.5 top-0 text-[9px] text-muted-foreground">
                          {String(hour).padStart(2, "0")}
                        </span>
                      </span>
                    ))}
                  </div>
                  <div
                    className="pointer-events-none absolute inset-y-3 w-px bg-primary"
                    style={{ left: "calc(" + Math.min(99, Math.max(1, todayPercent)) + "%)" }}
                  />
                  <div className="mt-5 space-y-2">
                    {dayEvents.map((event) => (
                      <button
                        key={event.id}
                        type="button"
                        onClick={() => setSelectedId(event.id)}
                        className="flex w-full items-center gap-3 rounded-md border bg-card px-3 py-2.5 text-left transition-colors hover:bg-accent"
                      >
                        <span className="w-12 shrink-0 text-xs font-medium text-muted-foreground">
                          {eventDate(event)
                            ? new Intl.DateTimeFormat("ru-RU", {
                                hour: "2-digit",
                                minute: "2-digit",
                              }).format(eventDate(event)!)
                            : "—"}
                        </span>
                        <span className="min-w-0 flex-1 truncate text-sm font-medium">
                          {event.title}
                        </span>
                        <span className="shrink-0 text-xs text-muted-foreground">
                          {event.registered ? "Вы зарегистрированы" : eventStatusLabel(event.status)}
                        </span>
                      </button>
                    ))}
                    {!dayEvents.length ? (
                      <p className="py-6 text-center text-sm text-muted-foreground">
                        На сегодня событий нет.
                      </p>
                    ) : null}
                  </div>
                </div>
              ) : (
                <div className="mt-4 space-y-2">
                  {dayEvents.map((event) => (
                    <button
                      key={event.id}
                      type="button"
                      onClick={() => setSelectedId(event.id)}
                      className="flex w-full items-center gap-3 rounded-md border bg-background px-3 py-2.5 text-left transition-colors hover:bg-accent"
                    >
                      <span className="w-12 shrink-0 text-xs font-medium text-muted-foreground">
                        {eventDate(event)
                          ? new Intl.DateTimeFormat("ru-RU", {
                              hour: "2-digit",
                              minute: "2-digit",
                            }).format(eventDate(event)!)
                          : "—"}
                      </span>
                      <span className="min-w-0 flex-1 truncate text-sm font-medium">
                        {event.title}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        {eventStatusLabel(event.status)}
                      </span>
                    </button>
                  ))}
                  {!dayEvents.length ? (
                    <p className="py-4 text-sm text-muted-foreground">Событий нет.</p>
                  ) : null}
                </div>
              )}
            </section>
          );
        })}
      </div>
    </div>
  );
}
