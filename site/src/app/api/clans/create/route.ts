import { isPublicModuleEnabled } from "@/lib/modules";
import { NextResponse } from "next/server";
import { getCurrentUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_CLAN_MUTATION_RPC } from "@prisma-eco/contracts";

const ERRORS: Record<string, string> = {
  USER_NOT_LINKED: "Профиль PRISMA не связан с текущим аккаунтом.",
  USER_NOT_APPROVED: "Действие доступно только одобренным участникам.",
  INVALID_CLAN_NAME: "Название клана должно содержать от 2 до 32 символов.",
  CLAN_NAME_INVALID: "Название клана должно содержать от 2 до 32 символов.",
  CLAN_NAME_TAKEN: "Клан с таким названием уже существует.",
  USER_ALREADY_IN_CLAN: "Вы уже состоите в клане.",
  CLAN_TAG_TAKEN: "Не удалось подобрать свободный тег клана.",
  CLAN_CREATE_RETRY: "Не удалось подобрать свободный тег клана.",
  CLAN_CREATE_FAILED: "Не удалось создать клан.",
};

function back(request: Request, error?: string) {
  const url = new URL("/app/clan", request.url);
  if (error) url.searchParams.set("error", error);
  return NextResponse.redirect(url, 303);
}

async function moduleDisabledResponse(request: Request) {
  return NextResponse.redirect(new URL("/app?error=module_disabled&module=clans", request.url), 303);
}

export async function POST(request: Request) {
  if (!(await isPublicModuleEnabled("clans"))) return moduleDisabledResponse(request);
  const user = await getCurrentUser();
  if (!user) return NextResponse.redirect(new URL("/login", request.url));
  if (user.status !== "ACCEPTED" || user.is_banned) return back(request, "forbidden");

  const form = await request.formData();
  const name = String(form.get("name") ?? "").trim();
  if (name.length < 2 || name.length > 32) return back(request, "INVALID_CLAN_NAME");

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.create, { p_name: name });

  if (error) return back(request, ERRORS[error.message] ?? "Не удалось создать клан.");
  if (!data || data.success === false) return back(request, ERRORS[data?.error] ?? "CLAN_CREATE_FAILED");

  return NextResponse.redirect(new URL("/app/clan?created=1", request.url), 303);
}
