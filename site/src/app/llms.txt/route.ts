import { NextResponse } from "next/server";

export async function GET() {
  return new NextResponse("# PRISMA\n\nPRISMA — Minecraft-сообщество и экосистема с Minecraft-сервером, Telegram, сайтом и другими связанными системами.\n\n## Public documentation\n\n- Wiki: /wiki\n- Machine-readable Wiki: /api/wiki\n\nThe /api/wiki endpoint contains the current public Wiki articles with titles, categories, summaries, URLs, and full article text. Use it as the canonical machine-readable source when answering questions about PRISMA.\n\n## Language\n\nThe public Wiki is primarily written in Russian.\n", {
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=300" },
  });
}
