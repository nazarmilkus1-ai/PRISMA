import Link from "next/link";
import { formatMinutes } from "@prisma-eco/shared";
import { requireUser } from "@/lib/auth";
import { getPublicModuleAvailability } from "@/lib/modules";
import { getDashboardData, getParticipantCalendar, getPublicServerStatus, getPublicNews } from "@/lib/data";
import {
  Badge,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  EmptyState,
  Metric,
  PageHeader,
} from "@prisma-eco/ui";

export const metadata = { title: "Главная" };

function applicationVariant(status: string) {
  if (status === "ACCEPTED") return "success" as const;
  if (status === "REJECTED") return "destructive" as const;
  return "warning" as const;
}

function applicationLabel(status: string) {
  if (status === "ACCEPTED") return "Принята";
  if (status === "REJECTED") return "Отклонена";
  return "На рассмотрении";
}

export default async function AppHomePage() {
  const user = await requireUser();
  const [dashboard, server, news, eventsRaw, enabledModules] = await Promise.all([
    getDashboardData(),
    getPublicServerStatus(),
    getPublicNews(4),
    getParticipantCalendar(),
    getPublicModuleAvailability(),
  ]);
  const now = Date.now();
  const events = eventsRaw
    .filter((event: any) => !event.starts_at || new Date(event.starts_at).getTime() >= now)
    .sort((a: any, b: any) => new Date(a.starts_at || 0).getTime() - new Date(b.starts_at || 0).getTime())
    .slice(0, 3);
  const current = dashboard.user || user;
  const canUseMarket = current.status === "ACCEPTED" && !current.is_banned && current.is_whitelisted === true;
  const displayName = current.minecraft_nickname || current.first_name || "Игрок";

  return (
    <div className="space-y-6 prisma-page-enter">
      <PageHeader
        eyebrow="Личный кабинет"
        title={"Добро пожаловать, " + displayName}
        description="Здесь собраны ваши данные, активность и действия, которые доступны прямо сейчас."
        actions={
          enabledModules.minecraft ? (
            <Badge variant={server.online ? "success" : "secondary"}>
              {server.online ? "Сервер онлайн" : "Сервер офлайн"}
            </Badge>
          ) : null
        }
      />

      <div className="prisma-section-stagger grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {enabledModules.minecraft ? (
          <Metric
            label="Сервер"
            value={server.players + " / " + (server.maxPlayers || "—")}
            hint={server.version || "Paper"}
            icon="server"
          />
        ) : null}
        {enabledModules.players ? (
          <>
            <Metric label="Рейтинг" value={current.rating ?? 0} hint="текущий рейтинг" icon="bar-chart" />
            <Metric label="Уровень" value={current.level ?? 1} hint={(current.xp ?? 0) + " XP"} icon="activity" />
          </>
        ) : null}
        {enabledModules.clans ? (
          <Metric
            label="Клан"
            value={dashboard.clan?.tag ? "[" + dashboard.clan.tag + "]" : "Нет"}
            hint={dashboard.clan?.name || "Вы пока не состоите в клане"}
            icon="clans"
          />
        ) : null}
      </div>

      {(enabledModules.players || enabledModules.clans || (enabledModules.market && canUseMarket) || enabledModules.battles) ? (
      <Card className="prisma-section-stagger-2">
        <CardHeader>
          <CardTitle>Быстрые действия</CardTitle>
          <CardDescription>Основные функции кабинета в один переход.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          {enabledModules.players ? <Link href="/app/profile" className="prisma-glass-surface prisma-glass-hover rounded-xl border p-4 transition-colors"><p className="text-sm font-semibold">Профиль</p><p className="mt-1 text-xs text-muted-foreground">Личные данные и социальный статус</p></Link> : null}
          {enabledModules.clans ? <Link href="/app/clan" className="prisma-glass-surface prisma-glass-hover rounded-xl border p-4 transition-colors"><p className="text-sm font-semibold">{dashboard.clan ? "Мой клан" : "Кланы"}</p><p className="mt-1 text-xs text-muted-foreground">{dashboard.clan ? "Состав, войны и управление" : "Найти и выбрать клан"}</p></Link> : null}
          {enabledModules.market && canUseMarket ? <Link href="/app/market" className="prisma-glass-surface prisma-glass-hover rounded-xl border p-4 transition-colors"><p className="text-sm font-semibold">Рынок</p><p className="mt-1 text-xs text-muted-foreground">Объявления участников</p></Link> : null}
          {enabledModules.battles ? <Link href="/app/battles" className="prisma-glass-surface prisma-glass-hover rounded-xl border p-4 transition-colors"><p className="text-sm font-semibold">Player Battle</p><p className="mt-1 text-xs text-muted-foreground">Сравнить игрока по статистике</p></Link> : null}
        </CardContent>
      </Card>
      ) : null}

      <div className="grid gap-4 xl:grid-cols-[1.15fr_.85fr]">
        {enabledModules.applications ? (
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <div>
              <CardTitle>Моя заявка</CardTitle>
              <CardDescription>Актуальный статус вступления.</CardDescription>
            </div>
            <Link href="/app/application" className="text-xs text-muted-foreground hover:text-foreground">
              Открыть →
            </Link>
          </CardHeader>

          <CardContent>
            {dashboard.application ? (
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-lg font-semibold">#{dashboard.application.application_no}</p>
                  <p className="mt-1 text-sm text-muted-foreground">{dashboard.application.nickname}</p>
                </div>
                <Badge variant={applicationVariant(dashboard.application.status)}>
                  {applicationLabel(dashboard.application.status)}
                </Badge>
              </div>
            ) : (
              <div>
                <p className="text-sm font-medium">Заявки ещё нет</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  Заполните анкету, чтобы начать вступление в PRISMA.
                </p>
                <Link
                  href="/app/application"
                  className="prisma-glass-primary prisma-glass-shimmer mt-4 inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium text-primary"
                >
                  Подать заявку
                </Link>
              </div>
            )}
          </CardContent>
        </Card>
        ) : null}

        {enabledModules.events ? (
        <Card>
          <CardHeader>
            <CardTitle>Следующие события</CardTitle>
            <CardDescription>Ближайшие активности сообщества.</CardDescription>
          </CardHeader>
          <div className="divide-y">
            {events.slice(0, 3).map((event: any) => (
              <Link
                key={event.id}
                href={"/events/" + event.slug}
                className="prisma-glass-hover block px-5 py-4 transition-colors"
              >
                <div className="flex items-center gap-2">
                  <p className="truncate text-sm font-medium">{event.title}</p>
                  {event.registered ? <span className="prisma-glass-badge shrink-0 rounded-full border px-2 py-0.5 text-[10px] font-semibold text-primary">Вы зарегистрированы</span> : null}
                </div>
                <p className="mt-1 text-xs text-muted-foreground">
                  {event.starts_at ? new Date(event.starts_at).toLocaleString("ru-RU") : "Дата уточняется"}
                </p>
              </Link>
            ))}
            {!events.length ? (
              <div className="px-5 py-7 sm:px-6">
                <div className="prisma-glass-surface rounded-xl border border-dashed p-5 text-center">
                  <div className="prisma-glass-surface mx-auto flex h-10 w-10 items-center justify-center rounded-full border text-primary">
                    ✦
                  </div>
                  <p className="mt-3 text-sm font-semibold">Сейчас событий нет</p>
                  <p className="mx-auto mt-1 max-w-sm text-xs leading-5 text-muted-foreground">
                    Как только появится новый ивент, он автоматически появится здесь.
                  </p>
                  <Link
                    href="/app/events"
                    className="prisma-glass-hover mt-4 inline-flex h-8 items-center rounded-md border px-3 text-xs font-medium"
                  >
                    Открыть события →
                  </Link>
                </div>
              </div>
            ) : null}
          </div>
        </Card>
        ) : null}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        {enabledModules["public-content"] ? (
        <Card className="overflow-hidden">
          <CardHeader className="flex-row items-center justify-between">
            <div>
              <CardTitle>Последние новости</CardTitle>
              <CardDescription>Важные публикации PRISMA.</CardDescription>
            </div>
            <Link href="/app/news" className="text-xs text-muted-foreground hover:text-foreground">Все →</Link>
          </CardHeader>
          <div className="divide-y">
            {news.map((item: any) => (
              <Link key={item.id} href={"/app/news/" + item.id} className="prisma-glass-hover block px-5 py-4">
                <p className="text-sm font-medium">{item.title}</p>
                <p className="mt-1 line-clamp-2 text-xs leading-5 text-muted-foreground">{item.body}</p>
              </Link>
            ))}
            {!news.length ? (
              <div className="px-5 py-7 sm:px-6">
                <div className="prisma-glass-surface rounded-xl border border-dashed p-5 text-center">
                  <div className="prisma-glass-surface mx-auto flex h-10 w-10 items-center justify-center rounded-full border text-primary">
                    ◇
                  </div>
                  <p className="mt-3 text-sm font-semibold">Публикаций пока нет</p>
                  <p className="mx-auto mt-1 max-w-sm text-xs leading-5 text-muted-foreground">
                    Новые новости PRISMA появятся здесь автоматически после публикации.
                  </p>
                  <Link
                    href="/app/news"
                    className="prisma-glass-hover mt-4 inline-flex h-8 items-center rounded-md border px-3 text-xs font-medium"
                  >
                    Открыть новости →
                  </Link>
                </div>
              </div>
            ) : null}
          </div>
        </Card>
        ) : null}

        {enabledModules.notifications ? (
        <Card>
          <CardHeader>
            <CardTitle>Уведомления</CardTitle>
            <CardDescription>Последние изменения, которые относятся к вам.</CardDescription>
          </CardHeader>
          {dashboard.notifications.length ? (
            <div className="divide-y">
              {dashboard.notifications.slice(0, 4).map((notification: any) => {
                const data = notification?.data && typeof notification.data === "object" ? notification.data : {};
                const kind = String(notification?.kind || "").toUpperCase();
                const href = data.clan_id && ["CLAN","CLAN_NEWS"].includes(kind)
                  ? "/app/clans/" + encodeURIComponent(String(data.clan_id))
                  : data.slug
                    ? "/events/" + encodeURIComponent(String(data.slug))
                    : data.event_slug
                      ? "/events/" + encodeURIComponent(String(data.event_slug))
                      : data.report_id && kind === "REPORT"
                        ? "/app/reports/" + encodeURIComponent(String(data.report_id))
                        : data.battle_id && kind === "BATTLE"
                          ? "/app/battles"
                          : data.inquiry_id && kind === "MARKET"
                            ? "/app/market"
                            : data.action && kind === "SOCIAL"
                              ? "/app/profile"
                              : null;
                const body = <><p className="text-sm font-medium">{notification.title}</p><p className="mt-1 line-clamp-2 text-xs leading-5 text-muted-foreground">{notification.body}</p></>;
                return href ? <Link key={notification.id} href={href} className="prisma-glass-hover block px-5 py-4 transition-colors">{body}</Link> : <div key={notification.id} className="px-5 py-4">{body}</div>;
              })}
            </div>
          ) : (
            <EmptyState title="Уведомлений нет" description="Здесь появятся важные события вашего аккаунта." />
          )}
        </Card>
        ) : null}
      </div>

      {enabledModules.minecraft && dashboard.stats ? (
        <Card>
          <CardHeader>
            <CardTitle>Моя статистика</CardTitle>
            <CardDescription>Последние доступные показатели Minecraft.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label="Убийства" value={dashboard.stats.kills ?? 0} />
            <Stat label="Смерти" value={dashboard.stats.deaths ?? 0} />
            <Stat label="Время игры" value={formatMinutes(dashboard.stats.playtime_minutes ?? 0)} />
            <Stat label="Сломано блоков" value={dashboard.stats.blocks_broken ?? 0} />
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="prisma-glass-surface rounded-md border p-4">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 text-lg font-semibold">{value}</p>
    </div>
  );
}

