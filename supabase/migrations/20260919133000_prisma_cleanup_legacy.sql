create or replace function public.bot_approve_application(
  p_application_id uuid,
  p_admin_tg_id bigint
)
returns json
language plpgsql
security definer
set search_path='public'
as $$
declare
  aid uuid;
  uid uuid;
  perm boolean;
begin
  select a.id, a.user_id
    into aid, uid
  from public.applications a
  where a.id = p_application_id
    and a.status = 'PENDING'
    and not a.is_archived;

  if aid is null then
    raise exception 'APPLICATION_NOT_FOUND';
  end if;

  select exists(
    select 1
    from public.admins a
    join public.users u on u.id = a.user_id
    join public.role_permissions rp on rp.role_id = a.role_id
    join public.permissions p on p.id = rp.permission_id
    where u.telegram_id = p_admin_tg_id
      and p.key = 'application.approve'
  ) into perm;

  if not perm then
    raise exception 'ADMIN_LACKS_PERMISSION';
  end if;

  update public.applications
     set status = 'ACCEPTED',
         reviewed_by_tg_id = p_admin_tg_id,
         reviewed_at = now(),
         updated_at = now()
   where id = aid;

  update public.users
     set status = 'ACCEPTED',
         is_whitelisted = true,
         updated_at = now()
   where id = uid;

  insert into public.application_history(application_id, action, actor_tg_id, reason)
  values (aid, 'ACCEPTED', p_admin_tg_id, null);

  return json_build_object(
    'success', true,
    'application_id', aid,
    'user_id', uid
  );
end;
$$;

revoke all on function public.bot_approve_application(uuid,bigint) from public, anon, authenticated;
grant execute on function public.bot_approve_application(uuid,bigint) to service_role;

drop function if exists public.bot_create_report_idempotent(bigint,bigint,text,text,text,uuid);
drop function if exists public.bot_create_report_v2(bigint,bigint,text,text,text,jsonb,jsonb,timestamp with time zone);
drop function if exists public.bot_create_clan_v2(bigint,text,text);
drop function if exists public.create_user_with_application(bigint,text,text,date,text,text,text,text);
drop function if exists public.award_achievement(uuid,text);
drop function if exists public.bot_get_latest_news(integer);

delete from public.login_codes
 where status in ('verified','expired')
    or expires_at < now();
