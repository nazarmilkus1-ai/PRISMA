import { NextResponse } from "next/server";
import { getPublicWiki } from "@/lib/data";

export const dynamic = "force-dynamic";

export async function GET() {
  const pages = await getPublicWiki();
  return NextResponse.json(
    {
      name: "PRISMA Wiki",
      description: "Публичная документация Minecraft-сообщества PRISMA.",
      source: "/wiki",
      pages: pages.map((page: any) => ({
        title: page.title,
        slug: page.slug,
        category: page.category,
        excerpt: page.excerpt,
        content: page.content,
        url: "/wiki/" + page.slug,
      })),
    },
    {
      headers: {
        "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600",
      },
    },
  );
}
