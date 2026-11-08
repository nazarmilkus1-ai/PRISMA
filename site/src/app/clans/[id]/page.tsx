import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Badge, Card, CardContent, CardHeader, CardTitle, Metric, PageHeader } from "@prisma-eco/ui";
import { getClanPage } from "@/lib/data";

const roleLabel: Record<string, string> = {
  owner: "Владелец",
  co_owner: "Совладелец",
  officer: "Офицер",
  member: "Участник",
  recruit: "Рекрут",
};

const statusLabel: Record<string, string> = {
  scheduled: "Запланирована",
  active: "Активна",
  finished: "Завершена",
  cancelled: "Отменена",
};

const activityLabel: Record<string, string> = {
  CLAN_CREATED: "Клан создан",
  MEMBER_JOIN: "Участник вступил",
  MEMBER_LEAVE: "Участник вышел",
  ROLE_CHANGE: "Изменена роль",
  MEMBER_MOVED: "Участник переведён",
  OWNER_TRANSFER: "Передан владелец",
  CLAN_DISBANDED: "Клан распущен",
  INVITE_SENT: "Отправлено приглашение",
  INVITE_ACCEPTED: "Приглашение принято",
  INVITE_DECLINED: "Приглашение отклонено",
  INVITE_CANCELLED: "Приглашение отменено",
  INVITE_EXPIRED: "Приглашение истекло",
  ANNOUNCEMENT_CREATED: "Опубликовано объявление",
  ANNOUNCEMENT_DELETED: "Удалено объявление",
  VILLAGE_CREATED: "Создана территория",
  VILLAGE_DELETED: "Удалена территория",
  WAR_DECLARED: "Объявлена война",
  WAR_ACTIVE: "Война началась",
  WAR_FINISHED: "Война завершена",
  WAR_CANCELLED: "Война отменена",
  WAR_UPDATED: "Обновлена война",
};

const roleShort: Record<string, string> = {
  owner: "Владелец",
  co_owner: "Совладелец",
  officer: "Офицер",
  member: "Участник",
  recruit: "Рекрут",
};

function activityText(item: any) {
  const p = item.payload || {};
  switch (item.kind) {
    case "ROLE_CHANGE":
      return (item.nickname || "Игрок") + ": " + (roleShort[p.old_role] || p.old_role || "—") + " → " + (roleShort[p.role] || p.role || "—");
    case "INVITE_SENT":
      return (item.nickname || "Игрок") + " пригласил " + (p.invitee_nickname || "игрока");
    case "INVITE_ACCEPTED":
      return (p.inviter_nickname || "Приглашение") + " принято игроком " + (item.nickname || "Игрок");
    case "INVITE_DECLINED":
    case "INVITE_CANCELLED":
    case "INVITE_EXPIRED":
      return "Игрок: " + (item.nickname || "—");
    case "MEMBER_LEAVE":
      return p.action === "KICK"
        ? (item.nickname || p.nickname || "Игрок") + " исключён из клана"
        : "Игрок: " + (item.nickname || p.nickname || "—");
    case "OWNER_TRANSFER":
      return (p.old_owner_nickname || "Игрок") + " → " + (p.new_owner_nickname || "Игрок");
    case "CLAN_DISBANDED":
      return "Владелец: " + (p.actor_nickname || "—");
    case "ANNOUNCEMENT_CREATED":
    case "ANNOUNCEMENT_DELETED":
      return p.title || "Объявление клана";
    case "VILLAGE_CREATED":
    case "VILLAGE_DELETED":
      return p.name || "Территория клана";
    case "WAR_DECLARED":
      return "Новая война с кланом";
    case "WAR_FINISHED":
      return "Счёт: " + (p.score_a ?? 0) + " : " + (p.score_b ?? 0);
    default:
      return item.nickname || "Система PRISMA";
  }
}

