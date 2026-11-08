create or replace function public.mc_list_clan_announcements(p_user_id uuid)
returns json
language sql stable security definer set search_path=''
as $function$
select json_build_object(
  'announcements',
  coalesce((
    select json_agg(x order by x.created_at desc)
    from (
      select a.id,a.clan_id,a.title,a.body,a.created_at,u.minecraft_nickname author_nickname
      from public.clan_members cm
      join public.clan_announcements a on a.clan_id=cm.clan_id
      left join public.users u on u.id=a.author_id
      where cm.user_id=p_user_id and cm.status='active'
      order by a.created_at desc
      limit 20
    ) x
  ),'[]'::json)
);
$function$;

create or replace function public.mc_create_clan_announcement(
  p_user_id uuid,p_title text,p_body text
)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
begin
  return private.prisma_participant_create_clan_announcement(p_user_id,p_title,p_body);
end;
$function$;

revoke execute on function public.mc_list_clan_announcements(uuid) from public,anon,authenticated;
grant execute on function public.mc_list_clan_announcements(uuid) to service_role;
revoke execute on function public.mc_create_clan_announcement(uuid,text,text) from public,anon,authenticated;
grant execute on function public.mc_create_clan_announcement(uuid,text,text) to service_role;