import Link from "next/link";
import { getCurrentUser } from "@/lib/auth";
import { Icon } from "@/components/Icon";
import { NavLink } from "@/components/NavLink";
import { PrismMark } from "@/components/PrismMark";
import { getPublicModuleAvailability } from "@/lib/modules";

const NAV = [
  ["/", "Главная", null],
  ["/server", "О сервере", "minecraft"],
  ["/community", "Сообщество", null],
  ["/map", "Карта", "map"],
  ["/market", "Рынок", "market"],
  ["/commands", "Команды", "minecraft"],
  ["/news", "Новости", "public-content"],
  ["/events", "События", "events"],
  ["/wiki", "Wiki", "public-content"],
  ["/rules", "Правила", null],
] as const;

export async function SiteHeader() {
  const user = await getCurrentUser();
  const enabledModules = await getPublicModuleAvailability();
  const canAccessCommunity = Boolean(
    user && user.status === "ACCEPTED" && !user.is_banned && user.is_whitelisted,
  );
  const publicNav = [
    ["/apply", "Подать анкету", "applications"],
    ["/wiki", "Wiki", "public-content"],
    ["/rules", "Правила", null],
  ] as const;
  const sourceNav = canAccessCommunity ? NAV : publicNav;
  const nav = sourceNav.filter(([href, , moduleId]) =>
    (!moduleId || enabledModules[moduleId]) &&
    (canAccessCommunity || href === "/apply" || href === "/wiki" || href === "/rules") &&
    (href !== "/market" || canAccessCommunity),
  );
  const displayName = user?.minecraft_nickname || user?.first_name || "Кабинет";

  return (
    <header data-prisma-public-header className="site-public-header sticky top-0 z-40">
      <div className="mx-auto flex min-h-14 max-w-7xl items-center justify-between gap-3 px-3 sm:px-6 lg:px-8">
        <Link href="/" className="ox-brand shrink-0" aria-label="PRISMA — главная">
          <PrismMark />
          Prisma
        </Link>

        <nav className="hidden min-w-0 items-center gap-0.5 md:flex" aria-label="Основная навигация">
          {nav.map(([href, label]) => (
            <NavLink key={href} href={href}>
              {label}
            </NavLink>
          ))}
        </nav>

        <div className="flex items-center gap-1.5">
          {canAccessCommunity ? (
            <>
              <Link
                href="/search"
                aria-label="Поиск"
                className="prisma-glass-control prisma-glass-hover hidden size-9 items-center justify-center rounded-[10px] border text-muted-foreground sm:inline-flex"
              >
                <Icon name="search" size={17} />
              </Link>
              <Link
                href="/app"
                className="prisma-glass-control prisma-glass-hover inline-flex h-9 items-center gap-2 rounded-[10px] border px-2.5 text-sm font-semibold sm:px-3"
              >
                <span className="hidden sm:inline">{displayName}</span>
                <span className="flex size-6 items-center justify-center rounded-full bg-white text-[10px] font-extrabold text-black">
                  {displayName.slice(0, 1).toUpperCase()}
                </span>
              </Link>
            </>
          ) : user ? (
            <Link href="/app" className="ox-btn ox-btn-sm">
              Кабинет
            </Link>
          ) : (
            <Link href="/login" className="ox-btn ox-btn-sm">
              Войти
            </Link>
          )}

          <details className="relative md:hidden">
            <summary className="prisma-glass-control prisma-glass-hover flex size-9 cursor-pointer list-none items-center justify-center rounded-[10px] border text-muted-foreground">
              <span className="sr-only">Открыть меню</span>
              <Icon name="menu" size={19} />
            </summary>
            <div className="site-public-header-menu absolute right-0 top-11 z-50 w-[min(88vw,22rem)] rounded-2xl p-2">
              <nav className="grid gap-1" aria-label="Мобильная навигация">
                {nav.map(([href, label]) => (
                  <NavLink key={href} href={href} className="ox-navlink !px-3.5 !py-3 !text-sm">
                    {label}
                  </NavLink>
                ))}
                {canAccessCommunity ? (
                  <NavLink href="/search" className="ox-navlink !px-3.5 !py-3 !text-sm">
                    Поиск
                  </NavLink>
                ) : null}
              </nav>
            </div>
          </details>
        </div>
      </div>
    </header>
  );
}
