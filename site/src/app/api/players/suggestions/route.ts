import { NextResponse } from "next/server";
import { getCurrentUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_READ_RPC } from "@prisma-eco/contracts";

export async function GET(request: Request) {
  const user = await getCurrentUser();

  if (!user) {
    return NextResponse.json({ players: [] }, { status: 401 });
  }

  const url = new URL(request.url);
  const query = url.searchParams.get("q")?.trim() ?? "";

  if (!query || query.length > 32) {
    return NextResponse.json({ players: [] }, { status: 200 });
  }

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_READ_RPC.searchPlayers, {
    p_query: query,
    p_limit: 8,
  });

  if (error || !Array.isArray(data)) {
    return NextResponse.json({ players: [] }, { status: 200 });
  }

  const ownNickname = user.minecraft_nickname?.trim().toLowerCase();

  const players = data
    .filter((player: any) => {
      const nickname = String(player?.minecraft_nickname ?? "").trim();
      return nickname && nickname.toLowerCase() !== ownNickname;
    })
    .slice(0, 8)
    .map((player: any) => ({
      id: String(player.id),
      minecraft_nickname: String(player.minecraft_nickname),
      platform: player.platform === "BEDROCK" ? "BEDROCK" : "JAVA",
      rating: Number(player.rating ?? 0),
      activity_score: Number(player.activity_score ?? 0),
    }));

  return NextResponse.json(
    { players },
    {
      status: 200,
      headers: {
        "Cache-Control": "private, max-age=15, stale-while-revalidate=30",
      },
    },
  );
}
