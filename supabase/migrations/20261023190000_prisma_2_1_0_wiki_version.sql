-- Обновить актуальные страницы Wiki после перехода проекта на PRISMA 2.1.0.
-- Исторические миграции и их комментарии не изменяются: они фиксируют состояние на момент создания.

begin;

update public.wiki_pages
set content = replace(content, '**PrismaPlugin 2.0.0**', '**PrismaPlugin 2.1.0**'),
    updated_at = now()
where slug = 'prisma-minecraft-plugins'
  and content like '%**PrismaPlugin 2.0.0**%';

update public.wiki_pages
set content = replace(content, 'Актуальная версия проекта: **2.0.0**.', 'Актуальная версия проекта: **2.1.0**.'),
    updated_at = now()
where slug = 'prisma-history'
  and content like '%Актуальная версия проекта: **2.0.0**.%';

commit;
