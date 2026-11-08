"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon } from "@/components/Icon";
import { ThemeSwitcher } from "@/components/ThemeSwitcher";

const LABELS: Record<string, string> = {
  dashboard: "Обзор", applications: "Заявки", onboarding: "Онбординг", players: "Игроки",
  reports: "Репорты", support: "Поддержка", moderation: "Модерация", clans: "Кланы", voting: "Голосования",
  news: "Новости", analytics: "Аналитика", monitoring: "Мониторинг", notifications: "Уведомления",
  admins: "Администраторы", security: "Безопасность", audit: "Аудит", extra: "Настройки",
};

export function Header({ onSidebarToggle }: { onSidebarToggle: () => void }) {
  const pathname = usePathname() || "/dashboard";
  const segments = pathname.split("/").filter(Boolean);

  return (
    <header className="prisma-glass-surface sticky top-0 z-30 rounded-none border-x-0 border-t-0">
      <div className="mx-auto flex h-14 w-full max-w-[1440px] items-center gap-3 px-4 sm:px-6 lg:px-8">
        <button type="button" onClick={onSidebarToggle} aria-label="Переключить меню" className="prisma-glass-control prisma-glass-hover inline-flex size-9 items-center justify-center rounded-md border">
          <Icon name="menu" size={18} />
        </button>
        <div className="hidden h-5 w-px bg-border sm:block" />
        <nav aria-label="Хлебные крошки" className="flex min-w-0 items-center gap-1.5 text-sm">
          <Link href="/dashboard" className="text-muted-foreground hover:text-foreground">PRISMA</Link>
          {segments.slice(1).map((segment) => (
            <span key={segment} className="flex min-w-0 items-center gap-1.5">
              <Icon name="chevron-right" size={14} className="shrink-0 text-muted-foreground/60" />
              <span className="truncate font-medium">{LABELS[segment] ?? segment}</span>
            </span>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-1">
          <a href="https://github.com/nazarmilkus1-ai/prisma-ecosystem" target="_blank" rel="noreferrer" className="prisma-glass-control prisma-glass-hover hidden size-9 items-center justify-center rounded-md border sm:inline-flex" aria-label="GitHub">
            <Icon name="github" size={16} />
          </a>
          <ThemeSwitcher compact />
          <Link href="/dashboard/notifications" className="prisma-glass-control prisma-glass-hover inline-flex size-9 items-center justify-center rounded-md border" aria-label="Уведомления">
            <Icon name="bell" size={16} />
          </Link>
          <Link href="/dashboard/extra" className="prisma-glass-control prisma-glass-hover ml-1 hidden items-center gap-2 rounded-md border px-2.5 py-1.5 text-xs font-medium sm:flex">
            <span className="size-2 rounded-full bg-emerald-500" aria-hidden />
            PRISMA
          </Link>
        </div>
      </div>
    </header>
  );
}
