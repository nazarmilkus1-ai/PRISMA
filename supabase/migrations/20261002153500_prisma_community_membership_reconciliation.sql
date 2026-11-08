-- PRISMA: provide a canonical candidate list for Telegram membership reconciliation.
-- The bot verifies the real Telegram membership and then feeds only state changes
-- back through bot_set_community_membership.

create or replace function public.bot_list_community_membership_candidates()
returns json
language sql
stable
security definer
set search_path=''
as $function$
  select coalesce(
    json_agg(
      json_build_object(
        'tg_id',u.telegram_id,
        'username',u.telegram_username,
        'first_name',u.first_name,
        'last_name',u.last_name,
        'full_name',u.full_name,
        'community_is_member',coalesce(u.community_is_member,false),
        'is_whitelisted',coalesce(u.is_whitelisted,false)
      )
      order by u.telegram_id
    ),
    '[]'::json
  )
  from public.users u
  where u.deleted_at is null
    and u.telegram_id is not null
    and (
      u.is_whitelisted=true
      or (
        u.status='ACCEPTED'::public.application_status
        and u.is_banned=false
        and exists (
          select 1
          from public.applications a
          where a.user_id=u.id
            and a.status='ACCEPTED'::public.application_status
            and not a.is_archived
        )
      )
    );
$function$;

revoke all on function public.bot_list_community_membership_candidates()
from public,anon,authenticated;
grant execute on function public.bot_list_community_membership_candidates()
to service_role;
