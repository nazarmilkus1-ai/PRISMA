import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { EventsPanel } from "@/components/EventsPanel";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function EventsPage() {
  const admin = await requireAdminContext("event.manage");
  if (!admin) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.events, { p_limit: 100 });
  const events = Array.isArray(data) ? data : [];

  if (error) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="font-display text-2xl text-moon">События</h1>
          <p className="mt-1 text-sm text-moon-dim">Управление мероприятиями PRISMA.</p>
        </div>
        <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">
          Не удалось загрузить события: {error.message}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-curse">Сообщество</p>
        <h1 className="mt-1 font-display text-2xl text-moon">События</h1>
        <p className="mt-1 text-sm text-moon-dim">
          Создание, публикация, расписание и результаты мероприятий PRISMA.
        </p>
      </div>
      <EventsPanel initialEvents={events} />
    </div>
  );
}
