-- Public read policies for intentionally public news and clan directories.

drop policy if exists news_public_select on public.news;
create policy news_public_select on public.news
for select to anon,authenticated
using (is_published=true);

drop policy if exists clans_public_select on public.clans;
create policy clans_public_select on public.clans
for select to anon,authenticated
using (deleted_at is null and status='active');
