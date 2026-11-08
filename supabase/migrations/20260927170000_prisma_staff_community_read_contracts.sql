-- PRISMA v2: authenticated staff community read contracts.

create or replace function public.staff_list_news(p_limit integer default 200)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,200),500));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='news.manage' limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
  return coalesce((select json_agg(row_data order by created_sort desc) from (
    select json_build_object('id',n.id,'title',n.title,'body',n.body,'kind',n.kind,'is_published',n.is_published,'created_by_name',n.created_by_name,'created_at',n.created_at,'published_at',n.published_at) row_data,n.created_at created_sort
    from public.news n order by n.created_at desc limit lim
  ) q),'[]'::json);
end;
$function$;
revoke all on function public.staff_list_news(integer) from public,anon;
grant execute on function public.staff_list_news(integer) to authenticated;

create or replace function public.staff_list_polls(p_limit integer default 200)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,200),500)); polls_data json; rating_data json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='poll.manage' limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
  select coalesce(json_agg(x order by x->>'created_at' desc),'[]'::json) into polls_data from (
    select json_build_object(
      'id',p.id,'question',p.question,'is_active',p.is_active,'status',p.status,'closes_at',p.closes_at,'expires_at',p.expires_at,'created_at',p.created_at,
      'options',(select coalesce(json_agg(json_build_object('id',o.id,'text',o.text,'position',o.position,'votes',(select count(*) from public.poll_votes v where v.poll_id=p.id and v.option_id=o.id)) order by o.position),'[]'::json) from public.poll_options o where o.poll_id=p.id)
    ) x from public.polls p where p.kind='POLL' order by p.created_at desc limit lim
  ) rows_data;
  select json_build_object('average',coalesce(avg(pr.value),0),'total',count(pr.value)) into rating_data
  from public.poll_ratings pr join public.polls p on p.id=pr.poll_id
  where p.kind='SERVER_RATING' and p.is_active=true;
  return json_build_object('polls',polls_data,'server_rating',rating_data);
end;
$function$;
revoke all on function public.staff_list_polls(integer) from public,anon;
grant execute on function public.staff_list_polls(integer) to authenticated;

create or replace function public.staff_list_events(p_limit integer default 100)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,100),200));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='event.manage' limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
  return coalesce((select json_agg(x order by x->>'starts_at' desc nulls last) from (
    select json_build_object(
      'id',e.id,'slug',e.slug,'title',e.title,'description',e.description,'status',e.status,'starts_at',e.starts_at,'ends_at',e.ends_at,
      'registration_deadline',e.registration_deadline,'max_participants',e.max_participants,'reward_config',e.reward_config,'created_at',e.created_at,'updated_at',e.updated_at,
      'participants',(select coalesce(json_agg(json_build_object('event_id',ep.event_id,'user_id',ep.user_id,'score',ep.score,'placement',ep.placement,'registered_at',ep.registered_at,'nickname',coalesce(u.minecraft_nickname,u.full_name,'Игрок')) order by ep.placement asc nulls last,ep.score desc nulls last),'[]'::json)
        from public.event_participants ep left join public.users u on u.id=ep.user_id where ep.event_id=e.id)
    ) x from public.events e order by e.starts_at desc nulls last limit lim
  ) rows_data),'[]'::json);
end;
$function$;
revoke all on function public.staff_list_events(integer) from public,anon;
grant execute on function public.staff_list_events(integer) to authenticated;
