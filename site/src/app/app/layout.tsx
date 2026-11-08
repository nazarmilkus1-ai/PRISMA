import { PARTICIPANT_NOTIFICATION_COUNT_RPC } from "@prisma-eco/contracts";
import { requireUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ParticipantShell } from "@/components/ParticipantShell";
import { getPublicModuleAvailability } from "@/lib/modules";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const db = await createSupabaseServerClient();
  const { data: unread } = await db.rpc(PARTICIPANT_NOTIFICATION_COUNT_RPC.unread);
  const count = typeof unread === "number" ? unread : 0;
  const enabledModules = await getPublicModuleAvailability();

  return (
    <ParticipantShell user={user} notificationsCount={count ?? 0} enabledModules={enabledModules}>
      {children}
    </ParticipantShell>
  );
}
