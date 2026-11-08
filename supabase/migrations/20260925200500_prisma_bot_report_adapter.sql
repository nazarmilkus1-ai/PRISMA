create or replace function public.bot_create_report(p_reporter_tg_id bigint,p_target_tg_id bigint,p_reason text) returns json
language plpgsql security definer set search_path=''
as $prisma$
declare reporter uuid; target_nick text;
begin
 select id into reporter from public.users where telegram_id=p_reporter_tg_id and deleted_at is null limit 1;
 select minecraft_nickname into target_nick from public.users where telegram_id=p_target_tg_id and deleted_at is null and status='ACCEPTED'::public.application_status limit 1;
 if reporter is null or target_nick is null then raise exception 'USER_NOT_FOUND'; end if;
 return private.prisma_create_report(reporter,'PLAYER',target_nick,p_reason);
end;
$prisma$;
revoke all on function public.bot_create_report(bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.bot_create_report(bigint,bigint,text) to service_role;