
create or replace function public.bot_list_marriages()
returns json
language sql
security definer
set search_path=public
as $function$
with rows as (
  select ia.source_position,
         case when m.status='ACTIVE' then 'ACTIVE' else 'DIVORCED' end status,
         coalesce(ia.partner_a_tg_id,ua.telegram_id) user_a,
         coalesce(ia.partner_a_name,ua.full_name,ua.telegram_username) user_a_name,
         coalesce(ia.partner_a_username,ua.telegram_username) user_a_username,
         coalesce(ia.partner_b_tg_id,ub.telegram_id) user_b,
         coalesce(ia.partner_b_name,ub.full_name,ub.telegram_username) user_b_name,
         coalesce(ia.partner_b_username,ub.telegram_username) user_b_username,
         m.married_at,
         ia.duration_text,
         ia.green_wedding
  from public.marriages m
  join public.users ua on ua.id=m.user_a_id
  join public.users ub on ub.id=m.user_b_id
  left join public.iris_marriage_import_archive ia
    on ia.chat_id=-1003727618185 and ia.source_position=m.source_position
  where m.status='ACTIVE'

  union all

  select ia.source_position,'DIVORCED',
         ia.partner_a_tg_id,ia.partner_a_name,ia.partner_a_username,
         ia.partner_b_tg_id,ia.partner_b_name,ia.partner_b_username,
         null::timestamptz,ia.duration_text,ia.green_wedding
  from public.iris_marriage_import_archive ia
  where ia.chat_id=-1003727618185
    and not exists (
      select 1 from public.marriages m
      where m.source_position=ia.source_position
    )
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
                  from public.telegram_chat_import_state s
                  where s.chat_id=p_chat_id),0)
    ),
  'imported_users',
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

create or replace function public.bot_get_clan_by_position(p_position integer)
returns json
language sql
security definer
set search_path=public
as $function$
with ranked as (
  select c.*,row_number() over(order by c.rating desc,c.level desc,c.id)::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active'
),
active_pick as (
  select r.* from ranked r
  where r.position=greatest(1,coalesce(p_position,1))
),
picked as (
  select * from active_pick
  union all
  select
    null::uuid id,a.clan_name name,
    ''::text tag,
    null::uuid owner_id,
    null::text description,
    coalesce(a.reputation,0)::integer rating,
    a.founded_at::timestamptz created_at,
    now() updated_at,
    coalesce(a.clan_type,'open')::text type,
    'IMPORTED'::text status,
    1::integer level,0::bigint xp,0::bigint balance,0 wins,0 losses,
    null::text color,null::text avatar_url,null::timestamptz deleted_at,
    'Iris'::text source,a.source_number,
    p_position::integer position
  from public.iris_clan_import_archive a
  where a.source_number=p_position
    and not exists(select 1 from active_pick)
  limit 1
),
base_json as (
  select x.*,
         ia.leader_name ia_leader_name,ia.leader_username ia_leader_username,
         ia.original_members
  from picked x
  left join public.iris_clan_import_archive ia on ia.source_number=x.source_number
)
select case
  when x.id is null and x.source_number is null then json_build_object('error','CLAN_NOT_FOUND')
  else json_build_object(
    'position',x.position,'id',x.id,'name',x.name,'tag',coalesce(x.tag,''),
    'type',x.type,'status',x.status,'owner_id',x.owner_id,
    'description',x.description,'rating',x.rating,'level',x.level,'xp',x.xp,
    'balance',x.balance,'wins',x.wins,'losses',x.losses,'created_at',x.created_at,
    'source',x.source,'source_number',x.source_number,'is_imported',x.status='IMPORTED',
    'leader',json_build_object(
      'tg_id',coalesce(
        (select u.telegram_id from public.users u
         where x.ia_leader_username is not null
           and lower(coalesce(u.telegram_username,''))=lower(x.ia_leader_username)
         order by u.is_whitelisted desc,u.created_at asc limit 1),
        owner.telegram_id
      ),
      'username',coalesce(x.ia_leader_username,owner.telegram_username),
      'full_name',coalesce(x.ia_leader_name,owner.full_name),
      'minecraft_nick',owner.minecraft_nickname
    ),
    'members',coalesce((
      with original as (
        select
          (select u.telegram_id from public.users u
           where nullif(m.value->>'username','') is not null
             and lower(coalesce(u.telegram_username,''))=lower(m.value->>'username')
           order by u.is_whitelisted desc,u.created_at asc limit 1) tg_id,
          nullif(m.value->>'username','') username,
          m.value->>'name' full_name,
          m.value->>'role' role,
          null::timestamptz joined_at,
          nullif(m.value->>'joined_text','') joined_text
        from jsonb_array_elements(coalesce(x.original_members,'[]'::jsonb)) m(value)
      ),
      current_members as (
        select u.telegram_id tg_id,u.telegram_username username,u.full_name,
               cm.role,cm.joined_at,null::text joined_text
        from public.clan_members cm
        join public.users u on u.id=cm.user_id
        where x.id is not null and cm.clan_id=x.id and cm.status='active'
      ),
      merged as (
        select * from original
        union all
        select cm.* from current_members cm
        where not exists (
          select 1 from original o
          where (o.tg_id is not null and o.tg_id=cm.tg_id)
             or (o.username is not null and lower(o.username)=lower(coalesce(cm.username,'')))
        )
      )
      select json_agg(json_build_object(
        'tg_id',m.tg_id,'username',m.username,'full_name',m.full_name,'role',m.role,
        'joined_at',m.joined_at,'joined_text',m.joined_text
      ) order by case when m.role='leader' or m.role='owner' then 0 else 1 end,m.joined_at nulls last,m.full_name)
      from merged m
    ),'[]'::json)
  )
end
from base_json x
left join public.users owner on owner.id=x.owner_id;
$function$;
