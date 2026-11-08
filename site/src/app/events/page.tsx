import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Badge, Card, CardContent, CardDescription, CardHeader, CardTitle, EmptyState, Icon } from "@prisma-eco/ui";
import { getEvents } from "@/lib/data";
import { EVENT_STATUS_LABELS } from "@prisma-eco/contracts";

export const metadata = { title: "События" };

function statusVariant(status: string) {
  if (status === "live") return "success" as const;
  if (status === "finished") return "secondary" as const;
  return "warning" as const;
}

export default async function EventsPage({searchParams}:{searchParams:Promise<{error?:string;updated?:string}>}) {
  await requireModule("events");
  const [events,sp] = await Promise.all([getEvents(100),searchParams]);

  return (
    <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
      {sp.error ? (
        <Card className="mt-5 border-destructive/30 bg-destructive/5">
          <CardContent className="py-4 text-sm text-destructive">{sp.error === "forbidden" ? "Регистрация доступна только одобренным участникам с whitelist." : sp.error === "invalid" ? "Некорректные параметры регистрации." : sp.error}</CardContent>
        </Card>
      ) : null}
      {sp.updated ? (
        <Card className="mt-5 border-primary/30 bg-primary/5">
          <CardContent className="py-4 text-sm">Регистрация обновлена.</CardContent>
        </Card>
      ) : null}

      <header>
        <p className="text-xs font-medium uppercase tracking-[0.16em] text-muted-foreground">PRISMA EVENTS</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight">События</h1>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">
          Игровые события, встречи и активности сообщества PRISMA.
        </p>
      </header>

      {!events.length ? (
        <Card className="mt-8">
          <EmptyState
            icon="calendar"
            title="Событий пока нет"
            description="Опубликованные события появятся здесь, когда администрация их создаст."
          />
        </Card>
      ) : (
        <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {events.map((event: any) => (
            <Link key={event.id} href={"/events/" + event.slug}>
              <Card className="h-full transition-colors prisma-glass-hover">
                <CardHeader>
                  <div className="flex items-center justify-between gap-3">
                    <span className="prisma-glass-surface flex size-8 items-center justify-center rounded-md border">
                      <Icon name="calendar" size={15} />
                    </span>
                    <Badge variant={statusVariant(event.status)}>{EVENT_STATUS_LABELS[event.status] ?? event.status}</Badge>
                  </div>
                  <CardTitle className="text-base">{event.title}</CardTitle>
                  <CardDescription className="line-clamp-3 leading-6">
                    {event.description}
                  </CardDescription>
                </CardHeader>
                <CardContent className="grid gap-2 text-xs text-muted-foreground">
                  <div className="flex justify-between gap-4">
                    <span>Начало</span>
                    <span>{event.starts_at ? new Date(event.starts_at).toLocaleString("ru-RU") : "Дата уточняется"}</span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span>Участники</span>
                    <span>{event.max_participants ?? "Без лимита"}</span>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
