import { requireAdmin } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { AppealsPanel } from "@/components/AppealsPanel";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function AppealsPage() {
  const admin = await requireAdmin("appeal.view");
  if (!admin) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.appeals, {
    p_status: "OPEN",
    p_limit: 500,
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl text-moon">Апелляции</h1>
        <p className="mt-1 text-sm text-moon-dim">Рассмотрение обращений по активным наказаниям через единый moderation workflow.</p>
      </div>
      {error ? (
        <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">
          Не удалось загрузить апелляции: {error.message}
        </div>
      ) : null}
      <AppealsPanel initialAppeals={Array.isArray(data) ? data : []} />
    </div>
  );
}
