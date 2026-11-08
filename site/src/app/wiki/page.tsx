import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Card, CardDescription, CardHeader, CardTitle, FormField, Input, Button, PageHeader } from "@prisma-eco/ui";
import { getWiki } from "@/lib/data";

export const metadata = { title: "PRISMA Wiki" };

type WikiPage = {
  id: string;
  slug: string;
  title: string;
  excerpt?: string | null;
  content: string;
  category: string;
};

type WikiGroup = {
  title: string;
  description: string;
  slugs: string[];
};

type WikiSection = {
  category: string;
  title: string;
  description: string;
  groups: WikiGroup[];
};

const WIKI_SECTIONS: WikiSection[] = [
  {
    category: "MINECRAFT",
    title: "Minecraft",
    description: "Сервер PRISMA: подключение, правила, команды и решение частых проблем.",
    groups: [
      {
        title: "Основы сервера",
        description: "Что такое сервер и как получить доступ.",
        slugs: ["minecraft-about-server", "minecraft-how-to-join"],
      },
      {
        title: "Подключение",
        description: "Инструкции для Java, Bedrock, PRISMA Auth и Geyser/Floodgate.",
        slugs: [
          "minecraft-java-connection",
          "minecraft-bedrock-connection",
          "minecraft-prisma-auth",
          "minecraft-geyser-floodgate",
        ],
      },
      {
        title: "Игра на сервере",
        description: "Команды, правила, whitelist и типовые проблемы.",
        slugs: ["minecraft-commands", "minecraft-rules", "minecraft-whitelist", "minecraft-faq"],
      },
    ],
  },
  {
    category: "TELEGRAM",
    title: "Telegram",
    description: "Телеграм-бот PRISMA: регистрация, функции игрока и автомодерация.",
    groups: [
      {
        title: "Основы",
        description: "Бот и регистрация участника.",
        slugs: ["telegram-bot", "telegram-registration", "telegram-application", "telegram-commands"],
      },
      {
        title: "Функции участника",
        description: "Центр игрока и персональные уведомления.",
        slugs: ["telegram-player-center", "telegram-notifications"],
      },
      {
        title: "Модерация",
        description: "Автоматическая защита и модерационные сценарии Telegram.",
        slugs: ["telegram-automod"],
      },
    ],
  },
  {
    category: "SYSTEMS",
    title: "PRISMA Systems",
    description: "Все основные системы PRISMA: от общей модели до инфраструктуры и игровых возможностей.",
    groups: [
      {
        title: "Знакомство с PRISMA",
        description: "Как устроена экосистема и из каких основных частей состоит.",
        slugs: ["prisma-wiki-guide", "prisma-how-it-works", "prisma-site", "prisma-telegram", "prisma-minecraft", "prisma-staff-panel"],
      },
      {
        title: "Участник и игровой прогресс",
        description: "Единая модель игрока, уровни, XP, рейтинг и Player Battle.",
        slugs: ["prisma-participant-model", "prisma-levels-xp", "prisma-rating", "prisma-player-battle"],
      },
      {
        title: "Сообщество и игровые системы",
        description: "Уведомления, поддержка, роли, авторизация, рынок, карта и модерация.",
        slugs: [
          "prisma-notifications",
          "prisma-support-complaints",
          "prisma-roles-permissions",
          "prisma-auth-identification",
          "prisma-economy-market",
          "prisma-map",
          "prisma-moderation",
        ],
      },
      {
        title: "Архитектура и инфраструктура",
        description: "Техническая архитектура, Supabase, Render, Vercel, Minecraft и контрактный слой.",
        slugs: [
          "prisma-technical-architecture",
          "prisma-supabase",
          "prisma-render",
          "prisma-vercel",
          "prisma-minecraft-plugins",
          "prisma-api-rpc",
          "prisma-security",
          "prisma-monitoring",
          "prisma-history",
        ],
      },
      {
        title: "Команды и социальные функции",
        description: "Команды Telegram и Minecraft, кланы, отношения, достижения и профили.",
        slugs: [
          "prisma-telegram-commands",
          "prisma-minecraft-commands",
          "prisma-clans",
          "prisma-social-relationships-marriages",
          "prisma-achievements",
          "prisma-player-profiles",
        ],
      },
      {
        title: "Staff и обслуживание",
        description: "Служебные команды, permissions, обращения, Panel и техническая диагностика.",
        slugs: [
          "prisma-staff-telegram-commands",
          "prisma-staff-permissions-matrix",
          "prisma-staff-case-management",
          "prisma-staff-panel-workflows",
          "prisma-technical-troubleshooting",
        ],
      },
    ],
  },
  {
    category: "STAFF",
    title: "Staff",
    description: "Внутренняя документация персонала: роли, полномочия, модерация и обучение.",
    groups: [
      {
        title: "Основы Staff",
        description: "Устройство команды, роли и ответственность.",
        slugs: ["staff-about", "staff-structure", "staff-roles"],
      },
      {
        title: "Полномочия и правила",
        description: "Границы доступа и единые правила работы.",
        slugs: ["staff-permissions", "staff-work-rules"],
      },
      {
        title: "Модерация",
        description: "Работа Staff с Minecraft и Telegram.",
        slugs: ["staff-minecraft-moderation", "staff-telegram-moderation"],
      },
      {
        title: "Системы и обучение",
        description: "PRISMA Systems и путь нового сотрудника.",
        slugs: ["staff-prisma-systems", "staff-training"],
      },
      {
        title: "Справка",
        description: "Быстрые ответы на частые вопросы Staff.",
        slugs: ["staff-faq"],
      },
    ],
  },
];

