-- PRISMA: keep the denormalized users.clan_id synchronized with the
-- canonical active clan_members relationship.
--
-- clan_members is the source of truth for membership. The users.clan_id
-- column remains for fast reads and legacy consumers, but must never drift.

create or replace function private.prisma_sync_user_clan_id_from_membership()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  old_user_id uuid;
  new_user_id uuid;
begin
  old_user_id := case when tg_op in ('UPDATE','DELETE') then old.user_id else null end;
  new_user_id := case when tg_op in ('INSERT','UPDATE') then new.user_id else null end;

  if old_user_id is not null then
    update public.users u
    set clan_id = (
      select cm.clan_id
      from public.clan_members cm
      where cm.user_id = old_user_id
        and cm.status = 'active'
      order by cm.joined_at desc nulls last
      limit 1
    ),
    updated_at = now()
    where u.id = old_user_id;
  end if;

  if new_user_id is not null
     and new_user_id is distinct from old_user_id then
    update public.users u
    set clan_id = (
      select cm.clan_id
      from public.clan_members cm
      where cm.user_id = new_user_id
        and cm.status = 'active'
      order by cm.joined_at desc nulls last
      limit 1
    ),
    updated_at = now()
    where u.id = new_user_id;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

drop trigger if exists clan_members_sync_user_clan_id on public.clan_members;

create trigger clan_members_sync_user_clan_id
after insert or update of user_id,clan_id,status or delete
on public.clan_members
for each row
execute function private.prisma_sync_user_clan_id_from_membership();

revoke all on function private.prisma_sync_user_clan_id_from_membership()
from public,anon,authenticated;
grant execute on function private.prisma_sync_user_clan_id_from_membership()
to postgres;
