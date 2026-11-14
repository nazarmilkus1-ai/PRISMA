-- "Рассылка без анкеты" failed: broadcasts.created_by references admins(id) but the function stored users.id.
create or replace function public.staff_broadcast_onboarding(p_title text, p_body text)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid:=(select auth.uid());
  actor_id uuid;
  admin_row_id uuid;
  broadcast_id uuid;
  recipients integer:=0;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'notification.send')
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select a.id into admin_row_id from public.admins a where a.user_id=actor_id limit 1;

  if char_length(trim(coalesce(p_title,''))) not between 1 and 200 then raise exception 'INVALID_NOTIFICATION_TITLE'; end if;
  if char_length(trim(coalesce(p_body,''))) not between 1 and 4000 then raise exception 'INVALID_NOTIFICATION_BODY'; end if;

  insert into public.broadcasts(created_by,title,body,target_filter,status,started_at,recipients_count)
  values(admin_row_id,trim(p_title),trim(p_body),
    jsonb_build_object('segment','ONBOARDING_BOT_STARTED'),
    'sending',now(),0)
  returning id into broadcast_id;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,attempts
  )
  select
    u.id,u.telegram_id,'telegram','BROADCAST',trim(p_title),trim(p_body),
    jsonb_build_object('broadcast_id',broadcast_id,'segment','ONBOARDING_BOT_STARTED'),
    'pending',0
  from public.users u
  where u.deleted_at is null
    and u.telegram_id is not null
    and u.bot_started_at is not null
    and u.community_is_member=true
    and not exists(select 1 from public.applications a where a.user_id=u.id);

  get diagnostics recipients=row_count;

  update public.broadcasts
  set recipients_count=recipients,updated_at=now()
  where id=broadcast_id;

  return json_build_object(
    'success',true,'broadcast_id',broadcast_id,'recipients',recipients,
    'unreachable_without_bot',(
      select count(*) from public.users u
      where u.deleted_at is null
        and u.community_is_member=true
        and u.bot_started_at is null
        and not exists(select 1 from public.applications a where a.user_id=u.id)
    )
  );
end;
$function$;

revoke all on function public.staff_broadcast_onboarding(text,text) from public,anon;
grant execute on function public.staff_broadcast_onboarding(text,text) to authenticated;
