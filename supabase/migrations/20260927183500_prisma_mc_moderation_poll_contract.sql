-- PRISMA v2: trusted Minecraft plugin moderation polling contracts.

create or replace function public.mc_get_pending_moderation(p_limit integer default 100)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  lim integer := greatest(1, least(coalesce(p_limit,100),500));
begin
  return coalesce((
    select json_agg(
      json_build_object(
        'id',m.id,'type',m.type,'reason',m.reason,
        'duration_minutes',m.duration_minutes,'expires_at',m.expires_at,
        'target_id',m.target_id,'minecraft_nickname',u.minecraft_nickname
      ) order by m.created_at asc
    )
    from (
      select *
      from public.moderation_logs
      where applied_at is null
        and type in ('WARN','KICK','MUTE','BAN','UNMUTE','UNBAN','WHITELIST','UNWHITELIST')
      order by created_at asc
      limit lim
    ) m
    left join public.users u on u.id=m.target_id
  ),'[]'::json);
end;
$function$;

revoke all on function public.mc_get_pending_moderation(integer) from public,anon,authenticated;
grant execute on function public.mc_get_pending_moderation(integer) to service_role;

create or replace function public.mc_mark_moderation_applied(p_log_id uuid)
returns boolean
language plpgsql
security definer
set search_path=''
as $function$
begin
  update public.moderation_logs
  set applied_at=coalesce(applied_at,now())
  where id=p_log_id and applied_at is null;
  return found;
end;
$function$;

revoke all on function public.mc_mark_moderation_applied(uuid) from public,anon,authenticated;
grant execute on function public.mc_mark_moderation_applied(uuid) to service_role;
