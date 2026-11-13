import { NextResponse } from "next/server";
import { isPublicModuleEnabled } from "@/lib/modules";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_APPLICATION_MUTATION_RPC } from "@prisma-eco/contracts";

function isValidCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;

  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function isNicknameValidForPlatform(nickname: string, platform: "JAVA" | "BEDROCK"): boolean {
  if (platform === "JAVA") return /^[A-Za-z0-9_]{3,16}$/.test(nickname);
  const gamertag = nickname
    .replace(/^\./, "")
    .replace(/#[0-9]{1,6}$/, "")
    .replace(/\s+/g, " ")
    .trim();
  return /^[A-Za-z0-9_ ]{3,15}$/.test(gamertag);
}

const ApplicationSchema = z.object({
  full_name: z.string().trim().min(2).max(100),
  birth_date: z.string().refine(isValidCalendarDate, {
    message: "INVALID_BIRTH_DATE",
  }),
  // Java: 3-16 of [A-Za-z0-9_]. Bedrock: a real Gamertag (spaces allowed, up to 15; the database turns it into ".D1lan_ok").
  nickname: z.string().trim().min(3).max(24).regex(/^\.?[A-Za-z0-9_ ]+(#[0-9]{1,6})?$/),
  platform: z.enum(["JAVA", "BEDROCK"]),
  goal: z.string().trim().max(1000).optional().or(z.literal("")),
  about: z.string().trim().max(1000).optional().or(z.literal("")),
  discovery_source: z.enum([
    "Telegram",
    "TikTok",
    "YouTube",
    "Discord",
    "Рекомендация друга",
    "Другое",
  ]),
  agreement: z.literal("yes"),
});

const ERROR_MESSAGES: Record<string, string> = {
  APPLICATION_PENDING: "У вас уже есть заявка на рассмотрении.",
  APPLICATION_ALREADY_ACTIVE: "У вас уже есть одобренный доступ к PRISMA.",
  APPLICATION_COOLDOWN: "Повторная подача пока недоступна. Дождитесь окончания срока ожидания.",
  AGE_TOO_YOUNG: "Для подачи заявки нужно быть не младше 14 лет.",
  INVALID_BIRTH_DATE: "Укажите корректную дату рождения.",
  INVALID_MINECRAFT_NICK: "Minecraft-ник должен содержать 3–16 латинских символов, цифр или _.",
  MINECRAFT_NICK_TAKEN: "Этот Minecraft-ник уже используется.",
  TELEGRAM_NOT_LINKED: "Сначала свяжите Telegram с профилем PRISMA.",
  USER_NOT_LINKED: "Профиль PRISMA не связан с текущим аккаунтом.",
  INVALID_PLATFORM: "Выберите корректную платформу.",
  INVALID_DISCOVERY_SOURCE: "Выберите источник, из которого вы узнали о PRISMA.",
};

function redirectBack(request: Request, params: Record<string, string>) {
  const url = new URL("/app/application", request.url);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  return NextResponse.redirect(url, 303);
}

export async function POST(request: Request) {
  if (!(await isPublicModuleEnabled("applications"))) {
    return NextResponse.redirect(new URL("/?error=module_disabled&module=applications", request.url), 303);
  }
  const supabase = await createSupabaseServerClient();
  const { data: claims } = await supabase.auth.getClaims();

  if (!claims?.claims?.sub) {
    return redirectBack(request, { error: "Сессия истекла. Войдите снова." });
  }

  const form = await request.formData();
  const payload = {
    full_name: String(form.get("full_name") ?? ""),
    birth_date: String(form.get("birth_date") ?? ""),
    nickname: String(form.get("nickname") ?? ""),
    platform: String(form.get("platform") ?? ""),
    goal: String(form.get("goal") ?? ""),
    about: String(form.get("about") ?? ""),
    discovery_source: String(form.get("discovery_source") ?? ""),
    agreement: String(form.get("agreement") ?? ""),
  };

  const parsed = ApplicationSchema.safeParse(payload);
  if (!parsed.success) {
    return redirectBack(request, { error: "Проверьте заполнение всех обязательных полей заявки." });
  }
  if (!isNicknameValidForPlatform(parsed.data.nickname, parsed.data.platform)) {
    return redirectBack(request, {
      error: parsed.data.platform === "JAVA"
        ? "Java-ник: 3–16 символов, только латиница, цифры и «_», без пробелов."
        : "Bedrock Gamertag: 3–15 символов, латиница, цифры и пробелы.",
    });
  }

  const { error } = await supabase.rpc(PARTICIPANT_APPLICATION_MUTATION_RPC.submit, {
    p_full_name: parsed.data.full_name,
    p_birth_date: parsed.data.birth_date,
    p_minecraft_nick: parsed.data.nickname,
    p_platform: parsed.data.platform,
    p_goal: parsed.data.goal || null,
    p_about: parsed.data.about || null,
    p_discovery_source: parsed.data.discovery_source,
  });

  if (error) {
    return redirectBack(request, {
      error: ERROR_MESSAGES[error.message] ?? "Не удалось отправить заявку. Попробуйте ещё раз.",
    });
  }

  return redirectBack(request, { submitted: "1" });
}
