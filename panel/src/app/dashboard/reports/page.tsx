import { requireAdmin } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Metric, PageHeader } from "@prisma-eco/ui";
import { ReportsWorkspace } from "@/components/ReportsWorkspace";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function ReportsPage() {
  const admin = await requireAdmin("report.view");
  if (!admin) return null;

  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc(STAFF_RPC.reportStats);
  const stats = (data ?? {}) as {
    open?: number;
    in_review?: number;
    resolved?: number;
    dismissed?: number;
  };

  return <div className="space-y-6">
    <PageHeader eyebrow="Модерация" title="Репорты" description="Жалобы, баги и проблемы сервера с единым workflow рассмотрения." />
    <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <Metric label="Открытые" value={stats.open ?? 0} hint="требуют решения" icon="reports" />
      <Metric label="В работе" value={stats.in_review ?? 0} hint="взяты модератором" icon="moderation" />
      <Metric label="Решённые" value={stats.resolved ?? 0} hint="закрыты" icon="check" />
      <Metric label="Отклонённые" value={stats.dismissed ?? 0} hint="dismissed" icon="close" />
    </div>
    <ReportsWorkspace />
  </div>;
}
