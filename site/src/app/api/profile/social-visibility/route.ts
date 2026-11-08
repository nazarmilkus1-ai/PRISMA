import { isPublicModuleEnabled } from "@/lib/modules";
import { NextResponse } from "next/server";
import { getCurrentUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_PROFILE_MUTATION_RPC } from "@prisma-eco/contracts";

function redirect(req: Request, target: string) {
  return NextResponse.redirect(new URL(target, req.url), 303);
}

export async function POST(req: Request) {
  if (!(await isPublicModuleEnabled("social"))) {
    return redirect(req, "/app?error=module_disabled&module=social");
  }
  const user = await getCurrentUser();
  if (!user) return redirect(req, "/login");

  const form = await req.formData();
  const visibility = String(form.get("visibility") ?? "PRIVATE").trim().toUpperCase();

  if (!["PRIVATE", "PUBLIC"].includes(visibility)) {
    return redirect(req, "/app/profile?social_visibility_error=1");
  }

  const db = await createSupabaseServerClient();
  const { error } = await db.rpc(PARTICIPANT_PROFILE_MUTATION_RPC.updateSocialVisibility, {
    p_visibility: visibility,
  });

  return redirect(
    req,
    error
      ? "/app/profile?social_visibility_error=1"
      : "/app/profile?social_visibility_saved=1",
  );
}
