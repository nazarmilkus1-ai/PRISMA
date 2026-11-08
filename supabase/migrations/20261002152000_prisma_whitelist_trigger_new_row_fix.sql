-- PRISMA: fix whitelist trigger to evaluate the pending NEW user row.

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
  eligible :=
    new.deleted_at is null
    and new.community_is_member=true
    and new.status='ACCEPTED'::public.application_status
    and new.is_banned=false
    and new.minecraft_nickname is not null
    and new.platform is not null
    and exists (
      select 1
      from public.applications a
      where a.user_id=new.id
        and a.status='ACCEPTED'::public.application_status
        and not a.is_archived
    );

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

-- Reconcile the current state after the trigger correction.
update public.users u
set is_whitelisted = private.prisma_whitelist_is_eligible(u.id),
    updated_at = now()
where u.is_whitelisted
   or not private.prisma_whitelist_is_eligible(u.id);
