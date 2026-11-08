import { AutomodSettings } from "@/components/AutomodSettings";
import { PasswordSettings } from "@/components/PasswordSettings";
import { ThemeSwitcher } from "@/components/ThemeSwitcher";
import { Card } from "@/components/ui";
import { requireAdmin } from "@/lib/require-admin";

const EXPORTS = [
  ["users", "Пользователи / player 360"],
  ["applications", "Анкеты"],
  ["moderation", "Модерация"],
  ["reports", "Репорти"],
  ["audit", "Аудит"],
] as const;

export default async function ExtraPage() {
  const admin = await requireAdmin("settings.view");
  if (!admin) return null;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-display text-2xl text-moon">Налаштування</h1>
        <p className="mt-1 text-sm text-moon-dim">Безопасность аккаунта, тема оформления, автомодерация и экспорт данных.</p>
      </div>

      <div>
        <h2 className="mb-3 font-display text-lg text-moon">Безпека акаунта</h2>
        <PasswordSettings />
      </div>

      <div>
        <h2 className="mb-3 font-display text-lg text-moon">Тема оформлення</h2>
        <Card className="p-5"><ThemeSwitcher /></Card>
      </div>

      <div>
        <h2 className="mb-3 font-display text-lg text-moon">Автомодерация</h2>
        <AutomodSettings />
      </div>

      <div>
        <h2 className="mb-3 font-display text-lg text-moon">Експорт</h2>
        <Card className="p-5">
          <p className="text-sm text-moon-dim">CSV-экспорт формируется на сервере после проверки permission. Секреты и ключи в экспорт не попадают.</p>
          <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-5">
            {EXPORTS.map(([key, label]) => (
              <a
                key={key}
                href={`/admin/api/export?resource=${key}`}
                className="rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon transition-colors hover:border-ember/40 hover:text-ember"
              >
                ↓ {label}
              </a>
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}
