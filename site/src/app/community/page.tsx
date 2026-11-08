import Link from "next/link";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@prisma-eco/ui";
import { getPublicModuleAvailability } from "@/lib/modules";
import { getCurrentUser } from "@/lib/auth";

export const metadata = { title: "Сообщество" };

export default async function CommunityPage() {
  const [modules, user] = await Promise.all([getPublicModuleAvailability(), getCurrentUser()]);
  const canUseMarket = Boolean(user && user.status === "ACCEPTED" && !user.is_banned && user.is_whitelisted);

  const cards = [
    modules["public-content"] ? {
      href: "/news",
      title: "Новости",
      description: "Официальные публикации и обновления PRISMA.",
    } : null,
    modules.events ? {
      href: "/events",
      title: "События",
      description: "Игровые активности и события сообщества.",
    } : null,
    modules.market && canUseMarket ? {
      href: "/market",
      title: "Рынок",
      description: "Объявления и обмен предложениями между участниками.",
    } : null,
    modules.map ? {
      href: "/map",
      title: "Карта",
      description: "Мир PRISMA, территории и публичные точки.",
    } : null,
    modules["public-content"] ? {
      href: "/wiki",
      title: "Wiki",
      description: "Правила, системы и документация PRISMA.",
    } : null,
    {
      href: "/rules",
      title: "Правила",
      description: "Основные правила проекта и сообщества.",
    },
  ].filter(Boolean) as { href: string; title: string; description: string }[];

  return (
    <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
      <div className="max-w-3xl">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-muted-foreground">COMMUNITY</p>
        <h1 className="mt-3 text-4xl font-semibold tracking-[-0.04em] sm:text-5xl">Сообщество PRISMA</h1>
        <p className="mt-4 max-w-2xl text-base leading-7 text-muted-foreground sm:text-lg">
          Единое пространство PRISMA для игроков: Minecraft, события, рынок, карта, новости и документация.
        </p>
      </div>

      <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {cards.map((card) => (
          <Link key={card.href} href={card.href} className="group">
            <Card className="h-full transition hover:-translate-y-0.5 prisma-glass-hover">
              <CardHeader>
                <CardTitle className="group-hover:text-primary">{card.title}</CardTitle>
                <CardDescription>{card.description}</CardDescription>
              </CardHeader>
            </Card>
          </Link>
        ))}
      </div>

      <Card className="mt-6">
        <CardContent className="flex flex-col gap-4 p-6 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="font-semibold">Кабинет участника</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Профиль, уведомления, кланы, рейтинги, поддержка и другие функции доступны после входа.
            </p>
          </div>
          <Link
            href="/login"
            className="prisma-glass-control prisma-glass-hover inline-flex h-10 shrink-0 items-center justify-center rounded-md border px-4 text-sm font-medium"
          >
            Войти в PRISMA →
          </Link>
        </CardContent>
      </Card>
    </div>
  );
}
