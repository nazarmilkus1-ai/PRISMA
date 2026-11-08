create or replace function public.mc_cancel_clan_invite(
  p_user_id uuid,
  p_invite_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_clan_id uuid;
  v_role text;
  v_invitee_id uuid;
  v_clan_name text;
begin
  select cm.clan_id, cm.role, c.name
    into v_clan_id, v_role, v_clan_name
  from public.clan_members cm
  join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id
    and cm.status='active'
    and c.status='active'
    and c.deleted_at is null
  limit 1;

  if v_clan_id is null then raise exception 'NO_CLAN'; end if;
  if v_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;

  select ci.invitee_id
    into v_invitee_id
  from public.clan_invitations ci
  where ci.id=p_invite_id
    and ci.clan_id=v_clan_id
    and ci.status='pending'
    and ci.expires_at>now()
  limit 1;

  if v_invitee_id is null then raise exception 'INVITE_NOT_FOUND'; end if;

  update public.clan_invitations
  set status='cancelled', responded_at=now()
  where id=p_invite_id
    and clan_id=v_clan_id
    and status='pending';

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    target.id,
    target.telegram_id,
    'telegram',
    'CLAN',
    'Приглашение в клан отменено',
    'Приглашение в клан "'||v_clan_name||'" было отменено.',
    jsonb_build_object(
      'clan_id',v_clan_id,
      'invite_id',p_invite_id,
      'source','participant_site'
    ),
    'pending',
    now()
  from public.users target
  where target.id=v_invitee_id
    and target.deleted_at is null
    and target.status='ACCEPTED'::public.application_status
    and not target.is_banned;

  return jsonb_build_object('success',true,'invite_id',p_invite_id);
end;
$function$;

create or replace function public.participant_cancel_clan_invite(
  p_invite_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return public.mc_cancel_clan_invite(uid,p_invite_id);
end;
$function$;

create or replace function public.participant_list_clan_invites()
returns jsonb
language sql
security definer
set search_path=''
as $function$
with me as (
  select u.id as user_id, u.clan_id
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1
),
incoming as (
  select
    ci.id,
    ci.clan_id,
    c.name,
    c.tag,
    inv.minecraft_nickname as inviter_nickname,
    ci.expires_at,
    ci.created_at
  from public.clan_invitations ci
  join public.clans c on c.id=ci.clan_id
  join public.users inv on inv.id=ci.inviter_id
  where ci.invitee_id=(select user_id from me)
    and ci.status='pending'
    and ci.expires_at>now()
),
outgoing as (
  select
    ci.id,
    ci.clan_id,
    target.id as invitee_id,
    target.minecraft_nickname as invitee_nickname,
    ci.expires_at,
    ci.created_at
  from public.clan_invitations ci
  join me on true
  join public.clan_members cm
    on cm.clan_id=ci.clan_id
    and cm.user_id=me.user_id
    and cm.status='active'
  join public.users target on target.id=ci.invitee_id
  where ci.clan_id=me.clan_id
    and cm.role in ('owner','officer')
    and ci.status='pending'
    and ci.expires_at>now()
)
select jsonb_build_object(
  'incoming',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from incoming i),'[]'::jsonb),
  'outgoing',coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from outgoing o),'[]'::jsonb)
);
$function$;

revoke all on function public.mc_cancel_clan_invite(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mc_cancel_clan_invite(uuid,uuid) to service_role;

revoke all on function public.participant_cancel_clan_invite(uuid) from public,anon;
grant execute on function public.participant_cancel_clan_invite(uuid) to authenticated;

revoke all on function public.participant_list_clan_invites() from public,anon;
grant execute on function public.participant_list_clan_invites() to authenticated;