export default async function ClanPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireModuleMember("clans");
  const { id } = await params;
  const data = await getClanPage(id);

  if (!data?.clan) notFound();

  const c = data.clan;
  const canJoin = !me.clan_id && String(c.type).toLowerCase() === "open";
  const memberCount = Number(c.member_count ?? data.members.length ?? 0);

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow={"Клан [" + (c.tag || "—") + "]"}
        title={c.name}
        description={c.description || "Клан PRISMA."}
        actions={
          <div className="flex flex-wrap gap-2">
            {canJoin ? (
              <form action="/api/clans/action" method="post">
                <input type="hidden" name="action" value="join" />
                <input type="hidden" name="target" value={c.id} />
                <button
                  type="submit"
                  className="prisma-glass-primary prisma-glass-hover inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium text-primary"
                >
                  Вступить
                </button>
              </form>
            ) : null}
            <Link
              href="/app/clans/compare"
              className="prisma-glass-control prisma-glass-hover inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium"
            >
              Клан VS Клан
            </Link>
            <Link
              href="/app/clan"
              className="prisma-glass-control prisma-glass-hover inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium"
            >
              Все кланы
            </Link>
          </div>
        }
      />

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <Metric label="Очки" value={c.points ?? 0} hint="клановые очки" icon="ranking" />
        <Metric label="Рейтинг" value={c.rating ?? 0} hint="clan rating" icon="bar-chart" />
        <Metric label="Уровень" value={c.level ?? 1} hint={(c.xp ?? 0) + " XP"} icon="activity" />
        <Metric label="Победы" value={c.wins ?? 0} hint={(c.losses ?? 0) + " поражений"} icon="battle" />
        <Metric label="Участники" value={memberCount} hint="активный состав" icon="players" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="overflow-hidden">
          <CardHeader>
            <CardTitle>Участники и роли</CardTitle>
          </CardHeader>
          <div className="divide-y">
            {data.members.map((member: any, index: number) => (
              <Link
                key={(member.nickname || "player") + ":" + index}
                href={member.nickname ? "/players/" + encodeURIComponent(member.nickname) : "#"}
                className="prisma-glass-hover flex items-center justify-between gap-3 px-5 py-4 transition-colors"
              >
                <span className="min-w-0 truncate">
                  <b>{member.nickname || "Игрок"}</b>
                  <span className="ml-2 text-xs text-muted-foreground">
                    ур. {member.level ?? 1}
                  </span>
                </span>
                <Badge variant={member.role === "owner" ? "success" : "secondary"}>
                  {roleLabel[member.role] || member.role || "Участник"}
                </Badge>
              </Link>
            ))}
            {!data.members.length ? (
              <p className="px-5 py-8 text-center text-sm text-muted-foreground">
                В клане пока нет участников.
              </p>
            ) : null}
          </div>
        </Card>

        <Card className="overflow-hidden">
          <CardHeader>
            <CardTitle>Войны и конфликты</CardTitle>
          </CardHeader>
          <div className="divide-y">
            {data.wars.map((war: any) => (
              <div key={war.id} className="px-5 py-4">
                <div className="flex items-center justify-between gap-3">
                  <p className="text-sm font-semibold">{war.opponent || "Неизвестный клан"}</p>
                  <Badge variant={war.status === "active" ? "warning" : "secondary"}>
                    {statusLabel[war.status] || war.status || "Статус не указан"}
                  </Badge>
                </div>
                <p className="mt-2 text-sm font-medium">
                  {war.score_for ?? 0} : {war.score_against ?? 0}
                </p>
                {war.scheduled_at ? (
                  <p className="mt-1 text-xs text-muted-foreground">
                    {new Date(war.scheduled_at).toLocaleString("ru-RU")}
                  </p>
                ) : null}
              </div>
            ))}
            {!data.wars.length ? (
              <p className="px-5 py-8 text-center text-sm text-muted-foreground">
                Истории войн ещё нет.
              </p>
            ) : null}
          </div>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Объявления клана</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {data.announcements.slice(0, 8).map((announcement: any) => (
            <article key={announcement.id} className="prisma-glass-surface rounded-md border p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="text-sm font-semibold">{announcement.title}</h3>
                <span className="text-xs text-muted-foreground">
                  {new Date(announcement.created_at).toLocaleString("ru-RU")}
                </span>
              </div>
              <p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-muted-foreground">
                {announcement.body}
              </p>
              <p className="mt-3 text-xs text-muted-foreground">
                {announcement.nickname || "Система PRISMA"}
              </p>
            </article>
          ))}
          {!data.announcements.length ? (
            <p className="text-sm text-muted-foreground">Объявлений пока нет.</p>
          ) : null}
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>История клана</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {data.activity.slice(0, 20).map((item: any) => (
                <article key={item.id} className="prisma-glass-surface rounded-md border p-3">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-xs font-semibold">{activityLabel[item.kind] || item.kind || "Событие"}</p>
                      <p className="mt-1 truncate text-xs text-muted-foreground">{activityText(item)}</p>
                    </div>
                    <time className="shrink-0 text-[11px] text-muted-foreground">
                      {new Date(item.created_at).toLocaleString("ru-RU")}
                    </time>
                  </div>
                  {item.xp ? <p className="mt-2 text-[11px] text-muted-foreground">+{item.xp} XP</p> : null}
                </article>
              ))}
            </div>
            {!data.activity.length ? (
              <p className="text-sm text-muted-foreground">
                История появится автоматически после действий участников, приглашений, территорий, объявлений и войн.
              </p>
            ) : null}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Территории</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid gap-2 sm:grid-cols-2">
              {data.villages.map((village: any) => (
                <div key={village.id} className="prisma-glass-surface rounded-md border p-4">
                  <p className="text-sm font-medium">{village.name}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {village.world} · X {Math.round(village.center_x)} · Z {Math.round(village.center_z)} · R
                    {village.radius}
                  </p>
                </div>
              ))}
            </div>
            {!data.villages.length ? (
              <p className="text-sm text-muted-foreground">Территорий ещё нет.</p>
            ) : null}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Достижения</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {data.achievements.map((achievement: any) => (
            <div key={achievement.achievement_id} className="prisma-glass-surface rounded-md border p-4">
              <div className="flex items-start gap-3">
                <span className="text-xl" aria-hidden="true">{achievement.achievements?.icon || "🏆"}</span>
                <div className="min-w-0">
                  <p className="text-sm font-medium">
                    {achievement.achievements?.title || "Достижение"}
                  </p>
                  <p className="mt-1 text-xs leading-5 text-muted-foreground">
                    {achievement.achievements?.description || "Описание отсутствует."}
                  </p>
                  <p className="mt-2 text-[11px] text-muted-foreground">
                    Открыто {new Date(achievement.unlocked_at).toLocaleDateString("ru-RU")}
                    {achievement.achievements?.xp_reward ? " · +" + achievement.achievements.xp_reward + " XP" : ""}
                  </p>
                </div>
              </div>
            </div>
          ))}
          {!data.achievements.length ? (
            <p className="text-sm text-muted-foreground sm:col-span-2 lg:col-span-3">
              Достижения клана ещё не открыты.
            </p>
          ) : null}
        </CardContent>
      </Card>
    </div>
  );
}
