-- PRISMA v2: staff read contracts for clan registry and Minecraft monitoring.

create or replace function public.staff_list_clans(p_limit integer default 200)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,200),300));
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='clan.view_all' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 return coalesce((
  select json_agg(x order by (x->>'rating')::int desc nulls last) from (
   select json_build_object(
    'id',c.id,'name',c.name,'tag',c.tag,'rating',c.rating,'description',c.description,'type',c.type,'status',c.status,
    'level',c.level,'xp',c.xp,'wins',c.wins,'losses',c.losses,'color',c.color,'avatar_url',c.avatar_url,'created_at',c.created_at,
    'owner',case when o.id is null then null else json_build_object('minecraft_nickname',o.minecraft_nickname,'telegram_username',o.telegram_username,'full_name',o.full_name) end,
    'members',(select coalesce(json_agg(json_build_object('clan_id',cm.clan_id,'user_id',cm.user_id,'role',cm.role,'status',cm.status,'joined_at',cm.joined_at,'users',json_build_object('minecraft_nickname',m.minecraft_nickname,'full_name',m.full_name,'telegram_username',m.telegram_username)) order by cm.joined_at asc),'[]'::json) from public.clan_members cm left join public.users m on m.id=cm.user_id where cm.clan_id=c.id),
    'activity',(select coalesce(json_agg(json_build_object('id',ca.id,'clan_id',ca.clan_id,'user_id',ca.user_id,'kind',ca.kind,'xp',ca.xp,'payload',ca.payload,'created_at',ca.created_at) order by ca.created_at desc),'[]'::json) from (select * from public.clan_activity where clan_id=c.id order by created_at desc limit 200) ca),
    'invitations',(select coalesce(json_agg(json_build_object('id',ci.id,'clan_id',ci.clan_id,'inviter_id',ci.inviter_id,'invitee_id',ci.invitee_id,'status',ci.status,'expires_at',ci.expires_at,'created_at',ci.created_at,'responded_at',ci.responded_at) order by ci.created_at desc),'[]'::json) from (select * from public.clan_invitations where clan_id=c.id order by created_at desc limit 100) ci),
    'wars',(select coalesce(json_agg(json_build_object('id',w.id,'clan_a',w.clan_a,'clan_b',w.clan_b,'status',w.status,'scheduled_at',w.scheduled_at,'winner_clan_id',w.winner_clan_id,'score_a',w.score_a,'score_b',w.score_b,'created_at',w.created_at) order by w.created_at desc),'[]'::json) from (select * from public.clan_wars where clan_a=c.id or clan_b=c.id order by created_at desc limit 100) w),
    'announcements',(select coalesce(json_agg(json_build_object('id',an.id,'clan_id',an.clan_id,'author_id',an.author_id,'title',an.title,'body',an.body,'created_at',an.created_at) order by an.created_at desc),'[]'::json) from (select * from public.clan_announcements where clan_id=c.id order by created_at desc limit 100) an)
   ) x from public.clans c left join public.users o on o.id=c.owner_id
   where c.deleted_at is null order by c.rating desc nulls last limit lim
  ) rows_data
 ),'[]'::json);
end;
$function$;
revoke all on function public.staff_list_clans(integer) from public,anon;
grant execute on function public.staff_list_clans(integer) to authenticated;

create or replace function public.staff_get_monitoring()
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; metrics_data json; events_data json; chat_data json;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='player.view' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 select coalesce(json_agg(to_jsonb(x) order by x.recorded_at desc),'[]'::json) into metrics_data from (
  select id,server_name,online_players,max_players,tps,cpu_percent,memory_used_mb,memory_max_mb,uptime_seconds,version,world,recorded_at from public.server_metrics order by recorded_at desc limit 120
 ) x;
 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json) into events_data from (
  select id,event_type,nickname,command,message,world,created_at,user_id from public.minecraft_events order by created_at desc limit 60
 ) x;
 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json) into chat_data from (
  select id,user_id,message,world,created_at from public.chat_logs order by created_at desc limit 30
 ) x;
 return json_build_object('metrics',metrics_data,'events',events_data,'chat_logs',chat_data);
end;
$function$;
revoke all on function public.staff_get_monitoring() from public,anon;
grant execute on function public.staff_get_monitoring() to authenticated;
