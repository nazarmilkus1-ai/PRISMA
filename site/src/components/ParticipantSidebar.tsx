"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { Icon, type IconName } from "@/components/Icon";
import { PrismMark } from "@/components/PrismMark";
import type { ModuleEnabledMap, ModuleId } from "@prisma-eco/contracts";

type Item = { href: string; label: string; icon: IconName; moduleId?: ModuleId };
type Group = { id: string; label: string; items: Item[] };

const GROUPS: Group[] = [
  {
    id: "overview",
    label: "Обзор",
    items: [{ href: "/app", label: "Главная", icon: "home" }],
  },
  {
    id: "minecraft",
    label: "Minecraft",
    items: [
      { href: "/app/server", label: "Сервер", icon: "server", moduleId: "minecraft" },
      { href: "/app/map", label: "Карта", icon: "map", moduleId: "map" },
      { href: "/app/minecraft", label: "Моя статистика", icon: "activity", moduleId: "minecraft" },
      { href: "/app/commands", label: "Команди PRISMA", icon: "wiki", moduleId: "minecraft" },
      { href: "/app/history", label: "Аналитика", icon: "activity", moduleId: "analytics" },
    ],
  },
  {
    id: "community",
    label: "Сообщество",
    items: [
      { href: "/app/players", label: "Игроки", icon: "players", moduleId: "players" },
      { href: "/app/rankings", label: "Рейтинги", icon: "ranking", moduleId: "players" },
      { href: "/app/clan", label: "Кланы", icon: "clans", moduleId: "clans" },
      { href: "/app/events", label: "События", icon: "calendar", moduleId: "events" },
      { href: "/app/calendar", label: "Календарь", icon: "calendar", moduleId: "events" },
      { href: "/app/market", label: "Рынок", icon: "market", moduleId: "market" },
      { href: "/app/news", label: "Новости", icon: "news", moduleId: "public-content" },
      { href: "/app/wiki", label: "Wiki", icon: "wiki", moduleId: "public-content" },
    ],
  },
  {
    id: "interaction",
    label: "Взаимодействие",
    items: [
      { href: "/app/battles", label: "Player Battle", icon: "battle", moduleId: "battles" },
      { href: "/app/voting", label: "Голосования", icon: "voting", moduleId: "voting" },
      { href: "/app/reports", label: "Репорты", icon: "reports", moduleId: "reports" },
      { href: "/app/support", label: "Поддержка", icon: "reports" },
      { href: "/app/appeals", label: "Апелляции", icon: "reports", moduleId: "appeals" },
    ],
  },
  {
    id: "profile",
    label: "Профиль",
    items: [
      { href: "/app/profile", label: "Профиль", icon: "profile", moduleId: "players" },
      { href: "/app/application", label: "Моя заявка", icon: "applications", moduleId: "applications" },
    ],
  },
  {
    id: "system",
    label: "Система",
    items: [
      { href: "/app/notifications", label: "Уведомления", icon: "bell", moduleId: "notifications" },
      { href: "/app/settings", label: "Настройки", icon: "settings" },
    ],
  },
];

function activeFor(pathname: string, href: string) {
  return pathname === href || (href !== "/app" && pathname.startsWith(href + "/"));
}

