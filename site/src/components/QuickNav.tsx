"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";

type Area = "public" | "participant";
type Page = { href: string; label: string; keys?: string };

const PUBLIC_PAGES: Page[] = [
  { href: "/", label: "Главная", keys: "home главная" },
  { href: "/server", label: "О сервере", keys: "server сервер онлайн ip" },
  { href: "/community", label: "Сообщество" },
  { href: "/map", label: "Карта", keys: "map карта" },
  { href: "/market", label: "Рынок", keys: "market рынок объявления" },
  { href: "/clans", label: "Кланы", keys: "clans клан" },
  { href: "/events", label: "События", keys: "events ивенты" },
  { href: "/rankings", label: "Рейтинг", keys: "rankings топ" },
  { href: "/players", label: "Игроки", keys: "players" },
  { href: "/commands", label: "Команды", keys: "commands" },
  { href: "/news", label: "Новости", keys: "news" },
  { href: "/wiki", label: "Wiki", keys: "wiki вики" },
  { href: "/rules", label: "Правила", keys: "rules" },
  { href: "/faq", label: "FAQ", keys: "faq вопросы" },
  { href: "/status", label: "Состояние", keys: "status состояние работает статус" },
  { href: "/apply", label: "Подать анкету", keys: "apply заявка" },
  { href: "/search", label: "Поиск" },
  { href: "/login", label: "Войти", keys: "login вход" },
];

const GO: Record<Area, Record<string, Page>> = {
  public: {
    h: { href: "/", label: "Главная" }, s: { href: "/server", label: "Сервер" }, m: { href: "/market", label: "Рынок" },
    c: { href: "/clans", label: "Кланы" }, e: { href: "/events", label: "События" }, w: { href: "/wiki", label: "Wiki" },
    r: { href: "/rules", label: "Правила" }, n: { href: "/news", label: "Новости" }, p: { href: "/players", label: "Игроки" },
    k: { href: "/map", label: "Карта" }, l: { href: "/rankings", label: "Рейтинг" }, a: { href: "/apply", label: "Анкета" },
    t: { href: "/status", label: "Состояние" },
  },
  participant: {
    h: { href: "/app", label: "Главная" }, s: { href: "/app/server", label: "Сервер" }, m: { href: "/app/market", label: "Рынок" },
    c: { href: "/app/clan", label: "Клан" }, e: { href: "/app/events", label: "События" }, w: { href: "/app/wiki", label: "Wiki" },
    r: { href: "/app/rankings", label: "Рейтинги" }, n: { href: "/app/news", label: "Новости" }, p: { href: "/app/players", label: "Игроки" },
    k: { href: "/app/map", label: "Карта" }, f: { href: "/app/profile", label: "Профиль" }, t: { href: "/app/support", label: "Поддержка" },
    v: { href: "/app/voting", label: "Голосования" }, b: { href: "/app/battles", label: "Player Battle" },
  },
};

const USAGE_KEY = "prisma:nav-usage";