function articleNumber(page: WikiPage) {
  const match = String(page.title).match(/^(\d+)\./);
  return match ? Number(match[1]) : Number.MAX_SAFE_INTEGER;
}

function articleTitle(page: WikiPage) {
  return page.title.replace(/^\d+\.\s*/, "");
}

function sortArticles(pages: WikiPage[]) {
  return [...pages].sort((a, b) => articleNumber(a) - articleNumber(b) || a.title.localeCompare(b.title, "ru"));
}

function ArticleLink({ page }: { page: WikiPage }) {
  const number = articleNumber(page);
  const numberLabel = Number.isFinite(number) ? String(number).padStart(2, "0") : "—";

  return (
    <Link
      href={"/wiki/" + page.slug}
      className="group prisma-glass-control prisma-glass-hover flex min-w-0 gap-3 rounded-lg border p-3.5 transition-colors"
    >
      <span className="prisma-glass-surface flex size-8 shrink-0 items-center justify-center rounded-md border text-xs font-semibold tabular-nums text-muted-foreground">
        {numberLabel}
      </span>
      <span className="min-w-0">
        <span className="block truncate text-sm font-semibold group-hover:text-foreground">{articleTitle(page)}</span>
        <span className="mt-1 block line-clamp-2 text-xs leading-5 text-muted-foreground">
          {page.excerpt || page.content.slice(0, 180)}
        </span>
      </span>
    </Link>
  );
}

