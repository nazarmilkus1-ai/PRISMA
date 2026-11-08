import { isPublicModuleEnabled } from "@/lib/modules";
import { NextResponse } from "next/server";
import { getCurrentUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_BATTLE_MUTATION_RPC } from "@prisma-eco/contracts";

const ERRORS: Record<string, string> = {
  USER_NOT_LINKED: "Профиль PRISMA не связан с текущим аккаунтом.",
  USER_NOT_APPROVED: "Бои доступны только одобренным участникам с whitelist.",
  PLAYER_ACCESS_REQUIRED: "Бои доступны только одобренным участникам с whitelist.",
  OPPONENT_INVALID: "Укажите корректный Minecraft-ник.",
  OPPONENT_NOT_FOUND: "Игрок не найден или сейчас не может участвовать в бою.",
  BATTLE_COOLDOWN: "С этим игроком уже был бой в последние 24 часа.",
};

export async function POST(req: Request) {
  if (!(await isPublicModuleEnabled("battles"))) {
    return NextResponse.redirect(new URL("/app?error=module_disabled&module=battles", req.url), 303);
  }
  const user = await getCurrentUser();
  if (!user) return NextResponse.redirect(new URL("/login", req.url), 303);
  if (user.status !== "ACCEPTED" || user.is_banned) {
    return NextResponse.redirect(new URL("/app/battles?error=forbidden", req.url), 303);
  }

  const form = await req.formData();
  const opponent = String(form.get("opponent") ?? "").trim();
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_BATTLE_MUTATION_RPC.create, {
    p_opponent_nickname: opponent,
  });

  if (error) {
    const message = ERRORS[error.message] ?? "Не удалось запустить бой.";
    return NextResponse.redirect(
      new URL("/app/battles?error=" + encodeURIComponent(message), req.url),
      303,
    );
  }

  if (!data || data.success !== true) {
    return NextResponse.redirect(
      new URL("/app/battles?error=" + encodeURIComponent("Бой не был создан."), req.url),
      303,
    );
  }

  return NextResponse.redirect(new URL("/app/battles?created=1", req.url), 303);
}
