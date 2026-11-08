-- Public read gateways for intentionally public server/map data. No browser service-role access.

create or replace function public.get_public_server_status()
returns jsonb
language sql
security definer set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_build_object(
        'node_id',node_id,'display_name',display_name,'status',status,'version',version,
        'online_players',online_players,'max_players',max_players,'last_heartbeat_at',last_heartbeat_at
      )
      from public.server_nodes where node_id='primary' limit 1
    ),
    jsonb_build_object(
      'node_id','primary','display_name','PRISMA','status','OFFLINE','version',null,
      'online_players',0,'max_players',0,'last_heartbeat_at',null
    )
  );
$function$;

create or replace function public.get_public_map_data()
returns jsonb
language sql
security definer set search_path=''
as $function$
  select jsonb_build_object(
    'markers',coalesce((
      select jsonb_agg(to_jsonb(m) order by m.kind,m.title)
      from (
        select id,kind,title,description,world,x,y,z,icon,color,clan_id,event_id,visible
        from public.map_markers where visible=true
      ) m
    ),'[]'::jsonb),
    'villages',coalesce((
      select jsonb_agg(to_jsonb(v) order by v.created_at)
      from (
        select cv.id,cv.clan_id,cv.name,cv.world,cv.center_x,cv.center_y,cv.center_z,cv.radius,cv.status,cv.created_at,
               jsonb_build_object('name',c.name,'tag',c.tag,'color',c.color) as clans
        from public.clan_villages cv
        join public.clans c on c.id=cv.clan_id
        where cv.status='active' and c.deleted_at is null and c.status='active'
      ) v
    ),'[]'::jsonb)
  );
$function$;

revoke all on function public.get_public_server_status() from public,anon,authenticated;
grant execute on function public.get_public_server_status() to anon,authenticated;

revoke all on function public.get_public_map_data() from public,anon,authenticated;
grant execute on function public.get_public_map_data() to anon,authenticated;
