import { PARTICIPANT_MINECRAFT_AUTH_RPC, PARTICIPANT_NOTIFICATION_RPC } from "@prisma-eco/contracts";
import Link from "next/link";
import { getPublicModuleAvailability } from "@/lib/modules";
import { Alert, Card, CardContent, CardDescription, CardHeader, CardTitle } from "@prisma-eco/ui";
import { requireUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata = { title: "Настройки" };

export default async function SettingsPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; minecraft_auth?: string }>;
}) {
  const user = await requireUser();
  const enabledModules = await getPublicModuleAvailability();
  const params = await searchParams;
  const error = params.error;
  const minecraftAuthMessage = params.minecraft_auth;
  const db = await createSupabaseServerClient();
  const { data: minecraftAuthPayload } = await db.rpc(PARTICIPANT_MINECRAFT_AUTH_RPC.status);
  const minecraftAuth = minecraftAuthPayload && typeof minecraftAuthPayload === "object"
    ? minecraftAuthPayload as Record<string, unknown>
    : null;
  const { data: prefsPayload } = await db.rpc(PARTICIPANT_NOTIFICATION_RPC.preferences);
  const prefs = prefsPayload && typeof prefsPayload === "object" ? prefsPayload as Record<string, boolean> : null;
  const minecraftPlatform = String(minecraftAuth?.platform ?? "").toUpperCase();
  const minecraftConfigured = minecraftAuth?.configured === true;

  const rows = [
    ["news", "Новости"],
    ["events", "События"],
    ["server_status", "Статус сервера"],
    ["clan_news", "Новости клана"],
    ["social", "Социальные запросы"],
    ["battles", "Player Battle"],
    ["market", "Запросы рынка"],
    ["moderation", "Модерация"],
    ["polls", "Голосования"],
  ] as const;

  return (
    <div className="space-y-6">
      <div>
        <p className="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">Система</p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">Настройки</h1>
        <p className="mt-1 max-w-2xl text-sm leading-6 text-muted-foreground">
          Управление уведомлениями и основными параметрами аккаунта.
        </p>
      </div>

      {error ? <Alert variant="destructive" title="Не удалось сохранить настройку" /> : null}

      <Card>
        <CardHeader>
          <CardTitle>Аккаунт</CardTitle>
          <CardDescription>Основные привязки вашего аккаунта PRISMA.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2">
          <div className="prisma-glass-surface rounded-md border p-4">
            <p className="text-xs text-muted-foreground">Minecraft</p>
            <p className="mt-1 truncate text-sm font-medium">{user.minecraft_nickname || "—"}</p>
          </div>
          <div className="prisma-glass-surface rounded-md border p-4">
            <p className="text-xs text-muted-foreground">Telegram</p>
            <p className="mt-1 truncate text-sm font-medium">
              {user.telegram_username ? "@" + user.telegram_username : "—"}
            </p>
          </div>
        </CardContent>
        <div className="flex items-center border-t px-5 py-4">
          <Link
            href="/app/profile"
            className="prisma-glass-control prisma-glass-hover inline-flex h-8 items-center rounded-md border px-3 text-sm font-medium"
          >
            Изменить профиль
          </Link>
        </div>
      </Card>


      <Card>
        <CardHeader>
          <CardTitle>Авторизация Minecraft</CardTitle>
          <CardDescription>
            Встроенная PRISMA Auth для Java. SimpleLogin больше не используется.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {minecraftAuthMessage === "saved" ? <Alert variant="success" title="Пароль сохранён" /> : null}
          {minecraftAuthMessage === "password_mismatch" ? <Alert variant="destructive" title="Пароли не совпадают" /> : null}
          {minecraftAuthMessage === "current_password_invalid" ? <Alert variant="destructive" title="Текущий пароль неверный" /> : null}
          {minecraftAuthMessage === "invalid_password" ? <Alert variant="destructive" title="Пароль должен быть 8–72 байта" /> : null}
          {minecraftAuthMessage === "already_configured" ? <Alert variant="destructive" title="Пароль уже настроен" /> : null}
          {minecraftAuthMessage === "platform_not_java" ? <Alert variant="destructive" title="Для Bedrock пароль не нужен" /> : null}
          {minecraftAuthMessage === "player_access_required" ? <Alert variant="destructive" title="Доступно после одобрения и whitelist" /> : null}
          {minecraftAuthMessage === "save_failed" ? <Alert variant="destructive" title="Не удалось сохранить пароль" /> : null}

          {minecraftPlatform === "BEDROCK" ? (
            <div className="prisma-glass-surface rounded-xl border p-4 text-sm leading-6">
              <p className="font-medium">Bedrock</p>
              <p className="mt-1 text-muted-foreground">Пароль не используется. Вход подтверждается через Geyser + Floodgate.</p>
            </div>
          ) : minecraftPlatform === "JAVA" ? (
            <>
              <div className="prisma-glass-surface rounded-xl border p-4 text-sm">
                <p className="text-xs text-muted-foreground">Minecraft</p>
                <p className="mt-1 font-medium">{String(minecraftAuth?.minecraft_nickname ?? user.minecraft_nickname ?? "—")}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {minecraftConfigured ? "Пароль уже установлен." : "Пароль ещё не установлен."}
                </p>
              </div>
              <form action="/api/minecraft-auth/password" method="post" className="grid gap-4">
                {minecraftConfigured ? (
                  <label className="grid gap-1.5 text-sm font-medium">
                    Текущий пароль
                    <input name="current_password" type="password" minLength={8} maxLength={72} required autoComplete="current-password"
                      className="prisma-glass-control h-9 rounded-md border px-3 text-sm text-foreground outline-none focus:border-primary" />
                  </label>
                ) : null}
                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="grid gap-1.5 text-sm font-medium">
                    {minecraftConfigured ? "Новый пароль" : "Пароль"}
                    <input name="new_password" type="password" minLength={8} maxLength={72} required autoComplete="new-password"
                      className="prisma-glass-control h-9 rounded-md border px-3 text-sm text-foreground outline-none focus:border-primary" />
                  </label>
                  <label className="grid gap-1.5 text-sm font-medium">
                    Повторите пароль
                    <input name="new_password_confirm" type="password" minLength={8} maxLength={72} required autoComplete="new-password"
                      className="prisma-glass-control h-9 rounded-md border px-3 text-sm text-foreground outline-none focus:border-primary" />
                  </label>
                </div>
                <div>
                  <button type="submit" className="inline-flex h-9 items-center rounded-md bg-primary px-3.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90">
                    {minecraftConfigured ? "Изменить пароль" : "Установить пароль"}
                  </button>
                </div>
              </form>
            </>
          ) : (
            <div className="prisma-glass-surface rounded-xl border p-4 text-sm text-muted-foreground">
              Minecraft-платформа пока не привязана.
            </div>
          )}
        </CardContent>
      </Card>

      {enabledModules.notifications ? (
      <Card>
        <CardHeader>
          <CardTitle>Уведомления</CardTitle>
          <CardDescription>
            Выберите, о чём PRISMA будет писать вам. Настройки применяются отдельно к каждому типу событий.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="divide-y">
            {rows.map(([key, label]) => (
              <form
                key={key}
                action="/api/settings/notifications"
                method="post"
                className="flex items-center justify-between gap-4 px-5 py-4"
              >
                <input type="hidden" name="key" value={key} />
                <input
                  type="hidden"
                  name="value"
                  value={String(!(prefs as any)?.[key])}
                />
                <span className="text-sm font-medium">{label}</span>
                <button
                  type="submit"
                  className={[
                    "prisma-glass-control prisma-glass-hover rounded-full border px-3 py-1 text-xs font-medium",
                    (prefs as any)?.[key] === false
                      ? "text-muted-foreground hover:text-foreground"
                      : "border-primary/40 bg-transparent text-primary",
                  ].join(" ")}
                >
                  {(prefs as any)?.[key] === false ? "Выключено" : "Включено"}
                </button>
              </form>
            ))}
          </div>
        </CardContent>
      </Card>
      ) : null}
    </div>
  );
}
