import { NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

const BodySchema = z.object({
  target_user_id: z.string().uuid(),
  role: z.enum(["co_owner", "officer", "member", "recruit"]),
});

export async function PATCH(request: Request) {
  const admin = await requireAdminContext("clan.manage");
  if (!admin) {
    return NextResponse.json({ error: "Нет права управлять кланами." }, { status: 403 });
  }

  const body = await request.json().catch(() => ({}));
  const parsed = BodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "Некорректные данные запроса." }, { status: 400 });
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.clanMemberRole, {
    p_target_user_id: parsed.data.target_user_id,
    p_role: parsed.data.role,
  });

  if (error) {
    const messages: Record<string, string> = {
      ADMIN_PROFILE_NOT_LINKED: "Профиль администратора не связан с PRISMA.",
      FORBIDDEN: "Нет права управлять кланами.",
      TARGET_NOT_IN_CLAN: "Игрок не состоит в активном клане.",
      OWNER_PROTECTED: "Владельца клана нельзя изменить этой операцией.",
      ROLE_UNCHANGED: "У игрока уже установлена эта роль.",
      INVALID_ROLE: "Выбрана некорректная роль.",
    };
    return NextResponse.json(
      { error: messages[error.message] ?? "Не удалось изменить роль." },
      { status: 409 },
    );
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result || result.success !== true) {
    return NextResponse.json({ error: "Не удалось изменить роль." }, { status: 500 });
  }

  return NextResponse.json({ ok: true, result });
}
