-- PRISMA: enforce Minecraft whitelist eligibility from community membership
-- and the current non-archived accepted application.

create or replace function private.prisma_whitelist_is_eligible(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $function$
  select exists (
    select 1
    from public.users u
    where u.id=p_user_id
      and u.deleted_at is null
      and u.community_is_member=true
      and u.status='ACCEPTED'::public.application_status
      and u.is_banned=false
      and u.minecraft_nickname is not null
      and u.platform is not null
      and exists (
        select 1
        from public.applications a
        where a.user_id=u.id
          and a.status='ACCEPTED'::public.application_status
          and not a.is_archived
      )
  );
$function$;

revoke all on function private.prisma_whitelist_is_eligible(uuid)
from public,anon,authenticated;
grant execute on function private.prisma_whitelist_is_eligible(uuid) to postgres;

create or replace function private.prisma_enforce_user_whitelist()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  eligible boolean;
  grant_on_transition boolean := false;
begin
  eligible := private.prisma_whitelist_is_eligible(new.id);

  if not eligible then
    new.is_whitelisted := false;
    return new;
  end if;

  if tg_op='UPDATE' then
    grant_on_transition :=
      (coalesce(old.community_is_member,false)=false and new.community_is_member=true)
      or (coalesce(old.status::text,'') <> 'ACCEPTED' and new.status='ACCEPTED'::public.application_status)
      or (coalesce(old.is_banned,false)=true and new.is_banned=false)
      or (old.minecraft_nickname is null and new.minecraft_nickname is not null)
      or (old.platform is null and new.platform is not null);
  end if;

  if grant_on_transition then
    new.is_whitelisted := true;
  end if;

  return new;
end;
$function$;

revoke all on function private.prisma_enforce_user_whitelist()
from public,anon,authenticated;
grant execute on function private.prisma_enforce_user_whitelist() to postgres;

drop trigger if exists prisma_enforce_user_whitelist on public.users;
create trigger prisma_enforce_user_whitelist
before update of community_is_member,status,is_banned,deleted_at,minecraft_nickname,platform,is_whitelisted
on public.users
for each row
execute function private.prisma_enforce_user_whitelist();

create or replace function private.prisma_reconcile_application_whitelist()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  update public.users u
  set is_whitelisted = private.prisma_whitelist_is_eligible(u.id),
      updated_at = now()
  where u.id=new.user_id;
  return new;
end;
$function$;

revoke all on function private.prisma_reconcile_application_whitelist()
from public,anon,authenticated;
grant execute on function private.prisma_reconcile_application_whitelist() to postgres;

drop trigger if exists prisma_reconcile_application_whitelist on public.applications;
create trigger prisma_reconcile_application_whitelist
after insert or update of status,is_archived
on public.applications
for each row
execute function private.prisma_reconcile_application_whitelist();

-- Reconcile every existing user once under the new invariant.
update public.users u
set is_whitelisted = private.prisma_whitelist_is_eligible(u.id),
    updated_at = now()
where u.is_whitelisted
   or not private.prisma_whitelist_is_eligible(u.id);

