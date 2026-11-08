-- PRISMA v2: authenticated staff gateway for the Telegram community chat id.

create or replace function public.staff_get_community_chat_id()
returns bigint
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  chat_id bigint;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'application.approve')
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select cs.chat_id
  into chat_id
  from public.chat_settings cs
  where cs.chat_id is not null
  order by cs.updated_at desc nulls last, cs.chat_id
  limit 1;

  if chat_id is null then raise exception 'COMMUNITY_CHAT_NOT_CONFIGURED'; end if;
  return chat_id;
end;
$function$;

revoke all on function public.staff_get_community_chat_id()
from public,anon;

grant execute on function public.staff_get_community_chat_id()
to authenticated;
