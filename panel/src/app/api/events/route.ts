import { NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

const DateField = z
  .string()
  .trim()
  .optional()
  .nullable()
  .transform((value) => (value ? new Date(value).toISOString() : null));

const EventSchema = z.object({
  slug: z.string().trim().min(2).max(120).regex(/^[a-z0-9][a-z0-9._-]*$/),
  title: z.string().trim().min(2).max(160),
  description: z.string().trim().max(5000).default(""),
  status: z.enum(["draft", "scheduled", "live", "finished", "cancelled"]),
  starts_at: DateField,
  ends_at: DateField,
  registration_deadline: DateField,
  max_participants: z.coerce.number().int().min(1).optional().nullable(),
});

const ResultSchema = z.object({
  event_id: z.string().uuid(),
  user_id: z.string().uuid(),
  score: z.coerce.number().int().min(0),
  placement: z.coerce.number().int().min(1).optional().nullable(),
});

function errorMessage(message: string) {
  const map: Record<string, string> = {
    ADMIN_PROFILE_NOT_LINKED: "Профиль администратора не связан с PRISMA.",
    FORBIDDEN: "Нет права управлять событиями.",
    EVENT_NOT_FOUND: "Событие не найдено.",
    INVALID_SLUG: "Slug должен содержать 2–120 символов: a-z, 0-9, точка, дефис или подчёркивание.",
    INVALID_TITLE: "Название: 2–160 символов.",
    INVALID_DESCRIPTION: "Описание не должно превышать 5000 символов.",
    INVALID_STATUS: "Некорректный статус события.",
    INVALID_MAX_PARTICIPANTS: "Максимальное число участников должно быть больше нуля.",
    INVALID_DATES: "Дата окончания должна быть позже даты начала.",
    INVALID_REGISTRATION_DEADLINE: "Дедлайн регистрации не может быть позже начала события.",
    TARGET_REQUIRED: "Не указан участник или событие.",
    PLAYER_NOT_FOUND: "Игрок не найден.",
    PLAYER_NOT_REGISTERED: "Игрок не зарегистрирован на это событие.",
    INVALID_SCORE: "Результат не может быть отрицательным.",
    INVALID_PLACEMENT: "Место должно быть положительным числом.",
    EVENT_ALREADY_FINISHED: "Завершённое событие нельзя отменить.",
    INVALID_STATUS_TRANSITION: "Недопустимый переход между статусами события.",
    MAX_BELOW_CURRENT_PARTICIPANTS: "Лимит нельзя уменьшить ниже текущего числа участников.",
  };
  return map[message] ?? "Не удалось выполнить действие с событием.";
}

async function staffRpc(action: string, args: Record<string, unknown>) {
  const supabase = await createSupabaseServerClient();
  return supabase.rpc(STAFF_RPC.manageEvent, { p_action: action, ...args });
}

export async function POST(request: Request) {
  const admin = await requireAdminContext("event.manage");
  if (!admin) return NextResponse.json({ error: "Нет права управлять событиями." }, { status: 403 });

  const parsed = EventSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Некорректные данные события." }, { status: 400 });

  const { data, error } = await staffRpc("CREATE", {
    p_event_id: null,
    p_slug: parsed.data.slug,
    p_title: parsed.data.title,
    p_description: parsed.data.description,
    p_status: parsed.data.status,
    p_starts_at: parsed.data.starts_at,
    p_ends_at: parsed.data.ends_at,
    p_registration_deadline: parsed.data.registration_deadline,
    p_max_participants: parsed.data.max_participants ?? null,
    p_reward_config: {},
  });

  if (error) return NextResponse.json({ error: errorMessage(error.message) }, { status: 409 });
  return NextResponse.json({ ok: true, result: Array.isArray(data) ? data[0] : data }, { status: 201 });
}

export async function PATCH(request: Request) {
  const admin = await requireAdminContext("event.manage");
  if (!admin) return NextResponse.json({ error: "Нет права управлять событиями." }, { status: 403 });

  const body = await request.json().catch(() => ({}));
  const eventId = z.string().uuid().safeParse(body.event_id);
  if (!eventId.success) return NextResponse.json({ error: "Некорректный ID события." }, { status: 400 });

  const parsed = EventSchema.partial().safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: "Некорректные данные события." }, { status: 400 });

  const { data, error } = await staffRpc("UPDATE", {
    p_event_id: eventId.data,
    p_slug: parsed.data.slug ?? null,
    p_title: parsed.data.title ?? null,
    p_description: parsed.data.description ?? null,
    p_status: parsed.data.status ?? null,
    p_starts_at: parsed.data.starts_at ?? null,
    p_ends_at: parsed.data.ends_at ?? null,
    p_registration_deadline: parsed.data.registration_deadline ?? null,
    p_max_participants: parsed.data.max_participants ?? null,
    p_reward_config: null,
    p_clear_description: Object.prototype.hasOwnProperty.call(body, "description") && body.description === null,
    p_clear_starts_at: Object.prototype.hasOwnProperty.call(body, "starts_at") && body.starts_at === null,
    p_clear_ends_at: Object.prototype.hasOwnProperty.call(body, "ends_at") && body.ends_at === null,
    p_clear_registration_deadline:
      Object.prototype.hasOwnProperty.call(body, "registration_deadline") && body.registration_deadline === null,
    p_clear_max_participants:
      Object.prototype.hasOwnProperty.call(body, "max_participants") && body.max_participants === null,
  });

  if (error) return NextResponse.json({ error: errorMessage(error.message) }, { status: 409 });
  return NextResponse.json({ ok: true, result: Array.isArray(data) ? data[0] : data });
}

export async function DELETE(request: Request) {
  const admin = await requireAdminContext("event.manage");
  if (!admin) return NextResponse.json({ error: "Нет права управлять событиями." }, { status: 403 });

  const body = await request.json().catch(() => ({}));
  const eventId = z.string().uuid().safeParse(body.event_id);
  if (!eventId.success) return NextResponse.json({ error: "Некорректный ID события." }, { status: 400 });

  const { data, error } = await staffRpc("CANCEL", {
    p_event_id: eventId.data,
  });

  if (error) return NextResponse.json({ error: errorMessage(error.message) }, { status: 409 });
  return NextResponse.json({ ok: true, result: Array.isArray(data) ? data[0] : data });
}

export async function PUT(request: Request) {
  const admin = await requireAdminContext("event.manage");
  if (!admin) return NextResponse.json({ error: "Нет права управлять событиями." }, { status: 403 });

  const parsed = ResultSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Некорректный результат." }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.setEventResult, {
    p_event_id: parsed.data.event_id,
    p_user_id: parsed.data.user_id,
    p_score: parsed.data.score,
    p_placement: parsed.data.placement ?? null,
  });

  if (error) return NextResponse.json({ error: errorMessage(error.message) }, { status: 409 });
  return NextResponse.json({ ok: true, result: Array.isArray(data) ? data[0] : data });
}
