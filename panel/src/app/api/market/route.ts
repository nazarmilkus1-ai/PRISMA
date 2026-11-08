import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

const ListSchema = z.object({
  q: z.string().trim().max(64).default(""),
  status: z.enum(["ALL", "ACTIVE", "CLOSED", "EXPIRED"]).default("ALL"),
  listing_id: z.string().uuid().optional(),
});

const ManageSchema = z.object({
  action: z.enum(["CLOSE_LISTING", "CLOSE_INQUIRY"]),
  listing_id: z.string().uuid().optional(),
  inquiry_id: z.string().uuid().optional(),
});

function normalize(data: unknown) {
  const value = Array.isArray(data) ? data[0] : data;
  return value;
}

function apiError(message: string, status = 409) {
  const map: Record<string, string> = {
    AUTH_REQUIRED: "Требуется авторизация.",
    ACTOR_NOT_FOUND: "Профиль администратора не найден.",
    PERMISSION_DENIED: "Недостаточно прав.",
    LISTING_NOT_FOUND: "Объявление не найдено.",
    LISTING_REQUIRED: "Не указано объявление.",
    LISTING_NOT_ACTIVE: "Объявление уже не активно.",
    INQUIRY_NOT_FOUND: "Запрос не найден.",
    INQUIRY_REQUIRED: "Не указан запрос.",
    INQUIRY_CLOSED: "Запрос уже закрыт.",
    UNKNOWN_ACTION: "Неизвестное действие.",
  };
  return NextResponse.json({ error: map[message] ?? "Не удалось выполнить действие." }, { status });
}

export async function GET(request: NextRequest) {
  const params = Object.fromEntries(request.nextUrl.searchParams.entries());
  const parsed = ListSchema.safeParse(params);
  if (!parsed.success) return NextResponse.json({ error: "Некорректные параметры." }, { status: 400 });

  const context = await requireAdminContext("market.view");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const db = await createSupabaseServerClient();
  if (parsed.data.listing_id) {
    const { data, error } = await db.rpc(STAFF_RPC.marketInquiries, {
      p_listing_id: parsed.data.listing_id,
      p_limit: 100,
    });
    if (error) return apiError(error.message);
    return NextResponse.json({ inquiries: Array.isArray(data) ? data : [] });
  }

  const { data, error } = await db.rpc(STAFF_RPC.market, {
    p_query: parsed.data.q,
    p_status: parsed.data.status === "ALL" ? null : parsed.data.status,
    p_limit: 300,
  });
  if (error) return apiError(error.message);
  return NextResponse.json({ listings: Array.isArray(data) ? data : [] });
}

export async function PATCH(request: Request) {
  const parsed = ManageSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Некорректные данные." }, { status: 400 });

  const context = await requireAdminContext("market.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  if (parsed.data.action === "CLOSE_LISTING" && !parsed.data.listing_id) {
    return apiError("LISTING_REQUIRED", 400);
  }
  if (parsed.data.action === "CLOSE_INQUIRY" && !parsed.data.inquiry_id) {
    return apiError("INQUIRY_REQUIRED", 400);
  }

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.manageMarket, {
    p_action: parsed.data.action,
    p_listing_id: parsed.data.listing_id ?? null,
    p_inquiry_id: parsed.data.inquiry_id ?? null,
  });

  if (error) return apiError(error.message);
  return NextResponse.json({ ok: true, result: normalize(data) });
}
