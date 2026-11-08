create or replace function public.bot_relationship_info(p_tg_id bigint)
returns json
language sql
stable
security definer
set search_path=public
as $function$
 select coalesce((
  select json_build_object(
   'active',true,
   'partner_tg_id',p.telegram_id,
   'partner_name',p.full_name,
   'partner_username',p.telegram_username,
   'started_at',r.started_at
  )
  from public.users u
  join public.relationships r on r.status='ACTIVE' and (r.user_a_id=u.id or r.user_b_id=u.id)
  join public.users p on p.id=case when r.user_a_id=u.id then r.user_b_id else r.user_a_id end
  where u.telegram_id=p_tg_id and u.deleted_at is null and p.deleted_at is null
  limit 1
 ),json_build_object('active',false));
$function$;