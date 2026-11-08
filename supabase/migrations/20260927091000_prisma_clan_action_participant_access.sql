create or replace function public.participant_clan_action(
  p_action text,
  p_target_nickname text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  uid uuid;
begin
  select u.id
    into uid
  from public.users u
  where u.auth_user_id = (select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then
    raise exception 'USER_NOT_LINKED';
  end if;

  perform private.prisma_participant_require_access(uid);

  if upper(trim(p_action)) not in ('KICK','PROMOTE','DEMOTE','TRANSFER','DISBAND') then
    raise exception 'INVALID_ACTION';
  end if;

  return public.mc_clan_action(
    uid,
    upper(trim(p_action)),
    nullif(trim(p_target_nickname), '')
  );
end;
$function$;

grant execute on function public.participant_clan_action(text, text) to authenticated;
revoke execute on function public.participant_clan_action(text, text) from anon;