function readUsage(): Record<string, number> {
  try {
    const raw = window.localStorage.getItem(USAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : {};
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function bumpUsage(href: string) {
  try {
    const usage = readUsage();
    usage[href] = (usage[href] || 0) + 1;
    window.localStorage.setItem(USAGE_KEY, JSON.stringify(usage));
  } catch {
    /* storage can be blocked: the palette still works without it */
  }
}

function isTyping(target: EventTarget | null) {
  const el = target as HTMLElement | null;
  const tag = el?.tagName?.toLowerCase();
  return tag === "input" || tag === "textarea" || tag === "select" || Boolean(el?.isContentEditable);
}

/** Hotkeys for the whole site: Ctrl/⌘+K or "/" palette (public pages), "g" + letter jumps, "?" help. */
export function QuickNav({ area }: { area: Area }) {
  const router = useRouter();
  const [palette, setPalette] = useState(false);
  const [help, setHelp] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const [usage, setUsage] = useState<Record<string, number>>({});
  const [pending, setPending] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const pendingTimer = useRef<number | undefined>(undefined);

  const go = (page: Page) => {
    bumpUsage(page.href);
    setPalette(false);
    setHelp(false);
    router.push(page.href);
  };

  useEffect(() => {
    const clearPending = () => {
      window.clearTimeout(pendingTimer.current);
      setPending(false);
    };
    let awaiting = false;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setPalette(false);
        setHelp(false);
        awaiting = false;
        clearPending();
        return;
      }
      const plain = !event.ctrlKey && !event.metaKey && !event.altKey;
      if (area === "public" && (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setUsage(readUsage());
        setQuery("");
        setActive(0);
        setPalette(true);
        return;
      }
      if (isTyping(event.target) || !plain) return;
      if (awaiting) {
        awaiting = false;
        clearPending();
        const page = GO[area][event.key.toLowerCase()];
        if (page) {
          event.preventDefault();
          bumpUsage(page.href);
          router.push(page.href);
        }
        return;
      }
      if (event.key === "g") {
        awaiting = true;
        setPending(true);
        pendingTimer.current = window.setTimeout(() => {
          awaiting = false;
          setPending(false);
        }, 1500);
      } else if (event.key === "?") {
        event.preventDefault();
        setHelp((value) => !value);
      } else if (event.key === "/" && area === "public") {
        event.preventDefault();
        setUsage(readUsage());
        setQuery("");
        setActive(0);
        setPalette(true);
      }
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      window.clearTimeout(pendingTimer.current);
    };
  }, [area, router]);

  useEffect(() => {
    if (!palette) return;
    const timer = window.setTimeout(() => inputRef.current?.focus(), 20);
    return () => window.clearTimeout(timer);
  }, [palette]);

  const items = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const list = PUBLIC_PAGES.filter((p) => !needle || `${p.label} ${p.keys || ""} ${p.href}`.toLowerCase().includes(needle));
    return list.sort((a, b) => (usage[b.href] || 0) - (usage[a.href] || 0));
  }, [query, usage]);

  const frequent = useMemo(
    () => PUBLIC_PAGES.filter((p) => (usage[p.href] || 0) > 0).sort((a, b) => (usage[b.href] || 0) - (usage[a.href] || 0)).slice(0, 4),
    [usage],
  );

  const askAi = () => {
    setPalette(false);
    window.dispatchEvent(new CustomEvent("prisma:ask", { detail: query.trim() }));
  };

  const hotkeyRows = Object.entries(GO[area]);

  return (
    <>
      {pending ? (
        <div className="fixed bottom-4 left-1/2 z-[90] -translate-x-1/2 rounded-xl border bg-[var(--card,#111)] px-3 py-2 text-xs shadow-lg" role="status">
          g … <span className="text-[var(--muted-foreground)]">ещё одна клавиша · ? — список</span>
        </div>
      ) : null}

      {palette ? (
        <div className="fixed inset-0 z-[95] flex items-start justify-center bg-black/55 p-4 pt-[12vh]" onClick={() => setPalette(false)}>
          <div role="dialog" aria-modal="true" aria-label="Быстрый переход" className="prisma-glass-surface w-full max-w-lg overflow-hidden rounded-2xl border shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <input
              ref={inputRef}
              value={query}
              onChange={(e) => { setQuery(e.target.value); setActive(0); }}
              onKeyDown={(e) => {
                if (e.key === "ArrowDown") { e.preventDefault(); setActive((i) => Math.min(items.length, i + 1)); }
                else if (e.key === "ArrowUp") { e.preventDefault(); setActive((i) => Math.max(0, i - 1)); }
                else if (e.key === "Enter") { e.preventDefault(); if (active >= items.length) askAi(); else if (items[active]) go(items[active]); }
              }}
              placeholder="Куда перейти? Рынок, правила, карта…"
              className="w-full border-b bg-transparent px-4 py-3.5 text-sm outline-none"
              aria-label="Поиск страницы"
            />
            {!query && frequent.length ? (
              <p className="px-4 pt-3 text-[11px] uppercase tracking-widest text-[var(--muted-foreground)]">Часто: {frequent.map((p) => p.label).join(" · ")}</p>
            ) : null}
            <ul className="max-h-[50vh] overflow-y-auto p-2" role="listbox">
              {items.map((page, index) => (
                <li key={page.href} role="option" aria-selected={index === active}>
                  <button type="button" onMouseEnter={() => setActive(index)} onClick={() => go(page)}
                    className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm ${index === active ? "bg-white/10" : ""}`}>
                    <span>{page.label}</span><span className="font-mono text-[11px] text-[var(--muted-foreground)]">{page.href}</span>
                  </button>
                </li>
              ))}
              <li role="option" aria-selected={active >= items.length}>
                <button type="button" onMouseEnter={() => setActive(items.length)} onClick={askAi}
                  className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm ${active >= items.length ? "bg-white/10" : ""}`}>
                  <span>🤖 Спросить PRISMA_AI{query.trim() ? `: «${query.trim().slice(0, 40)}»` : ""}</span><span className="text-[11px] text-[var(--muted-foreground)]">Enter</span>
                </button>
              </li>
            </ul>
            <p className="border-t px-4 py-2 text-[11px] text-[var(--muted-foreground)]">↑↓ выбрать · Enter открыть · Esc закрыть · ? все горячие клавиши</p>
          </div>
        </div>
      ) : null}

      {help ? (
        <div className="fixed inset-0 z-[95] flex items-center justify-center bg-black/55 p-4" onClick={() => setHelp(false)}>
          <div role="dialog" aria-modal="true" aria-label="Горячие клавиши" className="prisma-glass-surface w-full max-w-md rounded-2xl border p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between"><h2 className="text-base font-semibold">Горячие клавиши</h2><button type="button" onClick={() => setHelp(false)} className="rounded-lg border px-2.5 py-1 text-xs">Esc</button></div>
            <ul className="mt-3 space-y-1.5 text-sm">
              <li className="flex justify-between"><span>{area === "public" ? "Быстрый переход" : "Поиск"}</span><kbd className="font-mono text-xs">Ctrl/⌘ + K  ·  /</kbd></li>
              <li className="flex justify-between"><span>Эта справка</span><kbd className="font-mono text-xs">?</kbd></li>
              {hotkeyRows.map(([key, page]) => (
                <li key={key} className="flex justify-between"><span>{page.label}</span><kbd className="font-mono text-xs">g  {key}</kbd></li>
              ))}
            </ul>
            <p className="mt-3 text-[11px] text-[var(--muted-foreground)]">Работают, когда курсор не в поле ввода.</p>
          </div>
        </div>
      ) : null}
    </>
  );
}
