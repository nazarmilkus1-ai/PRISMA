-- PRISMA v2: authenticated staff read gateway for chat settings.

create or replace function public.staff_get_chat_settings()
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and p.key='settings.view'
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  return coalesce((
    select json_agg(to_jsonb(c) order by c.chat_id)
    from (
      select chat_id,anti_links,anti_caps,anti_flood,anti_media,anti_profanity,
             anti_mentions,anti_raid,caps_threshold,flood_messages,flood_window_seconds,
             links_action,caps_action,flood_action,profanity_action,media_action,repeat_warn_action
      from public.chat_settings
      where chat_id is not null
    ) c
  ), '[]'::json);
end;
$function$;

revoke all on function public.staff_get_chat_settings() from public,anon;
grant execute on function public.staff_get_chat_settings() to authenticated;
