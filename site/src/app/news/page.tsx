import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Card, CardDescription, CardHeader, CardTitle } from "@prisma-eco/ui";
import { getPublicNews } from "@/lib/data";

export const metadata = { title: "Новости" };

export default async function NewsPage() {
  await requireModule("public-content");
  const news = await getPublicNews(50);

  return (
    <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
      <header>
        <p className="text-xs font-medium uppercase tracking-[0.16em] text-muted-foreground">PRISMA NEWS</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight">Новости</h1>
        <p className="mt-2 text-sm leading-6 text-muted-foreground">
          Последние изменения, объявления и важные события PRISMA.
        </p>
      </header>

      <div className="mt-8 space-y-3">
        {news.map((item: any) => (
          <Link key={item.id} href={"/news/" + item.id} className="block">
            <Card className="transition-colors prisma-glass-hover">
              <CardHeader>
                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <span>{item.kind === "UPDATE" ? "ОБНОВЛЕНИЕ" : "НОВОСТЬ"}</span>
                  <span aria-hidden>·</span>
                  <span>{new Date(item.published_at || item.created_at).toLocaleDateString("ru-RU")}</span>
                </div>
                <CardTitle className="text-lg">{item.title}</CardTitle>
                <CardDescription className="line-clamp-3 leading-6">{item.body}</CardDescription>
              </CardHeader>
            </Card>
          </Link>
        ))}
        {!news.length ? (
          <Card className="p-10 text-center">
            <p className="font-medium">Новостей пока нет</p>
            <p className="mt-1 text-sm text-muted-foreground">Новые публикации появятся здесь.</p>
          </Card>
        ) : null}
      </div>
    </div>
  );
}
