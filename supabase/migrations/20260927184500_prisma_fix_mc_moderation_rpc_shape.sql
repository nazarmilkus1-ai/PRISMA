-- PRISMA v2: align trusted Minecraft moderation RPC return shapes
-- with SupabaseClient.postRpcSync(), which expects a JSON object.

create or replace function public.mc_get_pending_moderation(p_limit integer default 100)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  lim integer := greatest(1, least(coalesce(p_limit,100),500));
  pending json;
begin
  select coalesce(json_agg(
    json_build_object(
      'id',m.id,'type',m.type,'reason',m.reason,
      'duration_minutes',m.duration_minutes,'expires_at',m.expires_at,
      'target_id',m.target_id,'minecraft_nickname',u.minecraft_nickname
    ) order by m.created_at asc
  ),'[]'::json)
  into pending
  from (
    select *
    from public.moderation_logs
    where applied_at is null
      and type in ('WARN','KICK','MUTE','BAN','UNMUTE','UNBAN','WHITELIST','UNWHITELIST')
    order by created_at asc
    limit lim
  ) m
  left join public.users u on u.id=m.target_id;

  return json_build_object('data',pending);
end;
$function$;

revoke all on function public.mc_get_pending_moderation(integer) from public,anon,authenticated;
grant execute on function public.mc_get_pending_moderation(integer) to service_role;

drop function if exists public.mc_mark_moderation_applied(uuid);

create function public.mc_mark_moderation_applied(p_log_id uuid)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare changed boolean;
begin
  update public.moderation_logs
  set applied_at=coalesce(applied_at,now())
  where id=p_log_id and applied_at is null;
  changed:=found;
  return json_build_object('success',changed,'id',p_log_id);
end;
$function$;

revoke all on function public.mc_mark_moderation_applied(uuid) from public,anon,authenticated;
grant execute on function public.mc_mark_moderation_applied(uuid) to service_role;
