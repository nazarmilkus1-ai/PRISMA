-- PRISMA v2 report creation core.
-- Browser/Admin/Bot adapters can converge on this transaction-safe domain function.

create or replace function private.prisma_create_report(
  p_user_id uuid,
  p_type text,
  p_target_nickname text,
  p_description text
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
declare
  reporter uuid := p_user_id;
  target_nick text := nullif(trim(p_target_nickname),'');
  rid uuid;
begin
  if reporter is null then raise exception 'USER_NOT_FOUND'; end if;
  if not exists(select 1 from public.users u where u.id=reporter and u.deleted_at is null) then
    raise exception 'USER_NOT_FOUND';
  end if;

  if upper(trim(p_type)) not in ('PLAYER','BUG','SERVER') then raise exception 'INVALID_REPORT_TYPE'; end if;
  if p_description is null or char_length(trim(p_description)) not between 3 and 4000 then raise exception 'INVALID_REASON'; end if;

  if upper(trim(p_type))='PLAYER' then
    if target_nick is null or char_length(target_nick)>32 then raise exception 'TARGET_REQUIRED'; end if;
    select u.minecraft_nickname into target_nick
    from public.users u
    where u.deleted_at is null
      and u.status='ACCEPTED'::public.application_status
      and lower(trim(coalesce(u.minecraft_nickname,'')))=lower(target_nick)
      and not u.is_banned
      and u.id<>reporter
    limit 1;
    if target_nick is null then raise exception 'TARGET_INVALID'; end if;

    if exists(
      select 1 from public.reports r
      where r.user_id=reporter
        and r.type='PLAYER'
        and r.status in ('OPEN'::public.report_status,'IN_REVIEW'::public.report_status)
        and lower(coalesce(r.target_nickname,''))=lower(target_nick)
    ) then raise exception 'DUPLICATE_OPEN_REPORT'; end if;
  end if;

  insert into public.reports(user_id,type,target_nickname,description,status,category)
  values(
    reporter,
    upper(trim(p_type))::public.report_type,
    case when upper(trim(p_type))='PLAYER' then target_nick else null end,
    trim(p_description),
    'OPEN'::public.report_status,
    upper(trim(p_type))
  ) returning id into rid;

  return json_build_object('success',true,'report_id',rid);
end;
$prisma$;

revoke all on function private.prisma_create_report(uuid,text,text,text) from public,anon,authenticated;
grant execute on function private.prisma_create_report(uuid,text,text,text) to service_role;

create or replace function public.participant_create_report(
  p_type text,
  p_target_nickname text,
  p_description text
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=auth.uid() and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_create_report(uid,p_type,p_target_nickname,p_description);
end;
$prisma$;

revoke all on function public.participant_create_report(text,text,text) from public,anon;
grant execute on function public.participant_create_report(text,text,text) to authenticated;
