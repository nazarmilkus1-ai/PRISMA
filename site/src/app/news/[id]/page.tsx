import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Card, CardContent, Badge } from "@prisma-eco/ui";
import { PUBLIC_RPC } from "@prisma-eco/contracts";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PUBLIC_RPC.news, { p_limit: 100 });
  if (error || !Array.isArray(data)) return { title: "Новость" };
  const item = data.find((row: any) => row?.id === id);
  return { title: item?.title || "Новость" };
}

export default async function NewsDetailPage({ params }: { params: Promise<{ id: string }> }) {
  await requireModule("public-content");
  const { id } = await params;
  const db = await createSupabaseServerClient();
  const { data: rows, error } = await db.rpc(PUBLIC_RPC.news, { p_limit: 100 });
  if (error || !Array.isArray(rows)) notFound();
  const item = rows.find((row: any) => row?.id === id);
  if (!item) notFound();
  const article = item;

  return (
    <article className="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
      <Link href="/news" className="prisma-glass-control prisma-glass-hover inline-flex rounded-lg border px-3 py-1.5 text-xs text-muted-foreground">← Все новости</Link>
      <Card className="mt-4 overflow-hidden">
        <div className="border-b px-6 py-5 sm:px-10">
          <Badge variant="secondary">{article.kind === "UPDATE" ? "Обновление" : "Новость"}</Badge>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">{article.title}</h1>
          <p className="mt-2 text-xs text-muted-foreground">{new Date(article.published_at || article.created_at).toLocaleDateString("ru-RU")}</p>
        </div>
        <CardContent className="px-6 py-8 sm:px-10">
          <div className="whitespace-pre-wrap text-sm leading-7 text-foreground">{article.body}</div>
        </CardContent>
      </Card>
    </article>
  );
}
