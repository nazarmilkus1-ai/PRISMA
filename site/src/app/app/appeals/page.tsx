import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import Link from "next/link";
import { notFound } from "next/navigation";
import { PARTICIPANT_APPEAL_RPC } from "@prisma-eco/contracts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { APPEAL_STATUS_LABELS } from "@prisma-eco/contracts";

const statusLabel = APPEAL_STATUS_LABELS;
import { Badge, Card, CardContent, CardHeader, CardTitle, PageHeader } from "@prisma-eco/ui";

const errorLabel: Record<string,string> = {
  PLAYER_ACCESS_REQUIRED: "Апелляции доступны участникам с одобренной заявкой.",
  NO_ACTIVE_PUNISHMENT: "Активных наказаний нет.",
  PUNISHMENT_NOT_FOUND: "Наказание не найдено.",
  PUNISHMENT_NOT_ACTIVE: "Это наказание уже неактивно.",
  APPEAL_ALREADY_EXISTS: "По этому наказанию уже есть открытая апелляция.",
  INVALID_REASON: "Причина должна содержать 10–2000 символов.",
};

export default async function AppealsPage({ searchParams }: { searchParams: Promise<{ error?: string; created?: string }> }) {
  await requireModuleUser("appeals");
  const params = await searchParams;
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_APPEAL_RPC.list);
  const payload = (data ?? {}) as { appeals?: any[]; active_punishments?: any[] };
  const appeals = Array.isArray(payload.appeals) ? payload.appeals : [];
  const punishments = Array.isArray(payload.active_punishments) ? payload.active_punishments : [];

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <PageHeader eyebrow="Взаимодействие" title="Апелляции" description="Обращения по наказаниям и история решений администрации." />
        <Link href="/app/reports" className="text-sm text-muted-foreground hover:text-foreground">Перейти к репортам →</Link>
      </div>

      {params.created ? <div className="prisma-glass-surface rounded-xl border border-primary/30 p-3 text-sm">Апелляция отправлена администрации.</div> : null}
      {params.error ? <div className="prisma-glass-surface rounded-xl border border-destructive/30 p-3 text-sm text-destructive">{errorLabel[params.error] ?? "Не удалось отправить апелляцию."}</div> : null}

      <Card>
        <CardHeader><CardTitle>Новая апелляция</CardTitle></CardHeader>
        <CardContent>
          {punishments.length ? (
            <form action="/api/appeals" method="post" className="space-y-4">
              <div>
                <label htmlFor="punishment_id" className="text-sm font-medium">Наказание</label>
                <select id="punishment_id" name="punishment_id" className="prisma-glass-control mt-1 h-10 w-full rounded-md border px-3 text-sm">
                  {punishments.map((p: any) => (
                    <option key={p.id} value={p.id}>
                      {p.type} · {p.reason || "без причины"}{p.expires_at ? " · до " + new Date(p.expires_at).toLocaleString("ru-RU") : ""}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="reason" className="text-sm font-medium">Причина апелляции</label>
                <textarea id="reason" name="reason" required minLength={10} maxLength={2000} rows={6}
                  className="prisma-glass-control mt-1 w-full rounded-md border px-3 py-2 text-sm text-foreground outline-none focus:border-primary"
                  placeholder="Опишите, почему наказание стоит пересмотреть." />
              </div>
              <button type="submit" className="inline-flex h-10 items-center rounded-md bg-primary px-4 text-sm font-medium text-primary-foreground hover:opacity-90">Отправить апелляцию</button>
            </form>
          ) : (
            <p className="text-sm text-muted-foreground">Сейчас нет активных наказаний, на которые можно подать апелляцию.</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Мои апелляции</CardTitle></CardHeader>
        <CardContent>
          {appeals.length ? (
            <div className="space-y-3">
              {appeals.map((appeal: any) => (
                <article key={appeal.id} className="prisma-glass-surface rounded-xl border p-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge variant={appeal.status === "APPROVED" ? "default" : appeal.status === "REJECTED" ? "destructive" : "secondary"}>
                      {statusLabel[appeal.status] ?? appeal.status}
                    </Badge>
                    <span className="text-xs text-muted-foreground">{new Date(appeal.created_at).toLocaleString("ru-RU")}</span>
                    <span className="ml-auto text-xs text-muted-foreground">{appeal.punishment?.type ?? "Наказание"}</span>
                  </div>
                  <p className="mt-3 whitespace-pre-wrap text-sm leading-6">{appeal.reason}</p>
                  {appeal.review_note ? (
                    <div className="prisma-glass-surface mt-3 rounded-lg border p-3">
                      <p className="text-xs text-muted-foreground">Комментарий администрации</p>
                      <p className="mt-1 whitespace-pre-wrap text-sm">{appeal.review_note}</p>
                    </div>
                  ) : null}
                </article>
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">Вы ещё не подавали апелляций.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
