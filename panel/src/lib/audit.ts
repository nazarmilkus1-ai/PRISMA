import "server-only";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import type { User } from "@supabase/supabase-js";

function telegramIdFromAuthUser(actor: User | null): number | null {
  const email = actor?.email?.trim().toLowerCase() ?? "";
  const match = email.match(/^tg-(\d+)@admins\.prisma\.internal$/);
  return match ? Number(match[1]) : null;
}

export async function audit(
  actor: User | null,
  input: {
    actorUserId?: string | null;
    action: string;
    resource: string;
    resourceId?: string | null;
    metadata?: Record<string, unknown>;
  },
) {
  try {
    const admin = createSupabaseAdminClient();
    const actorTgId = telegramIdFromAuthUser(actor);
    let actorUserId = input.actorUserId ?? null;

    if (!actorUserId && actorTgId !== null) {
      const { data: profile } = await admin
        .from("users")
        .select("id")
        .eq("telegram_id", actorTgId)
        .is("deleted_at", null)
        .maybeSingle();
      actorUserId = profile?.id ?? null;
    }

    await admin.from("audit_logs").insert({
      actor_user_id: actorUserId,
      actor_tg_id: actorTgId,
      action: input.action,
      target_type: input.resource,
      target_id: input.resourceId ?? null,
      old_data: null,
      new_data: input.metadata ?? {},
    });
  } catch (error) {
    console.error("[audit] write failed", error);
  }
}
