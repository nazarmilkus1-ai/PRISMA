import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { STAFF_RPC } from "@prisma-eco/contracts";

const ActionSchema = z.enum(["off", "warn", "mute", "ban"]);

export async function GET() {
  const context = await requireAdminContext("settings.view");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.chatSettings);

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить настройки чата.") }, { status: 409 });
  return NextResponse.json({ chats: Array.isArray(data) ? data : [] });
}

const SettingsSchema = z.object({
  chat_id: z.coerce.bigint(),
  anti_links: z.boolean(),
  anti_caps: z.boolean(),
  anti_flood: z.boolean(),
  anti_media: z.boolean(),
  anti_profanity: z.boolean(),
  anti_mentions: z.boolean().optional(),
  anti_raid: z.boolean().optional(),
  caps_threshold: z.coerce.number().int().min(50).max(100).optional(),
  flood_messages: z.coerce.number().int().min(2).max(30).optional(),
  flood_window_seconds: z.coerce.number().int().min(2).max(60).optional(),
  links_action: ActionSchema.optional(),
  caps_action: ActionSchema.optional(),
  flood_action: ActionSchema.optional(),
  profanity_action: ActionSchema.optional(),
  media_action: ActionSchema.optional(),
  repeat_warn_action: ActionSchema.optional(),
});

export async function POST(request: Request) {
  const context = await requireAdminContext("settings.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = SettingsSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { chat_id, ...toggles } = parsed.data;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageChatSettings, {
    p_chat_id: chat_id.toString(),
    p_anti_links: toggles.anti_links,
    p_anti_caps: toggles.anti_caps,
    p_anti_flood: toggles.anti_flood,
    p_anti_media: toggles.anti_media,
    p_anti_profanity: toggles.anti_profanity,
    p_anti_mentions: toggles.anti_mentions ?? false,
    p_anti_raid: toggles.anti_raid ?? false,
    p_caps_threshold: toggles.caps_threshold ?? 70,
    p_flood_messages: toggles.flood_messages ?? 5,
    p_flood_window_seconds: toggles.flood_window_seconds ?? 8,
    p_links_action: toggles.links_action ?? "warn",
    p_caps_action: toggles.caps_action ?? "warn",
    p_flood_action: toggles.flood_action ?? "mute",
    p_profanity_action: toggles.profanity_action ?? "warn",
    p_media_action: toggles.media_action ?? "off",
    p_repeat_warn_action: toggles.repeat_warn_action ?? "mute",
  });
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить настройки чата.") }, { status: 409 });
  return NextResponse.json(data);
}

export async function DELETE(request: Request) {
  const context = await requireAdminContext("settings.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = z.object({ chat_id: z.coerce.bigint() }).safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "invalid chat id" }, { status: 400 });

  const chatId = parsed.data.chat_id.toString();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.deleteChatSettings, { p_chat_id: chatId });
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить настройки чата.") }, { status: 409 });
  return NextResponse.json(data);
}
