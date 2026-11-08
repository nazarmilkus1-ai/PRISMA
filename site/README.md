# PRISMA Community Site

Участницький веб-сайт PRISMA: публичная часть сообщества и рабочий кабинет игрока.

## Стек

- Next.js 16 / React 19
- TypeScript
- Tailwind CSS 4
- Supabase SSR + Auth
- Vercel

## Дизайн

UI строится на Supabase Design System: semantic color roles, theming, navigation patterns, atom components и fragment components. PRISMA использует собственный brand-accent, но не заменяет системные UI-паттерны случайными стилями.

## Запуск

```powershell
cd site
copy .env.example .env.local
npm install
npm run dev
```

## Переменные

`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` и `SUPABASE_SERVICE_ROLE_KEY` нужны для полного режима. Service-role ключ используется только в server-side коде.

## Auth

Вход выполняется через Telegram-бота PRISMA. Бот выдаёт одноразовый код через `login_codes`; сайт создаёт или использует Supabase Auth identity и связывает её с `users.auth_user_id`.

Участник должен иметь существующий профиль PRISMA.

## Кабинет участника

`/app` использует ту же информационную модель, что и административная панель PRISMA:

- **Обзор** — главная.
- **Minecraft** — сервер, карта, личная статистика и аналитика.
- **Сообщество** — игроки, рейтинги, кланы, события, календарь, рынок, новости и Wiki.
- **Взаимодействие** — голосования, репорты и Player Battle.
- **Профиль** — профиль и заявка.
- **Система** — уведомления и настройки.

На desktop кабинет использует фиксированный сворачиваемый sidebar и sticky header. На мобильных устройствах sidebar превращается в выезжающее меню.

## Публичные маршруты

- `/` — главная
- `/server` — Minecraft
- `/map` — Dynmap
- `/news` — новости
- `/clans` — публичные кланы
- `/players` — игроки
- `/rankings` — рейтинги
- `/events` — события
- `/calendar` — календарь
- `/market` — рынок
- `/wiki` — Wiki
- `/commands` — Команды Minecraft
- `/app/commands` — команды Minecraft в личном кабинете
- `/battles` — Player Battle

## Маршруты кабинета

- `/app` — обзор участника
- `/app/profile` — профиль
- `/app/minecraft` — личная Minecraft-статистика
- `/app/clan` — мой клан
- `/app/reports` — репорты
- `/app/voting` — голосования
- `/app/notifications` — уведомления
- `/app/settings` — настройки

## Безопасность

Participant UI не является источником авторизации. Доступ защищён Supabase Auth, server-side session checks, RLS и server-only service-role operations.

PRISMA rebuild начинается с чистой доменной модели. Из старой системы сохраняется только необходимый список текущих зарегистрированных участников; Iris history и прочие legacy-данные не являются частью нового baseline.
