create or replace function public.bot_list_clans()
returns json language sql security definer set search_path=public as $$
 select coalesce(json_agg(x order by x.rating desc,x.level desc,x.id),'[]'::json)
 from (select id,name,tag,rating,level,xp,balance,wins,losses,description from public.clans where deleted_at is null and status='active' limit 100) x $$;
create or replace function public.bot_join_clan(p_tg_id bigint,p_name text)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid; begin select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
if uid is null then raise exception 'USER_NOT_FOUND'; end if; return public.mc_join_clan(uid,p_name); end $$;
create or replace function public.bot_leave_clan(p_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid; begin select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
if uid is null then raise exception 'USER_NOT_FOUND'; end if; return public.mc_leave_clan(uid); end $$;
create or replace function public.bot_disband_clan(p_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid; begin select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
if uid is null then raise exception 'USER_NOT_FOUND'; end if; return public.mc_clan_action(uid,'DISBAND',null); end $$;
revoke execute on function public.bot_list_clans() from public,anon,authenticated;
revoke execute on function public.bot_join_clan(bigint,text) from public,anon,authenticated;
revoke execute on function public.bot_leave_clan(bigint) from public,anon,authenticated;
revoke execute on function public.bot_disband_clan(bigint) from public,anon,authenticated;
grant execute on function public.bot_list_clans() to service_role;
grant execute on function public.bot_join_clan(bigint,text) to service_role;
grant execute on function public.bot_leave_clan(bigint) to service_role;
grant execute on function public.bot_disband_clan(bigint) to service_role;