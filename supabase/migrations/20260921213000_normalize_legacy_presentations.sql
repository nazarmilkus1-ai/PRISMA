
-- Keep the transfer data in the normal PRISMA presentation.
create or replace function public.bot_list_iris_clan_archive()
returns json
language sql
security definer
set search_path=public
as $function$
select '[]'::json;
$function$;

create or replace function public.bot_list_marriages()
returns json
language sql
security definer
set search_path=public
as $function$
with current_rows as (
  select ia.source_position,
         coalesce(ia.partner_a_tg_id,ua.telegram_id) user_a,
         coalesce(ia.partner_a_name,ua.full_name,ua.telegram_username) user_a_name,
         coalesce(ia.partner_a_username,ua.telegram_username) user_a_username,
         coalesce(ia.partner_b_tg_id,ub.telegram_id) user_b,
         coalesce(ia.partner_b_name,ub.full_name,ub.telegram_username) user_b_name,
         coalesce(ia.partner_b_username,ub.telegram_username) user_b_username,
         m.married_at,
         ia.green_wedding,
         'ACTIVE'::text status
  from public.marriages m
  join public.users ua on ua.id=m.user_a_id
  join public.users ub on ub.id=m.user_b_id
  left join public.iris_marriage_import_archive ia
    on ia.chat_id=-1003727618185 and ia.source_position=m.source_position
  where m.status='ACTIVE'
),
historical as (
  select ia.source_position,
         ia.partner_a_tg_id user_a,ia.partner_a_name user_a_name,ia.partner_a_username user_a_username,
         ia.partner_b_tg_id user_b,ia.partner_b_name user_b_name,ia.partner_b_username user_b_username,
         case ia.source_position
           when 1 then timestamptz '2026-09-21 17:45:00+00' - interval '4 months 3 days'
           when 5 then timestamptz '2026-09-21 17:45:00+00' - interval '11 days 16 hours'
           when 6 then timestamptz '2026-09-21 17:45:00+00' - interval '11 days 11 hours'
           when 7 then timestamptz '2026-09-21 17:45:00+00' - interval '11 days 10 hours'
           when 9 then timestamptz '2026-09-21 17:45:00+00' - interval '2 days 19 hours'
           else timestamptz '2026-09-21 17:45:00+00'
         end married_at,
         ia.green_wedding,'ACTIVE'::text status
  from public.iris_marriage_import_archive ia
  where ia.chat_id=-1003727618185
    and not exists(select 1 from current_rows c where c.source_position=ia.source_position)
),
rows as (
  select * from current_rows
  union all
  select * from historical
)
select coalesce(json_agg(r order by r.source_position),'[]'::json)
from rows r;
$function$;

create or replace function public.bot_chat_stats(p_chat_id bigint)
returns json
language sql
security definer
set search_path=public
as $function$
select json_build_object(
  'total_messages', public.bot_chat_top_total(p_chat_id,null),
  'current_messages',
    greatest(
      0,
      coalesce((select sum(a.message_count)::integer
                from public.telegram_chat_activity a
                where a.chat_id=p_chat_id),0)
      - coalesce((select s.baseline_live_messages
                  from public.telegram_chat_import_state s where s.chat_id=p_chat_id),0)
    ),
  'legacy_messages',
    coalesce((select s.source_total_messages
              from public.telegram_chat_import_state s where s.chat_id=p_chat_id),0),
  'unique_users',
    coalesce((select count(*)::integer
              from public.iris_chat_stats_archive s
              where s.chat_id=p_chat_id and s.snapshot_kind='all_time'),0),
  'source',
    coalesce((select s.source from public.telegram_chat_import_state s where s.chat_id=p_chat_id),'PRISMA'),
  'source_total_messages',
    coalesce((select s.source_total_messages from public.telegram_chat_import_state s where s.chat_id=p_chat_id),0),
  'source_snapshot_at',
    (select s.snapshot_at from public.telegram_chat_import_state s where s.chat_id=p_chat_id)
);
$function$;
