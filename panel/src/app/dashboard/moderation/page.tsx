import { ModerationPanel } from "@/components/ModerationPanel";
import { requireAdmin } from "@/lib/require-admin";

export default async function ModerationPage() {
  const admin = await requireAdmin("punishment.view_history");
  if (!admin) return null;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl text-moon">Модерация</h1>
        <p className="mt-1 text-sm text-moon-dim">История игрока и удалённые действия</p>
      </div>
      <ModerationPanel />
    </div>
  );
}
