import { NextResponse } from "next/server";
import { z } from "zod";
import { PARTICIPANT_MINECRAFT_AUTH_RPC } from "@prisma-eco/contracts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireMember } from "@/lib/member";

const Schema = z.object({
  current_password: z.string().optional().default(""),
  new_password: z.string().min(8).max(72),
  new_password_confirm: z.string().min(8).max(72),
}).superRefine((data, ctx) => {
  if (data.new_password !== data.new_password_confirm) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["new_password_confirm"],
      message: "PASSWORD_MISMATCH",
    });
  }
});

function redirect(request: Request, target: string) {
  return NextResponse.redirect(new URL(target, request.url), 303);
}

export async function POST(request: Request) {
  await requireMember();

  const form = Object.fromEntries((await request.formData()).entries());
  const parsed = Schema.safeParse(form);
  if (!parsed.success) {
    const mismatch = parsed.error.issues.some((issue) => issue.message === "PASSWORD_MISMATCH");
    return redirect(request, "/app/settings?minecraft_auth=" + (mismatch ? "password_mismatch" : "invalid_password"));
  }

  if (new TextEncoder().encode(parsed.data.new_password).length > 72) {
    return redirect(request, "/app/settings?minecraft_auth=invalid_password");
  }

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_MINECRAFT_AUTH_RPC.setPassword, {
    p_current_password: parsed.data.current_password,
    p_new_password: parsed.data.new_password,
  });

  if (error) {
    console.error("[site/minecraft-auth]", error);
    return redirect(request, "/app/settings?minecraft_auth=save_failed");
  }

  const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
  const code = String(payload.error ?? "");
  if (code) {
    const statusMap: Record<string, string> = {
      INVALID_PASSWORD: "invalid_password",
      CURRENT_PASSWORD_INVALID: "current_password_invalid",
      AUTH_NOT_CONFIGURED: "not_configured",
      AUTH_ALREADY_CONFIGURED: "already_configured",
      PLAYER_ACCESS_REQUIRED: "player_access_required",
      PLATFORM_NOT_JAVA: "platform_not_java",
    };
    return redirect(request, "/app/settings?minecraft_auth=" + (statusMap[code] ?? "save_failed"));
  }

  return redirect(request, "/app/settings?minecraft_auth=saved");
}