export function ParticipantSidebar({
  collapsed,
  mobileOpen,
  onMobileClose,
  notificationsCount = 0,
  enabledModules,
  canUseMarket,
}: {
  collapsed: boolean;
  mobileOpen: boolean;
  onMobileClose: () => void;
  notificationsCount?: number;
  enabledModules: ModuleEnabledMap;
  canUseMarket: boolean;
}) {
  const pathname = usePathname() || "/app";
  const visibleGroups = GROUPS
    .map((group) => ({
      ...group,
      items: group.items.filter((item) =>
        (!item.moduleId || enabledModules[item.moduleId] === true) &&
        (item.href !== "/app/market" || canUseMarket),
      ),
    }))
    .filter((group) => group.items.length > 0);
  const activeGroupId = visibleGroups.find((group) => group.items.some((item) => activeFor(pathname, item.href)))?.id ?? "overview";
  const [openGroup, setOpenGroup] = useState("overview");

  useEffect(() => {
    if (pathname !== "/app") {
      setOpenGroup(activeGroupId);
    }
  }, [activeGroupId, pathname]);

  return (
    <aside
      className={[
        "site-participant-sidebar fixed inset-y-0 left-0 z-50 flex h-svh shrink-0 flex-col border-r text-[#f5f7f8] transition-[width,transform] duration-200 md:sticky md:top-0 md:z-20 md:translate-x-0",
        collapsed ? "md:w-16" : "md:w-64",
        mobileOpen ? "w-64 translate-x-0" : "w-64 -translate-x-full md:translate-x-0",
      ].join(" ")}
    >
      <div className="flex h-14 shrink-0 items-center border-b px-3">
        <Link
          href="/app"
          onClick={onMobileClose}
          aria-label="PRISMA — Главная"
          className={[
            "flex min-w-0 items-center gap-2.5 rounded-md px-2 py-1.5",
            collapsed ? "md:justify-center md:px-1" : "",
          ].join(" ")}
        >
          <span className="flex size-8 shrink-0 items-center justify-center rounded-md bg-primary text-primary-foreground">
            <PrismMark size={16} />
          </span>
          <span className={collapsed ? "md:hidden" : ""}>
            <span className="block text-sm font-semibold leading-none">PRISMA</span>
            <span className="mt-1 block text-[10px] text-muted-foreground">Личный кабинет</span>
          </span>
        </Link>
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto px-2 py-4" aria-label="Навигация кабинета">
        {visibleGroups.map((group) => {
          const active = group.items.some((item) => activeFor(pathname, item.href));
          const open = openGroup === group.id;

          return (
            <section key={group.id} className="mb-3">
              <button
                type="button"
                aria-expanded={open}
                aria-controls={`participant-nav-${group.id}`}
                onClick={() => setOpenGroup((current) => (current === group.id ? "" : group.id))}
                className={[
                  "mb-1 flex h-8 w-full items-center rounded-md px-2.5 text-[10px] font-medium uppercase tracking-[0.14em] transition-colors",
                  collapsed ? "md:justify-center md:px-0" : "justify-between",
                  active ? "text-primary" : "text-muted-foreground",
                  "hover:bg-accent hover:text-foreground",
                ].join(" ")}
              >
                <span className={collapsed ? "md:hidden" : ""}>{group.label}</span>
                <Icon
                  name="chevron-right"
                  size={13}
                  className={[
                    "transition-transform duration-150",
                    open ? "rotate-90" : "",
                    collapsed ? "md:rotate-0" : "",
                  ].join(" ")}
                />
              </button>

              <div
                id={`participant-nav-${group.id}`}
                hidden={!open}
                className={collapsed ? "space-y-0.5 md:hidden" : "space-y-0.5"}
              >
                {group.items.map((item) => {
                  const itemActive = activeFor(pathname, item.href);
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      onClick={onMobileClose}
                      aria-current={itemActive ? "page" : undefined}
                      title={collapsed ? item.label : undefined}
                      className={[
                        "group relative flex h-9 items-center gap-2.5 rounded-md px-2.5 text-sm transition-colors",
                        collapsed ? "md:justify-center md:px-0" : "",
                        itemActive
                          ? "bg-primary/14 font-medium text-primary"
                          : "text-muted-foreground hover:bg-accent hover:text-foreground",
                      ].join(" ")}
                    >
                      <Icon name={item.icon} size={16} />
                      <span className={collapsed ? "md:hidden" : "truncate"}>{item.label}</span>
                      {item.href === "/app/notifications" && notificationsCount > 0 && !collapsed ? (
                        <span className="ml-auto min-w-5 rounded-full bg-primary px-1.5 py-0.5 text-center text-[10px] font-bold leading-none text-primary-foreground">
                          {notificationsCount > 99 ? "99+" : notificationsCount}
                        </span>
                      ) : null}
                      {itemActive && !collapsed && item.href !== "/app/notifications" ? (
                        <span className="ml-auto size-1.5 rounded-full bg-primary" aria-hidden />
                      ) : null}
                    </Link>
                  );
                })}
              </div>
            </section>
          );
        })}
      </nav>

      <div className="shrink-0 border-t p-2">
        <Link
          href="/"
          onClick={onMobileClose}
          className={[
            "mt-0.5 flex h-9 w-full items-center rounded-md text-sm text-muted-foreground hover:bg-accent hover:text-foreground",
            collapsed ? "justify-center px-0" : "px-2.5",
          ].join(" ")}
          title={collapsed ? "Публичный сайт" : undefined}
        >
          <Icon name="globe" size={16} />
          <span className={collapsed ? "md:hidden" : "ml-2"}>Публичный сайт</span>
        </Link>

        <form action="/api/auth/logout" method="post" className="mt-0.5">
          <button
            type="submit"
            title={collapsed ? "Выйти" : undefined}
            className={[
              "flex h-9 w-full items-center rounded-md text-sm text-muted-foreground hover:bg-accent hover:text-foreground",
              collapsed ? "justify-center px-0" : "px-2.5",
            ].join(" ")}
          >
            <Icon name="logout" size={16} />
            <span className={collapsed ? "md:hidden" : "ml-2"}>Выйти</span>
          </button>
        </form>
      </div>
    </aside>
  );
}