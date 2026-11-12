import { Card } from "@/components/Card";
import { StatusBadge } from "@/components/StatusBadge";
import { getCommunityStatus } from "@/lib/data";

export const metadata = { title: "Состояние PRISMA" };
export const revalidate = 30;

function ago(seconds: number | null) {
  if (seconds === null) return "данных ещё нет";
  if (seconds < 90) return "только что";
  if (seconds < 3600) return `${Math.round(seconds / 60)} мин назад`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} ч назад`;
  return `${Math.round(seconds / 86400)} дн назад`;
}

export default async function StatusPage() {
  const status = await getCommunityStatus();
  const allOk = status.database.ok && status.minecraft.online;
  const rows = [
    { name: "Сайт", ok: true, detail: "Страница отдаётся" },
    {
      name: "Данные и вход",
      ok: status.database.ok,
      detail: status.database.ok ? `Отвечают за ${status.database.latencyMs} мс` : "Сейчас недоступны — вход и кабинет могут не работать",
    },
    {
      name: "Minecraft-сервер",
      ok: status.minecraft.online,
      detail: status.minecraft.online ? `Онлайн · связь ${ago(status.minecraft.lastSeenSeconds)}` : `Не на связи · последний сигнал: ${ago(status.minecraft.lastSeenSeconds)}`,
    },
  ];
  return (
    <div className="mx-auto max-w-3xl px-4 py-10 sm:px-6">
      <p className="text-xs font-semibold uppercase tracking-[.18em] text-[var(--primary)]">СОСТОЯНИЕ</p>
      <div className="mt-1 flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-3xl font-semibold">Всё ли работает?</h1>
        <StatusBadge online={allOk}>{allOk ? "Всё работает" : "Есть проблемы"}</StatusBadge>
      </div>
      <p className="mt-2 text-sm text-[var(--muted-foreground)]">Публично показываем только доступность. Адрес сервера и список игроков — в кабинете участников.</p>
      <div className="mt-6 space-y-3">
        {rows.map((row) => (
          <Card key={row.name} className="prisma-glass-surface flex items-center justify-between gap-4 p-4">
            <div>
              <p className="font-semibold">{row.name}</p>
              <p className="mt-1 text-sm text-[var(--muted-foreground)]">{row.detail}</p>
            </div>
            <StatusBadge online={row.ok}>{row.ok ? "OK" : "Сбой"}</StatusBadge>
          </Card>
        ))}
      </div>
      <p className="mt-4 text-xs text-[var(--muted-foreground)]">Проверено: {new Date(status.checkedAt).toLocaleString("ru-RU")} · обновляется автоматически. Для мониторинга: /api/status</p>
      <p className="mt-6 text-sm text-[var(--muted-foreground)]">Что-то не работает, а здесь всё зелёное? Напишите в поддержку через бота или спросите PRISMA_AI.</p>
    </div>
  );
}
