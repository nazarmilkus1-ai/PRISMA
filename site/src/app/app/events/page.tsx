import Link from "next/link";
import { EVENT_STATUS_LABELS } from "@prisma-eco/contracts";
import { getParticipantCalendar } from "@/lib/data";
import { Card } from "@/components/Card";
import { EmptyState, SectionTitle } from "@/components/SitePrimitives";

export const metadata = { title: "События" };

export default async function ParticipantEventsPage() {
  const events = await getParticipantCalendar();

  const sorted = [...events].sort((a: any, b: any) => {
    const aTime = a.starts_at ? new Date(a.starts_at).getTime() : Number.MAX_SAFE_INTEGER;
    const bTime = b.starts_at ? new Date(b.starts_at).getTime() : Number.MAX_SAFE_INTEGER;
    return aTime - bTime;
  });

  return (
    <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6">
      <SectionTitle
        eyebrow="PRISMA EVENTS"
        title="События"
        description="Полный список игровых событий PRISMA. Открывайте событие, смотрите условия и управляйте своей регистрацией."
      />

      {!sorted.length ? (
        <Card className="mt-8">
          <EmptyState title="Событий пока нет" body="Когда администрация опубликует первое событие, оно появится здесь." />
        </Card>
      ) : (
        <div className="mt-8 grid gap-4 lg:grid-cols-2">
          {sorted.map((event: any) => (
            <Card key={event.id} className="p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">
                    {EVENT_STATUS_LABELS[event.status] ?? event.status}
                  </p>
                  <h2 className="mt-2 text-lg font-semibold">{event.title}</h2>
                </div>
                {event.registered ? (
                  <span className="rounded-full border border-primary/30 bg-primary/5 px-3 py-1 text-xs font-semibold text-primary">
                    Вы зарегистрированы
                  </span>
                ) : null}
              </div>

              <p className="mt-3 line-clamp-3 text-sm leading-6 text-muted-foreground">
                {event.description || "Описание события пока не добавлено."}
              </p>

              <div className="mt-4 grid gap-2 text-xs text-muted-foreground sm:grid-cols-2">
                <div>
                  <span className="block">Начало</span>
                  <span className="mt-1 block font-medium text-foreground">
                    {event.starts_at ? new Date(event.starts_at).toLocaleString("ru-RU") : "Дата уточняется"}
                  </span>
                </div>
                <div>
                  <span className="block">Участники</span>
                  <span className="mt-1 block font-medium text-foreground">
                    {typeof event.participant_count === "number"
                      ? event.participant_count + (event.max_participants ? " / " + event.max_participants : "")
                      : "—"}
                  </span>
                </div>
              </div>

              {event.my_result ? (
                <p className="mt-4 rounded-xl border border-primary/20 bg-primary/5 px-3 py-2.5 text-xs text-primary">
                  Ваш результат: {event.my_result.placement ? "#" + event.my_result.placement : "без места"}
                  {event.my_result.score != null ? " · " + event.my_result.score + " очк." : ""}
                </p>
              ) : null}

              <Link
                href={"/events/" + event.slug}
                className="prisma-glass-control prisma-glass-hover mt-4 inline-flex rounded-xl border px-4 py-2.5 text-sm font-semibold"
              >
                Открыть событие →
              </Link>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
