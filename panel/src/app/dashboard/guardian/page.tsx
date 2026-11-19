import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { STAFF_GUARDIAN_RPC } from "@prisma-eco/contracts";
import { PageHeader } from "@prisma-eco/ui";
import { GuardianPanel, type GuardianOverview } from "@/components/GuardianPanel";

export const dynamic = "force-dynamic";

export default async function GuardianPage() {
  const context = await requireAdminContext("ops.view");
  if (!context) return null;

  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc(STAFF_GUARDIAN_RPC.overview);
  const overview = (data ?? { proposals: [], events: [], state: {} }) as GuardianOverview;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Система"
        title="Охранник"
        description="Следит за ботом, Render и деплоями. Сам делает только безопасное (рестарт при простое), остальное — после твоего подтверждения."
      />
      <GuardianPanel initial={overview} canManage={context.permissions.has("ops.manage")} />
    </div>
  );
}
