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

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    u.id,u.telegram_id,'telegram','CLAN_NEWS',v_title,v_body,
    jsonb_build_object(
      'clan_id',actor_clan_id,
      'announcement_id',announcement_id,
      'source','participant_site'
    ),
    'pending',now()
  from public.clan_members cm
  join public.users u on u.id=cm.user_id
  where cm.clan_id=actor_clan_id
    and cm.status='active'
    and cm.user_id<>p_user_id
    and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and not u.is_banned;

  return jsonb_build_object('success',true,'announcement_id',announcement_id,'clan_id',actor_clan_id);
end;
$function$;