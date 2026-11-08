-- Atomic participant poll voting gateway.
create or replace function private.prisma_participant_vote_poll_many(
  p_user_id uuid,
  p_poll_id uuid,
  p_option_ids uuid[]
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  poll public.polls%rowtype;
  option_count integer;
  existing_count integer;
  requested_count integer;
begin
  perform private.prisma_participant_require_access(p_user_id);

  if p_option_ids is null then raise exception 'INVALID_OPTIONS'; end if;

  select count(*)::integer into requested_count
  from (select distinct x from unnest(p_option_ids) as x where x is not null) d;

  if requested_count < 1 or requested_count > 20 then raise exception 'INVALID_OPTIONS'; end if;

  select * into poll from public.polls where id=p_poll_id for update;
  if not found or poll.status <> 'active' then raise exception 'POLL_NOT_ACTIVE'; end if;

  if poll.expires_at is not null and poll.expires_at <= now() then
    update public.polls set status='finished',finished_at=now() where id=poll.id;
    raise exception 'POLL_EXPIRED';
  end if;

  if not poll.allow_multiple and requested_count<>1 then raise exception 'MULTIPLE_OPTIONS_NOT_ALLOWED'; end if;
  if poll.allow_multiple and requested_count>coalesce(poll.max_choices,1) then raise exception 'MAX_CHOICES_REACHED'; end if;

  select count(*)::integer into option_count
  from (
    select distinct x as option_id from unnest(p_option_ids) as x where x is not null
  ) selected
  left join public.poll_options po on po.id=selected.option_id and po.poll_id=p_poll_id
  where po.id is null;

  if option_count>0 then raise exception 'INVALID_OPTION'; end if;

  select count(*)::integer into existing_count
  from public.poll_votes where poll_id=p_poll_id and user_id=p_user_id;

  if existing_count>0 then
    if not poll.allow_change_vote then raise exception 'CANNOT_CHANGE_VOTE'; end if;
    delete from public.poll_votes where poll_id=p_poll_id and user_id=p_user_id;
  end if;

  insert into public.poll_votes(poll_id,option_id,user_id)
  select p_poll_id,selected.option_id,p_user_id
  from (select distinct x as option_id from unnest(p_option_ids) as x where x is not null) selected;

  return jsonb_build_object('success',true,'poll_id',p_poll_id,'options',requested_count);
end;
$function$;

create or replace function public.participant_vote_poll_many(
  p_poll_id uuid,p_option_ids uuid[]
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_vote_poll_many(uid,p_poll_id,p_option_ids);
end;
$function$;

revoke all on function public.participant_vote_poll_many(uuid,uuid[]) from public,anon;
grant execute on function public.participant_vote_poll_many(uuid,uuid[]) to authenticated;