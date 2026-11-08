import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { DashboardShell } from "@/components/DashboardShell";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) redirect("/");

  const { data: aal, error: aalError } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aalError) redirect("/mfa?error=assurance");
  if (aal.nextLevel === "aal2" && aal.currentLevel !== "aal2") {
    redirect("/mfa?next=%2Fdashboard");
  }

  // Do not render the navigation shell for accounts which have no staff identity.
  // Previously every page silently returned null in this case, leaving a blank
  // content area under an otherwise normal-looking admin menu.
  const { data: staff, error: staffError } = await supabase.rpc(STAFF_RPC.authContext);
  const staffPayload = staff && typeof staff === "object" ? staff as Record<string, unknown> : null;
  if (
    staffError ||
    !staffPayload?.user_id ||
    !staffPayload?.admin_id ||
    !staffPayload?.role
  ) {
    redirect("/access-denied");
  }

  return <DashboardShell><div className="prisma-page-enter">{children}</div></DashboardShell>;
}
