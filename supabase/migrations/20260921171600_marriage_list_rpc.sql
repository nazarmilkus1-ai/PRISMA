create or replace function public.bot_list_marriages()
returns json language sql stable security definer set search_path=public as $$
select coalesce(json_agg(json_build_object(
  'user_a',ua.telegram_id,'user_a_name',ua.full_name,'user_a_username',ua.telegram_username,
  'user_b',ub.telegram_id,'user_b_name',ub.full_name,'user_b_username',ub.telegram_username,
  'married_at',m.married_at
) order by m.married_at),'[]'::json)
from public.marriages m
join public.users ua on ua.id=m.user_a_id
join public.users ub on ub.id=m.user_b_id
where m.status='ACTIVE' and ua.deleted_at is null and ub.deleted_at is null;
$$;
revoke execute on function public.bot_list_marriages() from public,anon,authenticated;
grant execute on function public.bot_list_marriages() to service_role;