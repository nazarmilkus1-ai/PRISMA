create or replace function public.mc_list_clan_invites(p_user_id uuid)
returns json language sql stable security definer set search_path=''
as $$
select json_build_object('invites',coalesce(json_agg(row_to_json(i) order by i.created_at desc),'[]'::json))
from (
  select ci.id,ci.clan_id,c.name,c.tag,ci.inviter_id,u.minecraft_nickname as inviter_nickname,
         ci.expires_at,ci.created_at
  from public.clan_invitations ci
  join public.clans c on c.id=ci.clan_id
  left join public.users u on u.id=ci.inviter_id
  where ci.invitee_id=p_user_id and ci.status='pending' and ci.expires_at>now()
) i;
$$;
revoke execute on function public.mc_list_clan_invites(uuid) from public;
grant execute on function public.mc_list_clan_invites(uuid) to service_role;
