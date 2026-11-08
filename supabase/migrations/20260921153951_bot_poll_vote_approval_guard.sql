-- Voting RPC is server-side only and also verifies the caller is an approved player.
create or replace function public.bot_vote_poll(
  p_poll_id uuid,
  p_option_id uuid,
  p_tg_id bigint
)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  uid uuid;
  p record;
  existing integer;
  caller_status text;
begin
  select u.id, upper(u.status::text)
    into uid, caller_status
  from public.users u
  where u.telegram_id = p_tg_id
    and u.deleted_at is null
  limit 1;

  if uid is null then
    raise exception 'USER_NOT_FOUND';
  end if;

  if caller_status <> 'ACCEPTED' then
    raise exception 'USER_NOT_APPROVED';
  end if;

  select *
    into p
  from public.polls
  where id = p_poll_id
  for update;

  if not found or p.status <> 'active' then
    raise exception 'POLL_NOT_ACTIVE';
  end if;

  if p.expires_at is not null and p.expires_at <= now() then
    update public.polls
    set status = 'finished',
        finished_at = now()
    where id = p.id;
    raise exception 'POLL_EXPIRED';
  end if;

  if not exists (
    select 1
    from public.poll_options
    where id = p_option_id
      and poll_id = p_poll_id
  ) then
    raise exception 'INVALID_OPTION';
  end if;

  select count(*)
    into existing
  from public.poll_votes
  where poll_id = p_poll_id
    and user_id = uid;

  if not p.allow_multiple and existing > 0 then
    if not p.allow_change_vote then
      raise exception 'CANNOT_CHANGE_VOTE';
    end if;

    delete from public.poll_votes
    where poll_id = p_poll_id
      and user_id = uid;
  elsif p.allow_multiple and existing >= coalesce(p.max_choices, 1) then
    raise exception 'MAX_CHOICES_REACHED';
  end if;

  insert into public.poll_votes(poll_id, option_id, user_id)
  values(p_poll_id, p_option_id, uid);

  return json_build_object('success', true);
end;
$function$;

revoke execute on function public.bot_vote_poll(uuid, uuid, bigint) from public, anon, authenticated;
grant execute on function public.bot_vote_poll(uuid, uuid, bigint) to service_role;
