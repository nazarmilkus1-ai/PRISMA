-- PRISMA v2: participant appeal gateways.
-- punishment_appeals has deny-all RLS, so browser access must stay inside
-- authenticated participant functions that derive identity from auth.uid().

create or replace function public.participant_get_appeals()
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 uid uuid;
 appeals_data json;
 punishments_data json;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into uid from public.users u where u.auth_user_id=actor_uid and u.deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;

 select coalesce(json_agg(json_build_object(
   'id',pa.id,'punishment_id',pa.punishment_id,'reason',pa.reason,'status',pa.status,
   'reviewed_by_tg_id',pa.reviewed_by_tg_id,'review_note',pa.review_note,
   'created_at',pa.created_at,'updated_at',pa.updated_at,
   'punishment',case when m.id is null then null else json_build_object(
     'id',m.id,'type',m.type,'reason',m.reason,'duration_minutes',m.duration_minutes,
     'expires_at',m.expires_at,'revoked',m.revoked,'status',m.status
   ) end
 ) order by pa.created_at desc),'[]'::json)
 into appeals_data
 from public.punishment_appeals pa
 left join public.moderation_logs m on m.id=pa.punishment_id
 where pa.user_id=uid;

 select coalesce(json_agg(json_build_object(
   'id',m.id,'type',m.type,'reason',m.reason,'duration_minutes',m.duration_minutes,
   'expires_at',m.expires_at,'created_at',m.created_at
 ) order by m.created_at desc),'[]'::json)
 into punishments_data
 from public.moderation_logs m
 where m.target_id=uid and m.revoked=false
   and upper(coalesce(m.status,''))='ACTIVE'
   and m.type in ('WARN','MUTE','BAN','KICK');

 return json_build_object('appeals',appeals_data,'active_punishments',punishments_data);
end;
$function$;

revoke all on function public.participant_get_appeals() from public,anon;
grant execute on function public.participant_get_appeals() to authenticated;

create or replace function public.participant_create_appeal(
 p_punishment_id uuid,
 p_reason text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 uid uuid;
 punishment_id uuid := p_punishment_id;
 punishment public.moderation_logs%rowtype;
 appeal_id uuid;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into uid from public.users u where u.auth_user_id=actor_uid and u.deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;

 if not exists(
  select 1 from public.applications a
  where a.user_id=uid and a.status='ACCEPTED' and not a.is_archived
 ) then raise exception 'PLAYER_ACCESS_REQUIRED'; end if;

 if p_reason is null or char_length(trim(p_reason)) not between 10 and 2000 then raise exception 'INVALID_REASON'; end if;

 if punishment_id is null then
  select m.id into punishment_id
  from public.moderation_logs m
  where m.target_id=uid and m.revoked=false and upper(coalesce(m.status,''))='ACTIVE'
    and m.type in ('WARN','MUTE','BAN','KICK')
  order by m.created_at desc,m.id desc limit 1;
 end if;
 if punishment_id is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

 select * into punishment
 from public.moderation_logs m
 where m.id=punishment_id and m.target_id=uid
 for update;
 if punishment.id is null then raise exception 'PUNISHMENT_NOT_FOUND'; end if;
 if punishment.revoked or upper(coalesce(punishment.status,''))<>'ACTIVE' then raise exception 'PUNISHMENT_NOT_ACTIVE'; end if;

 if exists(
  select 1 from public.punishment_appeals pa
  where pa.user_id=uid and pa.punishment_id=punishment.id and pa.status in ('OPEN','IN_REVIEW')
 ) then raise exception 'APPEAL_ALREADY_EXISTS'; end if;

 insert into public.punishment_appeals(user_id,telegram_id,punishment_id,reason,status)
 values(uid,(select telegram_id from public.users where id=uid),punishment.id,trim(p_reason),'OPEN')
 returning id into appeal_id;

 return json_build_object('success',true,'appeal_id',appeal_id,'punishment_id',punishment.id);
end;
$function$;

revoke all on function public.participant_create_appeal(uuid,text) from public,anon;
grant execute on function public.participant_create_appeal(uuid,text) to authenticated;
