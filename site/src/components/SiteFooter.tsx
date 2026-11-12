import Link from "next/link";
import { PrismMark } from "@/components/PrismMark";
import { getCurrentUser } from "@/lib/auth";
import { getPublicModuleAvailability } from "@/lib/modules";

/* Members can open all of these; guests are limited to Wiki, the application and login (see lib/supabase/proxy.ts). */
const MEMBER_LINKS = [
  ["/wiki", "Wiki", "public-content"],
  ["/news", "Новости", "public-content"],
  ["/rules", "Правила", null],
  ["/faq", "FAQ", null],
  ["/guide", "Гайд новичка", null],
  ["/status", "Состояние", null],
] as const;

export async function SiteFooter() {
  const [user, enabledModules] = await Promise.all([getCurrentUser(), getPublicModuleAvailability()]);
  const isMember = Boolean(user && user.status === "ACCEPTED" && !user.is_banned && user.is_whitelisted);

  const links: Array<readonly [string, string]> = isMember
    ? MEMBER_LINKS.filter(([, , moduleId]) => !moduleId || enabledModules[moduleId]).map(
        ([href, label]) => [href, label] as const,
      )
    : [
        ...(enabledModules["public-content"] ? ([["/wiki", "Wiki"]] as const) : []),
        ["/rules", "Правила"] as const,
        ["/status", "Состояние"] as const,
        ...(enabledModules.applications ? ([["/apply", "Подать анкету"]] as const) : []),
        ...(user ? ([["/app", "Кабинет"]] as const) : ([["/login", "Войти"]] as const)),
      ];

  return (
    <footer className="relative z-10 border-t border-white/10 bg-[#030305]/80">
      <div className="mx-auto flex max-w-7xl flex-col gap-6 px-4 py-10 sm:px-6 md:flex-row md:items-center md:justify-between lg:px-8">
        <div className="grid gap-2">
          <Link href="/" className="ox-brand" aria-label="PRISMA — главная">
            <PrismMark />
            Prisma
          </Link>
          <p className="max-w-sm text-sm leading-6 text-muted-foreground">
            Сообщество Minecraft. Один луч, много цветов.
          </p>
        </div>

        <nav aria-label="Ссылки в подвале" className="flex flex-wrap gap-x-5 gap-y-2">
          {links.map(([href, label]) => (
            <Link
              key={href}
              href={href}
              className="text-sm font-semibold text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
            >
              {label}
            </Link>
          ))}
        </nav>
      </div>
    </footer>
  );
}
