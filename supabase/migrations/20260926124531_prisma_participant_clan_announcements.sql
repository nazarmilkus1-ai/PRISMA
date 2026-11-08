CREATE OR REPLACE FUNCTION private.prisma_participant_create_clan_announcement(
  p_user_id uuid,
  p_title text,
  p_body text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  actor_clan_id uuid;
  v_title text := trim(coalesce(p_title,''));
  v_body text := trim(coalesce(p_body,''));
  announcement_id uuid;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select cm.clan_id
    into actor_clan_id
  from public.clan_members cm
  where cm.user_id=p_user_id
    and cm.status='active'
    and cm.role in ('owner','officer')
  limit 1;

  if actor_clan_id is null then raise exception 'NO_CLAN_PERMISSION'; end if;
  if char_length(v_title)<3 or char_length(v_title)>120
     or char_length(v_body)<3 or char_length(v_body)>3000
    then raise exception 'INVALID_ANNOUNCEMENT'; end if;

  insert into public.clan_announcements(clan_id,author_id,title,body)
  values(actor_clan_id,p_user_id,v_title,v_body)
  returning id into announcement_id;

  return jsonb_build_object('success',true,'announcement_id',announcement_id,'clan_id',actor_clan_id);
end;
$function$;

CREATE OR REPLACE FUNCTION private.prisma_participant_delete_clan_announcement(
  p_user_id uuid,
  p_announcement_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  actor_clan_id uuid;
  target_clan_id uuid;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select cm.clan_id
    into actor_clan_id
  from public.clan_members cm
  where cm.user_id=p_user_id
    and cm.status='active'
    and cm.role in ('owner','officer')
  limit 1;

  if actor_clan_id is null then raise exception 'NO_CLAN_PERMISSION'; end if;

  select clan_id into target_clan_id
  from public.clan_announcements
  where id=p_announcement_id;

  if target_clan_id is null then raise exception 'ANNOUNCEMENT_NOT_FOUND'; end if;
  if target_clan_id<>actor_clan_id then raise exception 'NO_CLAN_PERMISSION'; end if;

  delete from public.clan_announcements where id=p_announcement_id;

  return jsonb_build_object('success',true,'announcement_id',p_announcement_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.participant_create_clan_announcement(
  p_title text,
  p_body text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_create_clan_announcement(uid,p_title,p_body);
end;
$function$;

CREATE OR REPLACE FUNCTION public.participant_delete_clan_announcement(
  p_announcement_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_delete_clan_announcement(uid,p_announcement_id);
end;
$function$;

revoke all on function public.participant_create_clan_announcement(text,text) from public;
grant execute on function public.participant_create_clan_announcement(text,text) to authenticated;

revoke all on function public.participant_delete_clan_announcement(uuid) from public;
grant execute on function public.participant_delete_clan_announcement(uuid) to authenticated;