"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { Icon } from "@/components/Icon";
import { ThemeSwitcher } from "@/components/ThemeSwitcher";

type Item = { href: string; label: string; icon: Parameters<typeof Icon>[0]["name"] };
type Group = { id: string; label: string; items: Item[] };

const GROUPS: Group[] = [
  {
    id: "overview",
    label: "Обзор",
    items: [
      { href: "/dashboard", label: "Дашборд", icon: "home" },
      { href: "/dashboard/monitoring", label: "Мониторинг", icon: "monitor" },
      { href: "/dashboard/analytics", label: "Аналитика", icon: "analytics" },
    ],
  },
  {
    id: "people",
    label: "Люди и модерация",
    items: [
      { href: "/dashboard/applications", label: "Заявки", icon: "applications" },
      { href: "/dashboard/onboarding", label: "Онбординг", icon: "compass" },
      { href: "/dashboard/players", label: "Игроки", icon: "players" },
      { href: "/dashboard/reports", label: "Репорты", icon: "reports" },
      { href: "/dashboard/support", label: "Поддержка", icon: "reports" },
      { href: "/dashboard/appeals", label: "Апелляции", icon: "reports" },
      { href: "/dashboard/moderation", label: "Наказания", icon: "moderation" },
    ],
  },
  {
    id: "community",
    label: "Сообщество",
    items: [
      { href: "/dashboard/clans", label: "Кланы", icon: "clans" },
      { href: "/dashboard/events", label: "События", icon: "calendar" },
      { href: "/dashboard/voting", label: "Голосования", icon: "voting" },
      { href: "/dashboard/market", label: "Рынок", icon: "market" },
      { href: "/dashboard/news", label: "Новости", icon: "news" },
    ],
  },
  {
    id: "system",
    label: "Система",
    items: [
      { href: "/dashboard/notifications", label: "Уведомления", icon: "bell" },
      { href: "/dashboard/admins", label: "Персонал", icon: "admins" },
      { href: "/dashboard/security", label: "Безопасность", icon: "security" },
      { href: "/dashboard/audit", label: "Аудит", icon: "audit" },
      { href: "/dashboard/extra", label: "Настройки", icon: "settings" },
      { href: "/dashboard/modules", label: "Модули", icon: "settings" },
    ],
  },
];

function activeFor(pathname: string, href: string) {
  return pathname === href || (href !== "/dashboard" && pathname.startsWith(href + "/"));
}

export function Sidebar({
  collapsed,
  mobileOpen,
  onMobileClose,
}: {
  collapsed: boolean;
  mobileOpen: boolean;
  onMobileClose: () => void;
}) {
  const pathname = usePathname() || "/dashboard";
  const activeGroupId = GROUPS.find((group) => group.items.some((item) => activeFor(pathname, item.href)))?.id ?? "overview";
  const [openGroup, setOpenGroup] = useState("overview");

  useEffect(() => {
    if (activeGroupId !== "community") setOpenGroup(activeGroupId);
  }, [activeGroupId]);

  return (
    <aside
      className={[
        "prisma-glass-surface fixed inset-y-0 left-0 z-50 flex h-svh shrink-0 flex-col rounded-none border-l-0 border-y-0 text-[#f5f7f8] transition-[width,transform] duration-200 md:sticky md:top-0 md:z-20 md:translate-x-0",
        collapsed ? "md:w-16" : "md:w-64",
        mobileOpen ? "w-64 translate-x-0" : "w-64 -translate-x-full md:translate-x-0",
      ].join(" ")}
    >
      <div className="flex h-14 shrink-0 items-center border-b px-3">
        <Link
          href="/dashboard"
          onClick={onMobileClose}
          aria-label="PRISMA — Дашборд"
          className={[
            "prisma-glass-hover flex min-w-0 items-center gap-2.5 rounded-md px-2 py-1.5 transition-colors",
            collapsed ? "md:justify-center md:px-1" : "",
          ].join(" ")}
        >
          <span className="flex size-8 shrink-0 items-center justify-center rounded-md bg-brand text-xs font-bold text-primary-foreground">
            P
          </span>
          <span className={collapsed ? "md:hidden" : ""}>
            <span className="block text-sm font-semibold leading-none">PRISMA</span>
            <span className="mt-1 block text-[10px] text-white/[0.42]">Панель управления</span>
          </span>
        </Link>
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto px-2 py-3" aria-label="Навигация панели">
        {GROUPS.map((group) => {
          const active = group.items.some((item) => activeFor(pathname, item.href));
          const open = openGroup === group.id;

          return (
            <section key={group.id} className="mb-3">
              <button
                type="button"
                aria-expanded={open}
                aria-controls={`admin-nav-${group.id}`}
                onClick={() => setOpenGroup((current) => (current === group.id ? "" : group.id))}
                className={[
                  "prisma-glass-hover mb-1 flex h-8 w-full items-center rounded-md px-2.5 text-[10px] font-medium uppercase tracking-[0.14em] text-white/55 transition-colors",
                  collapsed ? "md:justify-center md:px-0" : "justify-between",
                  active ? "text-primary" : "text-white/[0.55]",
                  ""
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
                id={`admin-nav-${group.id}`}
                hidden={!open}
                className={collapsed ? "space-y-0.5 md:hidden" : "space-y-0.5"}
              >
                {group.items.map((item) => {
                  const activeItem = activeFor(pathname, item.href);
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      onClick={onMobileClose}
                      aria-current={activeItem ? "page" : undefined}
                      title={collapsed ? item.label : undefined}
                      className={[
                        "group flex h-9 items-center gap-2.5 rounded-md px-2.5 text-sm transition-colors",
                        collapsed ? "md:justify-center md:px-0" : "",
                        activeItem
                          ? "bg-primary/14 font-medium text-primary"
                          : "text-white/[0.68] hover:bg-white/[0.07] hover:text-white",
                      ].join(" ")}
                    >
                      <Icon name={item.icon} size={16} />
                      <span className={collapsed ? "md:hidden" : "truncate"}>{item.label}</span>
                      {activeItem && !collapsed ? <span className="ml-auto size-1.5 rounded-full bg-brand" /> : null}
                    </Link>
                  );
                })}
              </div>
            </section>
          );
        })}
      </nav>

      <div className="shrink-0 border-t p-2">
        <div className={collapsed ? "flex justify-center" : "flex items-center justify-between gap-2"}>
          {!collapsed ? <span className="px-2 text-xs text-white/[0.5]">Тема</span> : null}
          <ThemeSwitcher compact />
        </div>
        <form action="/admin/api/auth/logout" method="post" className="mt-1">
          <button
            type="submit"
            title={collapsed ? "Выйти" : undefined}
            className={[
              "prisma-glass-hover flex h-9 w-full items-center rounded-md text-sm text-muted-foreground transition-colors hover:text-foreground",
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