function SectionCard({
  section,
  pages,
  sectionIndex,
}: {
  section: WikiSection;
  pages: WikiPage[];
  sectionIndex: number;
}) {
  const pageBySlug = new Map(pages.map((page) => [page.slug, page]));

  return (
    <Card>
      <CardHeader>
        <div className="flex items-start gap-3">
          <span className="prisma-glass-surface flex size-9 shrink-0 items-center justify-center rounded-md border text-xs font-bold tabular-nums text-muted-foreground">
            {String(sectionIndex + 1).padStart(2, "0")}
          </span>
          <div className="min-w-0">
            <CardTitle className="text-base">{section.title}</CardTitle>
            <CardDescription className="mt-1 leading-6">{section.description}</CardDescription>
          </div>
        </div>
      </CardHeader>

      <div className="space-y-4 p-5">
        {section.groups.map((group) => {
          const groupPages = sortArticles(
            group.slugs
              .map((slug) => pageBySlug.get(slug))
              .filter((page): page is WikiPage => Boolean(page)),
          );

          if (!groupPages.length) return null;

          return (
            <section key={group.title} className="prisma-glass-surface rounded-lg border p-3.5 sm:p-4">
              <div className="border-b pb-3">
                <div className="min-w-0">
                  <h3 className="text-sm font-semibold">{group.title}</h3>
                  <p className="mt-1 text-xs leading-5 text-muted-foreground">{group.description}</p>
                </div>
              </div>

              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                {groupPages.map((page) => (
                  <ArticleLink key={page.id} page={page} />
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </Card>
  );
}

export default async function WikiPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; category?: string }>;
}) {
  const params = await searchParams;
  const query = (params.q ?? "").trim();
  const requestedCategory = (params.category ?? "").trim().toUpperCase();
  await requireModule("public-content");
  const pages = (await getWiki()) as WikiPage[];

  const visibleCategories = Array.from(new Set(pages.map((page) => page.category)));
  const selectedCategory = visibleCategories.includes(requestedCategory) ? requestedCategory : "";

  const normalizedQuery = query.toLocaleLowerCase("ru-RU");
  const searchedPages = normalizedQuery
    ? pages.filter((page) =>
        [page.title, page.excerpt, page.content, page.category]
          .filter(Boolean)
          .some((value) => String(value).toLocaleLowerCase("ru-RU").includes(normalizedQuery)),
      )
    : pages;

  const visiblePages = selectedCategory
    ? searchedPages.filter((page) => page.category === selectedCategory)
    : searchedPages;

  const sections = WIKI_SECTIONS.filter((section) => visibleCategories.includes(section.category)).filter(
    (section) => !selectedCategory || section.category === selectedCategory,
  );

  return (
    <div className="mx-auto w-full max-w-7xl px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
      <div className="space-y-6">
        <PageHeader
          eyebrow="База знаний"
          title="PRISMA Wiki"
          description="Материалы PRISMA собраны по разделам, группам и отдельным статьям."
        />

        <Card>
          <CardHeader>
            <CardTitle>Разделы Wiki</CardTitle>
            <CardDescription>Выберите большой раздел или оставьте все материалы открытыми.</CardDescription>
          </CardHeader>
          <div className="flex flex-wrap gap-2 px-5 py-4">
            <Link
              href={query ? "/wiki?q=" + encodeURIComponent(query) : "/wiki"}
              className={[
                "prisma-glass-control prisma-glass-hover rounded-md border px-3 py-2 text-sm font-medium transition-colors",
                !selectedCategory ? "border-[var(--primary)]/40 text-foreground" : "text-muted-foreground",
              ].join(" ")}
            >
              Все разделы
            </Link>
            {WIKI_SECTIONS.filter((section) => visibleCategories.includes(section.category)).map((section) => (
              <Link
                key={section.category}
                href={
                  "/wiki?category=" +
                  encodeURIComponent(section.category) +
                  (query ? "&q=" + encodeURIComponent(query) : "")
                }
                className={[
                  "prisma-glass-control prisma-glass-hover rounded-md border px-3 py-2 text-sm font-medium transition-colors",
                  selectedCategory === section.category
                    ? "border-[var(--primary)]/40 text-foreground"
                    : "text-muted-foreground",
                ].join(" ")}
              >
                {section.title}
              </Link>
            ))}
          </div>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Поиск</CardTitle>
            <CardDescription>Поиск работает по названию, описанию, категории и содержимому статьи.</CardDescription>
          </CardHeader>
          <form action="/wiki" className="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-end">
            <input type="hidden" name="category" value={selectedCategory} />
            <div className="min-w-0 flex-1">
              <FormField label="Запрос">
                <Input name="q" defaultValue={query} placeholder="Например: кланы" className="prisma-glass-control" />
              </FormField>
            </div>
            <Button type="submit" variant="outline" className="prisma-glass-control prisma-glass-hover">Найти</Button>
          </form>
        </Card>

        {sections.map((section) => {
          const sectionPages = visiblePages.filter((page) => page.category === section.category);
          const sectionIndex = WIKI_SECTIONS.findIndex((item) => item.category === section.category);

          if (!sectionPages.length) return null;
          return <SectionCard key={section.category} section={section} pages={sectionPages} sectionIndex={sectionIndex} />;
        })}

        {!visiblePages.length ? (
          <Card>
            <div className="px-5 py-10 text-center">
              <p className="font-medium">Материалы не найдены</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Попробуйте изменить запрос или выбрать другой раздел.
              </p>
            </div>
          </Card>
        ) : null}
      </div>
    </div>
  );
}
