import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { NOTIFICATION_STATUS_LABELS, PARTICIPANT_RPC } from "@prisma-eco/contracts";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Card } from "@/components/Card";
import { SectionTitle } from "@/components/SitePrimitives";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata = { title: "Уведомления" };

function notificationHref(item: any) {
  const data = item?.data && typeof item.data === "object" ? item.data : {};
  const kind = String(item?.kind || "").toUpperCase();
  if (data.clan_id && ["CLAN", "CLAN_NEWS"].includes(kind)) return "/app/clans/" + encodeURIComponent(String(data.clan_id));
  if (data.slug) return "/events/" + encodeURIComponent(String(data.slug));
  if (data.event_slug) return "/events/" + encodeURIComponent(String(data.event_slug));
  if (data.report_id) return "/app/reports/" + encodeURIComponent(String(data.report_id));
  if (data.support_ticket_no && kind === "SUPPORT") return "/app/support?ticket_no=" + encodeURIComponent(String(data.support_ticket_no));
  if (data.ticket_no) return "/app/reports";
  if (data.application_id) return "/app/application";
  if (data.action && kind === "SOCIAL") return "/app/profile";
  if (data.battle_id && kind === "BATTLE") return "/app/battles";
  if (data.inquiry_id && kind === "MARKET") return "/app/market";
  return null;
}

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  await requireModuleUser("notifications");
  const params = await searchParams;
  const db = await createSupabaseServerClient();
  const { data: notifications, error } = await db.rpc(PARTICIPANT_RPC.notifications, { p_limit: 100 });

  const rows = Array.isArray(notifications) ? notifications : [];
  const unread = rows.filter((item: any) => item.status === "sent").length;

  return (
    <div className="mx-auto max-w-5xl px-4 py-6 sm:px-6 lg:px-8">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <SectionTitle
          eyebrow="ACCOUNT"
          title="Уведомления"
          description="Все изменения и события, которые относятся к вашему аккаунту."
        />
        {unread > 0 ? (
          <form action="/api/notifications/read" method="post">
            <button
              type="submit"
              className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-semibold text-foreground"
            >
              Отметить всё прочитанным
            </button>
          </form>
        ) : null}
      </div>

      {params.error || error ? (
        <Card className="mt-4 border-red-500/30 p-4 text-sm text-red-400">
          Не удалось обновить уведомления.
        </Card>
      ) : null}

      <div className="mt-5 space-y-3">
        {rows.map((item: any) => {
          const isUnread = item.status === "sent";
          return (
            <Card
              key={item.id}
              className={[
                "prisma-glass-surface prisma-glass-hover",
                isUnread ? "border-[var(--primary)]/40" : "",
              ].filter(Boolean).join(" ")}
            >
              <div className="flex gap-4 p-5">
                <div className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-xl bg-[var(--muted)] text-xs font-bold">
                  {isUnread ? "●" : "✓"}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <p className="font-semibold">{item.title || "Уведомление PRISMA"}</p>
                      <p className="mt-1 text-[11px] uppercase tracking-[0.14em] text-[var(--muted-foreground)]">
                        {item.kind || "system"} · {NOTIFICATION_STATUS_LABELS[item.status] ?? item.status}
                      </p>
                    </div>
                    <time
                      dateTime={item.created_at}
                      className="shrink-0 text-xs text-[var(--muted-foreground)]"
                    >
                      {new Date(item.created_at).toLocaleString("ru-RU")}
                    </time>
                  </div>
                  {item.body ? (
                    <p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-[var(--muted-foreground)]">
                      {item.body}
                    </p>
                  ) : null}
                  {notificationHref(item) ? (
                    <div className="mt-4">
                      <Link
                        href={notificationHref(item)!}
                        className="prisma-glass-control prisma-glass-hover inline-flex rounded-lg border px-3 py-1.5 text-xs font-semibold text-foreground"
                      >
                        Открыть
                      </Link>
                    </div>
                  ) : null}
                  {isUnread ? (
                    <form action="/api/notifications/read" method="post" className="mt-4">
                      <input type="hidden" name="id" value={item.id} />
                      <button
                        type="submit"
                        className="prisma-glass-control prisma-glass-hover rounded-lg border px-3 py-1.5 text-xs font-semibold text-foreground"
                      >
                        Отметить прочитанным
                      </button>
                    </form>
                  ) : null}
                </div>
              </div>
            </Card>
          );
        })}

        {!rows.length ? (
          <Card className="p-12 text-center">
            <p className="font-semibold">Уведомлений пока нет</p>
            <p className="mt-1 text-sm text-[var(--muted-foreground)]">
              Здесь появятся сообщения о заявках, кланах, событиях и других изменениях.
            </p>
          </Card>
        ) : null}
      </div>
    </div>
  );
}
