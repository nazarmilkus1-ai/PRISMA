# PRISMA Module Registry

Реєстр: `modules/registry.json`. Generated API: `packages/contracts/src/modules.generated.ts`.

## Навіщо

PRISMA має кілька consumers, які споживають одну доменну модель. Без окремого ownership-рівня легко отримати модуль, де половина логіки в bot, частина в site, ще частина в SQL.

Реєстр фіксує:

- хто володіє доменом;
- на яких поверхнях він живе;
- які shared contract namespaces він **експортує**;
- які namespaces він **використовує**;
- від яких модулів залежить;
- які каталоги потрібно перевірити під час демонтажу;
- чи описаний removal path.

## Ownership

`contractNamespaces` означає **власність**. Один namespace може мати тільки одного owner.

`uses` означає **залежність**. Один namespace може використовуватися багатьма модулями.

Це важлива різниця: наприклад, `STAFF_RPC` належить control-plane модулю, а moderation, reports, market та інші модулі лише використовують потрібні поля цього контракту.

## Додавання

Запустіть:

```powershell
node scripts/create-feature-module.mjs --id=example --title="Example module" --owner=core --depends=players
```

Після цього:

1. завершити запис у `modules/registry.json`;
2. додати domain contract;
3. додати migration/RPC/RLS/ACL;
4. підключити consumers;
5. заповнити verification та removal;
6. запустити `node scripts/verify-modules.mjs`.

## Видалення

Не вирізайте модуль одним глобальним пошуком.

Використовуйте порядок із `defaultRemovalOrder` у реєстрі: entrypoints → adapters → contracts → forward migration → ACL/RLS → docs.

Історичні Supabase migrations не переписуються. Видалення DB-структури оформлюється новою migration.

## Runtime-управління

Реєстр описує модулі, а не самостійно перемикає їх. Фактичний стан зберігається в `public.prisma_module_states` і змінюється через `/admin/dashboard/modules` (permission `modules.manage`, обов’язкова причина вимкнення та audit log).

Модули с префиксом `minecraft-` — отдельные переключатели игровых механик: дома, точки появления, координаты/чекпоинты, могилы, HUD/TAB, команды модерации, `/tpall`, staff-телепортация, команды кланов/сёл, защита территорий, `/tpa` и Minecraft ↔ Telegram. Они зависят от родительских доменов; выключенный родительский модуль блокирует зависимые функции, даже если отдельный переключатель включён.

Выключение переключателя блокирует новые действия/команды соответствующей механики. Восстановление уже начатых транзакций могил остаётся разрешённым, чтобы не потерять вещи игрока. Защита территорий работает по принципу fail-safe: пока свежий runtime-state не загружен, защита не отключается автоматически.

Миграция `20261024150000_prisma_minecraft_gameplay_toggles.sql` создаёт отсутствующие записи со значением `enabled=true` и не меняет существующие состояния. Её нужно применить к целевой базе до включения версии плагина, которая проверяет эти переключатели. Файл миграции в репозитории сам по себе не изменяет production.

## Runtime state

Кожен active module має `runtimeManaged: true`. Фактичний стан зберігається централізовано в `public.prisma_module_states`.

Для нового модуля scaffold автоматично додає його до registry та `MODULE_IDS`. Публічний RPC одиничного стану трактує відсутній рядок як enabled для backward compatibility, але Java-плагін читає явні рядки з `get_public_module_states()` і блокує функцію, якщо стан відсутній або застарілий. Тому перед оновленням JAR потрібно застосувати відповідну forward migration до цільової бази.

Для staff доступні permission keys `modules.view` і `modules.manage`. Будь-яке перемикання стану проходить через RPC та audit log.


## Generated contracts

`packages/contracts/src/modules.generated.ts` генерується тільки зі registry через `scripts/sync-module-contracts.mjs`. Не редагуйте його вручну. Це прибирає дублювання metadata між registry, contracts та admin UI.
