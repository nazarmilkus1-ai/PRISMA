import { NextResponse } from "next/server";
import { isPublicModuleEnabled } from "@/lib/modules";
import { z } from "zod";
import { getCurrentUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_NOTIFICATION_MUTATION_RPC } from "@prisma-eco/contracts";

const Schema = z.object({ id: z.string().uuid().optional() });

export async function POST(req: Request) {
  if (!(await isPublicModuleEnabled("notifications"))) {
    return NextResponse.redirect(new URL("/app?error=module_disabled&module=notifications", req.url), 303);
  }
  const user = await getCurrentUser();
  if (!user) return NextResponse.redirect(new URL("/login", req.url));

  const form = Object.fromEntries((await req.formData()).entries());
  const parsed = Schema.safeParse(form);
  if (!parsed.success) {
    return NextResponse.redirect(new URL("/app/notifications?error=invalid", req.url), 303);
  }

  const db = await createSupabaseServerClient();
  const { error } = await db.rpc(PARTICIPANT_NOTIFICATION_MUTATION_RPC.markRead, {
    p_notification_id: parsed.data.id ?? null,
  });

  return NextResponse.redirect(
    new URL(error ? "/app/notifications?error=save_failed" : "/app/notifications", req.url),
    303,
  );
}
