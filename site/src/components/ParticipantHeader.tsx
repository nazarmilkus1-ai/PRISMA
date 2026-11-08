"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon } from "@/components/Icon";
import { GlobalSearchLauncher } from "@/components/GlobalSearchLauncher";
import { PrismMark } from "@/components/PrismMark";

const LABELS: Record<string, string> = {
  app: "Главная",
  profile: "Мой профиль",
  application: "Моя заявка",
  minecraft: "Моя статистика",
  clan: "Клан",
  reports: "Репорты",
  appeals: "Апелляции",
  voting: "Голосования",
  settings: "Настройки",
  notifications: "Уведомления",
  server: "Сервер",
  map: "Карта",
  history: "Аналитика",
  players: "Игроки",
  rankings: "Рейтинги",
  events: "События",
  calendar: "Календарь",
  market: "Рынок",
  news: "Новости",
  wiki: "Wiki",
  battles: "Player Battle",
};

export function ParticipantHeader({
  user,
  onMenuToggle,
}: {
  user: {
    minecraft_nickname?: string | null;
    first_name?: string | null;
    telegram_username?: string | null;
  };
  onMenuToggle: () => void;
}) {
  const pathname = usePathname() || "/app";
  const segments = pathname.split("/").filter(Boolean).slice(1);
  const displayName = user.minecraft_nickname || user.first_name || user.telegram_username || "PRISMA";
  const initial = displayName.slice(0, 1).toUpperCase();

  return (
    <header className="site-participant-header sticky top-0 z-30">
      <div className="mx-auto flex h-14 w-full max-w-[1200px] items-center gap-2 px-4 sm:px-6 lg:px-8">
        <button
          type="button"
          onClick={onMenuToggle}
          aria-label="Переключить меню"
          className="prisma-glass-control prisma-glass-hover inline-flex size-9 shrink-0 items-center justify-center rounded-md border text-muted-foreground transition-colors"
        >
          <Icon name="menu" size={18} />
        </button>

        <Link
          href="/app"
          aria-label="PRISMA — Главная"
          className="prisma-glass-hover inline-flex items-center gap-2 rounded-md px-2 py-1.5 transition-colors"
        >
          <span className="prisma-glass-primary flex size-7 items-center justify-center rounded-md border text-primary-foreground">
            <PrismMark size={14} />
          </span>
          <span className="hidden text-sm font-semibold tracking-wide sm:inline">PRISMA</span>
        </Link>

        {segments.length > 0 ? (
          <span className="hidden min-w-0 items-center gap-2 sm:flex">
            <Icon
              name="chevron-right"
              size={14}
              className="shrink-0 text-muted-foreground"
              aria-hidden
            />
            <span className="min-w-0 truncate text-sm font-medium text-muted-foreground">
              {LABELS[segments[segments.length - 1]] ?? segments[segments.length - 1]}
            </span>
          </span>
        ) : null}

        <div className="ml-auto flex items-center gap-2">
          <GlobalSearchLauncher />

          <Link
            href="/app/profile"
            aria-label="Мой профиль"
            className="prisma-glass-control prisma-glass-hover flex items-center gap-2 rounded-md border px-2 py-1.5 text-xs font-medium transition-colors"
          >
            <span className="flex size-7 items-center justify-center rounded-md bg-white text-[10px] font-extrabold text-black">
              {initial}
            </span>
            <span className="hidden max-w-36 truncate sm:inline">{displayName}</span>
          </Link>
        </div>
      </div>
    </header>
  );
}