import { NextResponse } from "next/server";
import { isPublicModuleEnabled } from "@/lib/modules";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_NOTIFICATION_MUTATION_RPC } from "@prisma-eco/contracts";
import { requireMember } from "@/lib/member";

const Schema = z.object({
  key: z.enum(["news","events","server_status","clan_news","social","battles","market","moderation","polls"]),
  value: z.enum(["true","false"]),
});

export async function POST(request: Request) {
  if (!(await isPublicModuleEnabled("notifications"))) {
    return NextResponse.redirect(new URL("/app?error=module_disabled&module=notifications", request.url), 303);
  }
  await requireMember();
  const form = Object.fromEntries((await request.formData()).entries());
  const parsed = Schema.safeParse(form);
  if (!parsed.success) return NextResponse.redirect(new URL("/app/settings?error=invalid", request.url), 303);

  const db = await createSupabaseServerClient();
  const { error } = await db.rpc(PARTICIPANT_NOTIFICATION_MUTATION_RPC.updatePreference, {
    p_key: parsed.data.key,
    p_value: parsed.data.value === "true",
  });

  if (error) {
    console.error("[site/settings]", error);
    return NextResponse.redirect(new URL("/app/settings?error=save_failed", request.url), 303);
  }

  return NextResponse.redirect(new URL("/app/settings", request.url), 303);
}
