import Link from "next/link";
import { Icon, type IconName } from "@/components/Icon";
import { PrismMark } from "@/components/PrismMark";
import { getCurrentUser } from "@/lib/auth";
import { getPublicModuleAvailability } from "@/lib/modules";
import type { ModuleId } from "@prisma-eco/contracts";

export const metadata = { title: "PRISMA" };

const STEPS = [
  ["Telegram", "Открой бота PRISMA: через него идёт вход и приходят все уведомления."],
  ["Заявка", "Заполни анкету: Minecraft-ник, платформа и пара слов о себе."],
  ["Вход", "Получи одноразовый код от бота и войди в личный кабинет."],
  ["Сообщество", "Следи за статусом заявки и знакомься с игроками и кланами."],
  ["Игра", "После принятия администрацией подключайся к серверу."],
] as const;

type Tile = {
  href: string;
  icon: IconName;
  title: string;
  text: string;
  moduleId: ModuleId;
  open: boolean;
};

const TILES: readonly Tile[] = [
  { href: "/server", icon: "server", title: "Сервер и карта", text: "Статус сервера, интерактивная карта мира и история её изменений.", moduleId: "minecraft", open: false },
  { href: "/clans", icon: "clans", title: "Кланы", text: "Территории, войны, ранги и сравнение кланов между собой.", moduleId: "clans", open: false },
  { href: "/events", icon: "calendar", title: "События", text: "Календарь ивентов, регистрация и итоговые результаты.", moduleId: "events", open: false },
  { href: "/rankings", icon: "ranking", title: "Рейтинги", text: "Таблицы лидеров, сезоны и паспорт каждого игрока.", moduleId: "players", open: false },
  { href: "/market", icon: "market", title: "Рынок", text: "Объявления сообщества: обмен, продажа и помощь.", moduleId: "market", open: false },
  { href: "/wiki", icon: "wiki", title: "Wiki", text: "Правила, инструкции и описание систем PRISMA.", moduleId: "public-content", open: true },
];

export default async function HomePage() {
  const [user, enabledModules] = await Promise.all([getCurrentUser(), getPublicModuleAvailability()]);
  const isMember = Boolean(user && user.status === "ACCEPTED" && !user.is_banned && user.is_whitelisted);
  const tiles = TILES.filter((tile) => enabledModules[tile.moduleId]);

  return (
    <>
      <section className="mx-auto flex min-h-[calc(100svh-56px)] w-full max-w-7xl items-center px-4 py-16 sm:px-6 lg:px-8">
        <div className="prisma-glass-surface prisma-stagger w-full max-w-xl rounded-[32px] p-7 sm:p-10">
          <div className="mb-7 flex items-center justify-between gap-4">
            <span className="ox-brand">
              <PrismMark />
              Prisma
            </span>
            <span className="ox-chip">Minecraft</span>
          </div>

          <h1 className="fade-text text-[clamp(2.75rem,10vw,4.5rem)] font-extrabold leading-[1.02] tracking-[-0.04em]">
            PRISMA
          </h1>
          <p className="mt-4 max-w-md text-base leading-7 text-foreground-light">
            Сообщество Minecraft. Один луч света, много разных игроков. Начни с заявки или изучи нашу Wiki.
          </p>

          <div className="mt-8 flex flex-wrap gap-3">
            {isMember ? (
              <Link href="/app" className="ox-btn ox-btn-solid">
                Открыть кабинет
                <Icon name="check" size={18} />
              </Link>
            ) : enabledModules.applications ? (
              <Link href="/apply" className="ox-btn ox-btn-solid">
                Подать анкету
                <ArrowIcon />
              </Link>
            ) : null}
            {enabledModules["public-content"] ? (
              <Link href="/wiki" className="ox-btn">
                Wiki
              </Link>
            ) : null}
            <a
              href="https://t.me/prisma_eco_bot?start=onboarding"
              target="_blank"
              rel="noopener noreferrer"
              className="ox-btn"
            >
              Открыть Telegram
            </a>
          </div>
        </div>
      </section>

      <section className="mx-auto w-full max-w-7xl px-4 py-16 sm:px-6 lg:px-8" aria-labelledby="steps-title">
        <div className="mb-8 grid max-w-xl gap-2">
          <p className="ox-chip">Вход в сообщество</p>
          <h2 id="steps-title" className="text-3xl font-extrabold tracking-[-0.025em] sm:text-4xl">
            Как попасть на сервер
          </h2>
        </div>
        <ol className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          {STEPS.map(([title, text], index) => (
            <li key={title} className="ox-card">
              <span className="ox-step">{index + 1}</span>
              <h3 className="mt-2 text-lg font-extrabold tracking-[-0.02em]">{title}</h3>
              <p className="text-sm leading-6 text-muted-foreground">{text}</p>
            </li>
          ))}
        </ol>
      </section>

      {tiles.length > 0 ? (
        <section className="mx-auto w-full max-w-7xl px-4 py-16 sm:px-6 lg:px-8" aria-labelledby="inside-title">
          <div className="mb-8 grid max-w-xl gap-2">
            <p className="ox-chip">Возможности</p>
            <h2 id="inside-title" className="text-3xl font-extrabold tracking-[-0.025em] sm:text-4xl">
              Что внутри
            </h2>
          </div>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {tiles.map((tile) => {
              const content = (
                <>
                  <span className="flex size-11 items-center justify-center rounded-[14px] border border-white/20 bg-white/[0.06]">
                    <Icon name={tile.icon} size={20} />
                  </span>
                  <h3 className="mt-2 text-lg font-extrabold tracking-[-0.02em]">{tile.title}</h3>
                  <p className="text-sm leading-6 text-muted-foreground">{tile.text}</p>
                  {!tile.open && !isMember ? (
                    <span className="ox-chip mt-1">Для участников</span>
                  ) : null}
                </>
              );
              return tile.open || isMember ? (
                <Link key={tile.href} href={tile.href} className="ox-card">
                  {content}
                </Link>
              ) : (
                <div key={tile.href} className="ox-card">
                  {content}
                </div>
              );
            })}
          </div>
        </section>
      ) : null}

      <section className="mx-auto w-full max-w-7xl px-4 pb-24 pt-8 sm:px-6 lg:px-8">
        <div className="prisma-glass-surface rounded-[32px] p-8 text-center sm:p-12">
          <h2 className="fade-text mx-auto max-w-xl text-3xl font-extrabold tracking-[-0.03em] sm:text-4xl">
            {isMember ? "Всё ждёт тебя в кабинете" : "Начни с одной анкеты"}
          </h2>
          <p className="mx-auto mt-3 max-w-md text-sm leading-6 text-foreground-light">
            {isMember
              ? "Профиль, клан, события и рынок собраны в одном месте."
              : "Это займёт пару минут. Результат придёт в Telegram и в личный кабинет."}
          </p>
          <div className="mt-7 flex justify-center">
            {isMember ? (
              <Link href="/app" className="ox-btn ox-btn-solid">
                Открыть кабинет
                <ArrowIcon />
              </Link>
            ) : enabledModules.applications ? (
              <Link href="/apply" className="ox-btn ox-btn-solid">
                Подать анкету
                <ArrowIcon />
              </Link>
            ) : null}
          </div>
        </div>
      </section>
    </>
  );
}

function ArrowIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <line x1="5" y1="12" x2="19" y2="12" />
      <polyline points="12 5 19 12 12 19" />
    </svg>
  );
}
