-- Part 1/2. Bans last 30 days by default (every way a ban is issued). Applied as 20261117144239.
-- Forward-only.

alter table public.users
  add column if not exists ban_review_due_at timestamptz,
  add column if not exists ban_review_notified_at timestamptz;

-- 1) Default ban term = 30 days, for every way a ban is issued (bot, panel, plugin, 5-warning auto-ban).
create or replace function private.prisma_ban_default_term_user()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if new.is_banned is true
     and new.banned_until is null
     and coalesce(new.ban_type,'') <> 'REVIEW'
     and (tg_op = 'INSERT' or old.is_banned is not true) then
    new.banned_until := now() + interval '30 days';
    new.ban_type := 'TEMPORARY';
  end if;
  return new;
end;
$function$;

create or replace trigger prisma_ban_default_term
  before insert or update of is_banned, banned_until on public.users
  for each row execute function private.prisma_ban_default_term_user();

create or replace function private.prisma_ban_default_term_log()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if new.type = 'BAN' and new.expires_at is null and coalesce(new.revoked, false) = false then
    new.expires_at := now() + interval '30 days';
    new.duration_minutes := coalesce(new.duration_minutes, 43200);
  end if;
  return new;
end;
$function$;

create or replace trigger prisma_ban_default_term
  before insert on public.moderation_logs
  for each row execute function private.prisma_ban_default_term_log();

