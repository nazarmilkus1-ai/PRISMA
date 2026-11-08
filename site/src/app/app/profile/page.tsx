import { notFound } from "next/navigation";
import Link from "next/link";
import { getPublicModuleAvailability } from "@/lib/modules";
import { Card, CardContent, CardDescription, CardHeader, CardTitle, Badge, Button, Input, PageHeader, Metric, Alert } from "@prisma-eco/ui";
import { MINECRAFT_ROLES } from "@prisma-eco/contracts";
import { requireUser } from "@/lib/auth";
import { getDashboardData, getRankingEntry, getSocialData, getServerRole } from "@/lib/data";

export const metadata = { title: "Мой профиль" };

export default async function ProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ social_error?: string; social_done?: string; social_visibility_error?: string; social_visibility_saved?: string; error?: string; saved?: string }>;
}) {
  const enabledModules = await getPublicModuleAvailability();
  if (!enabledModules.players) notFound();
  const u = await requireUser();
  const sp = await searchParams;
  const [data, rankEntry, social, serverRole] = await Promise.all([
    getDashboardData(),
    getRankingEntry(u.id, "rating"),
    enabledModules.social ? getSocialData() : Promise.resolve(null),
    getServerRole(),
  ]);

  const stats: any = data.stats || {};
  const xp = Number(u.xp || 0);
  const levelProgress = Math.max(0, Math.min(1000, xp % 1000));
  const kills = Number(stats.kills || 0);
  const deaths = Number(stats.deaths || 0);
  const kd = deaths ? (kills / deaths).toFixed(2) : String(kills);
  const displayName = u.minecraft_nickname || u.first_name || "Игрок";
  const role = MINECRAFT_ROLES.find((item:any) => item.id === serverRole.role);
  const serverRoleLabel = role ? "[" + role.label + "] " + role.name : "[УЧ] Учасник";

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Профиль"
        title={displayName}
        description={enabledModules.social ? "Ваш публичный профиль, статистика и социальные возможности PRISMA." : "Ваш публичный профиль и статистика PRISMA."}
        actions={
          <div className="flex flex-wrap gap-2">
            <Link
              href="/app/rankings"
              className="prisma-glass-control prisma-glass-hover inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium"
            >
              Мой рейтинг
            </Link>
            {enabledModules.minecraft ? (
              <Link
                href="/app/minecraft"
                className="inline-flex h-9 items-center rounded-md bg-primary px-3.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
              >
                Моя статистика
              </Link>
            ) : null}
          </div>
        }
      />

      {sp.error ? (
        <Alert variant="destructive" title="Не удалось выполнить действие">
          {decodeURIComponent(sp.error)}
        </Alert>
      ) : null}
      {sp.saved ? <Alert variant="success" title="Профиль сохранён" /> : null}
      {enabledModules.social ? (
        <>
          {sp.social_error ? (
            <Alert variant="destructive" title="Социальное действие не выполнено">
              {decodeURIComponent(sp.social_error)}
            </Alert>
          ) : null}
          {sp.social_done ? <Alert variant="success" title="Действие выполнено" /> : null}
          {sp.social_visibility_error ? <Alert variant="destructive" title="Не удалось изменить видимость социального статуса" /> : null}
          {sp.social_visibility_saved ? <Alert variant="success" title="Настройка сохранена" /> : null}
        </>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Metric
          label="Рейтинг"
          value={u.rating || 0}
          hint={rankEntry?.rank != null ? "#" + rankEntry.rank + " место" : "позиция пока не рассчитана"}
          icon="bar-chart"
        />
        <Metric label="Активность" value={u.activity_score || 0} hint="активность PRISMA" icon="activity" />
        <Metric label="Уровень" value={u.level || 1} hint={xp + " XP"} icon="activity" />
        {enabledModules.minecraft ? <Metric label="K/D" value={kd} hint={kills + " убийств · " + deaths + " смертей"} icon="battle" /> : null}
      </div>

      <Card>
        <CardHeader className="flex-row items-start justify-between gap-4">
          <div>
            <CardTitle>Паспорт игрока</CardTitle>
            <CardDescription>Данные, которые доступны в вашем профиле PRISMA.</CardDescription>
          </div>
          <Badge variant={u.status === "ACTIVE" ? "success" : "secondary"}>{u.status || "Участник"}</Badge>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {[
            ["Minecraft", u.minecraft_nickname || "—"],
            ["Telegram", u.telegram_username ? "@" + u.telegram_username : "—"],
            ["Платформа", u.platform || "—"],
            ["Привилегия", serverRoleLabel],
            ["Имя", u.full_name || u.first_name || "—"],
            ["Возраст", u.age ?? "—"],
            ["Клан", data.clan?.name ? data.clan.name + " [" + data.clan.tag + "]" : "Без клана"],
          ].map(([label, value]) => (
            <div key={String(label)} className="prisma-glass-surface rounded-md border p-4">
              <p className="text-xs text-muted-foreground">{label}</p>
              <p className="mt-1 truncate text-sm font-medium">{String(value)}</p>
            </div>
          ))}
        </CardContent>
      </Card>

      {data.application ? (
        <Card>
          <CardHeader>
            <CardTitle>Анкета участника</CardTitle>
            <CardDescription>Основные сведения из анкеты вступления.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-md border bg-muted/40 p-4 sm:col-span-2">
              <p className="text-xs text-muted-foreground">О себе</p>
              <p className="mt-2 whitespace-pre-wrap text-sm leading-6">{data.application.about || "Не указано"}</p>
            </div>
            <div className="prisma-glass-surface rounded-md border p-4">
              <p className="text-xs text-muted-foreground">Цель участия</p>
              <p className="mt-2 text-sm leading-6">{data.application.goal || "Не указана"}</p>
            </div>
            <div className="prisma-glass-surface rounded-md border p-4">
              <p className="text-xs text-muted-foreground">Как узнал о PRISMA</p>
              <p className="mt-2 text-sm leading-6">{data.application.discovery_source || "Не указано"}</p>
            </div>
          </CardContent>
        </Card>
      ) : null}

      {enabledModules.social && social ? (
      <Card>
        <CardHeader>
          <CardTitle>Социальный профиль</CardTitle>
          <CardDescription>Игровые социальные функции PRISMA и история статусов.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="prisma-glass-surface rounded-md border p-4">
              <p className="text-xs text-muted-foreground">Брак</p>
              {social.marriage?.partner_nickname ? (
                <>
                  <p className="mt-2 font-medium">{social.marriage.partner_nickname}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    С {new Date(social.marriage.married_at).toLocaleDateString("ru-RU")}
                  </p>
                  <form action="/api/profile/social" method="post" className="mt-3">
                    <input type="hidden" name="action" value="MARRIAGE_DIVORCE" />
                    <Button type="submit" variant="outline" size="sm">
                      Завершить статус
                    </Button>
                  </form>
                </>
              ) : (
                <p className="mt-2 text-sm text-muted-foreground">Активного брака нет.</p>
              )}
            </div>

            <div className="prisma-glass-surface rounded-md border p-4">
              <p className="text-xs text-muted-foreground">Связь</p>
              {social.relationship?.partner_nickname ? (
                <>
                  <p className="mt-2 font-medium">{social.relationship.partner_nickname}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    С {new Date(social.relationship.started_at).toLocaleDateString("ru-RU")}
                  </p>
                  <form action="/api/profile/social" method="post" className="mt-3">
                    <input type="hidden" name="action" value="RELATIONSHIP_END" />
                    <input type="hidden" name="target" value={social.relationship.partner_nickname} />
                    <Button type="submit" variant="outline" size="sm">
                      Завершить статус
                    </Button>
                  </form>
                </>
              ) : (
                <p className="mt-2 text-sm text-muted-foreground">Активной связи нет.</p>
              )}
            </div>
          </div>

          <div className="rounded-md border p-4">
            <p className="text-sm font-medium">Новый запрос</p>
            <p className="mt-1 text-xs text-muted-foreground">Укажите точный Minecraft-ник участника PRISMA.</p>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <form action="/api/profile/social" method="post" className="flex gap-2">
                <input type="hidden" name="action" value="MARRIAGE_REQUEST" />
                <Input name="target" required maxLength={32} placeholder="Ник для брака" />
                <Button type="submit" size="sm">Отправить</Button>
              </form>
              <form action="/api/profile/social" method="post" className="flex gap-2">
                <input type="hidden" name="action" value="RELATIONSHIP_REQUEST" />
                <Input name="target" required maxLength={32} placeholder="Ник для связи" />
                <Button type="submit" size="sm" variant="outline">Отправить</Button>
              </form>
            </div>
          </div>

          {(social.marriage_requests_in.length + social.relationship_requests_in.length) > 0 ? (
            <div>
              <p className="text-sm font-medium">Входящие запросы</p>
              <div className="mt-3 space-y-2">
                {social.marriage_requests_in.map((x: any) => (
                  <div key={"mi" + x.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm">
                    <span><b>Брак</b> · {x.requester_nickname}</span>
                    <div className="flex gap-2">
                      <form action="/api/profile/social" method="post">
                        <input type="hidden" name="action" value="MARRIAGE_ACCEPT" />
                        <input type="hidden" name="request_id" value={x.id} />
                        <Button type="submit" size="sm">Принять</Button>
                      </form>
                      <form action="/api/profile/social" method="post">
                        <input type="hidden" name="action" value="MARRIAGE_REJECT" />
                        <input type="hidden" name="request_id" value={x.id} />
                        <Button type="submit" variant="outline" size="sm">Отклонить</Button>
                      </form>
                    </div>
                  </div>
                ))}

                {social.relationship_requests_in.map((x: any) => (
                  <div key={"ri" + x.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm">
                    <span><b>Связь</b> · {x.requester_nickname}</span>
                    <div className="flex gap-2">
                      <form action="/api/profile/social" method="post">
                        <input type="hidden" name="action" value="RELATIONSHIP_ACCEPT" />
                        <input type="hidden" name="request_id" value={x.id} />
                        <Button type="submit" size="sm">Принять</Button>
                      </form>
                      <form action="/api/profile/social" method="post">
                        <input type="hidden" name="action" value="RELATIONSHIP_REJECT" />
                        <input type="hidden" name="request_id" value={x.id} />
                        <Button type="submit" variant="outline" size="sm">Отклонить</Button>
                      </form>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : null}

          {(social.marriage_requests_out.length + social.relationship_requests_out.length) > 0 ? (
            <div>
              <p className="text-sm font-medium">Ожидающие запросы</p>
              <div className="mt-3 space-y-2">
                {social.marriage_requests_out.map((x: any) => (
                  <div key={"mo" + x.id} className="flex items-center justify-between gap-3 rounded-md border p-3 text-sm">
                    <span><b>Брак</b> · {x.target_nickname}</span>
                    <form action="/api/profile/social" method="post">
                      <input type="hidden" name="action" value="MARRIAGE_CANCEL_REQUEST" />
                      <input type="hidden" name="request_id" value={x.id} />
                      <Button type="submit" variant="outline" size="sm">Отменить</Button>
                    </form>
                  </div>
                ))}
                {social.relationship_requests_out.map((x: any) => (
                  <div key={"ro" + x.id} className="flex items-center justify-between gap-3 rounded-md border p-3 text-sm">
                    <span><b>Связь</b> · {x.target_nickname}</span>
                    <form action="/api/profile/social" method="post">
                      <input type="hidden" name="action" value="RELATIONSHIP_CANCEL_REQUEST" />
                      <input type="hidden" name="request_id" value={x.id} />
                      <Button type="submit" variant="outline" size="sm">Отменить</Button>
                    </form>
                  </div>
                ))}
              </div>
            </div>
          ) : null}

          <div className="border-t pt-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-sm font-medium">Видимость социального статуса</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {data.user?.social_visibility === "PUBLIC"
                    ? "Другие участники могут видеть ваш текущий брак или отношения в профиле."
                    : "Ваш текущий брак и отношения скрыты от других участников."}
                </p>
              </div>
              <form action="/api/profile/social-visibility" method="post">
                <input
                  type="hidden"
                  name="visibility"
                  value={data.user?.social_visibility === "PUBLIC" ? "PRIVATE" : "PUBLIC"}
                />
                <Button type="submit" variant="outline" size="sm">
                  {data.user?.social_visibility === "PUBLIC" ? "Скрыть статус" : "Показывать статус"}
                </Button>
              </form>
            </div>
          </div>

          {(social.marriage_history.length + social.relationship_history.length) > 0 ? (
            <div>
              <p className="text-sm font-medium">История</p>
              <div className="mt-3 space-y-2">
                {[
                  ...social.marriage_history.map((x: any) => ({
                    ...x,
                    kind: "Брак",
                    date: x.married_at,
                    end: x.divorced_at,
                  })),
                  ...social.relationship_history.map((x: any) => ({
                    ...x,
                    kind: "Связь",
                    date: x.started_at,
                    end: x.ended_at,
                  })),
                ]
                  .sort((a: any, b: any) => new Date(b.date).getTime() - new Date(a.date).getTime())
                  .slice(0, 8)
                  .map((x: any) => (
                    <div key={x.kind + x.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border px-3 py-2.5 text-sm">
                      <span><b>{x.kind}</b> · {x.partner_nickname || "Игрок"}</span>
                      <span className="text-xs text-muted-foreground">
                        {new Date(x.date).toLocaleDateString("ru-RU")}
                        {x.end ? " → " + new Date(x.end).toLocaleDateString("ru-RU") : ""}
                      </span>
                    </div>
                  ))}
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Прогресс уровня</CardTitle>
          <CardDescription>{levelProgress} / 1000 XP до следующего уровня.</CardDescription>
        </CardHeader>
        <CardContent>
          <div
            className="h-2 overflow-hidden rounded-full bg-muted"
            role="progressbar"
            aria-label="Прогресс уровня"
            aria-valuemin={0}
            aria-valuemax={1000}
            aria-valuenow={levelProgress}
          >
            <div className="h-full rounded-full bg-primary transition-[width]" style={{ width: (levelProgress / 10) + "%" }} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Редактирование профиля</CardTitle>
          <CardDescription>
            Здесь можно изменить только имя. Язык PRISMA сейчас фиксирован на русском.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form action="/api/profile/update" method="post" className="grid gap-4 sm:grid-cols-2">
            <label className="grid gap-1.5 text-sm font-medium">
              Имя
              <Input name="full_name" required maxLength={100} defaultValue={u.full_name || u.first_name || ""} placeholder="Имя" />
            </label>
            <div className="grid gap-1.5 text-sm font-medium">
              Язык
              <div className="flex h-9 items-center rounded-md border bg-muted/40 px-3 text-sm text-muted-foreground">
                Русский
              </div>
              <input type="hidden" name="locale" value="ru" />
            </div>
            <div className="sm:col-span-2">
              <Button type="submit">Сохранить изменения</Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
