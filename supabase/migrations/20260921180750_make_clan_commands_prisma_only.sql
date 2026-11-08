update public.clans
set description = null
where deleted_at is null
  and (
    lower(coalesce(description,'')) like '%iris%'
    or lower(coalesce(description,'')) like '%импортировано%'
    or lower(coalesce(description,'')) like '%оригинальный%'
  );

create or replace function public.bot_list_clans()
returns json
language sql
security definer
set search_path=public
as $function$
with catalog as (
  select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.balance,c.wins,c.losses,
         c.description,c.type,c.status,c.created_at,c.source,c.source_number,
         owner.telegram_id owner_tg_id,
         coalesce(ia.leader_username,owner.telegram_username) owner_username,
         coalesce(ia.leader_name,owner.full_name) owner_full_name,
         greatest(
           (select count(*)::integer from public.clan_members cm
            where cm.clan_id=c.id and cm.status='active'),
           coalesce(ia.source_member_count,0)
         ) member_count,
         false is_imported_only
  from public.clans c
  join public.users owner on owner.id=c.owner_id
  left join public.iris_clan_import_archive ia on ia.source_number=c.source_number
  where c.deleted_at is null and c.status='active'

  union all

  select null::uuid id,a.clan_name name,null::text tag,
         coalesce(a.reputation,0)::integer rating,1::integer level,
         0::bigint xp,0::bigint balance,0 wins,0 losses,
         null::text description,a.clan_type::text type,'IMPORTED'::text status,
         a.founded_at::timestamptz created_at,'Iris'::text source,a.source_number,
         (select u.telegram_id from public.users u
          where lower(coalesce(u.telegram_username,''))=lower(coalesce(a.leader_username,''))
          order by u.is_whitelisted desc,u.created_at asc limit 1) owner_tg_id,
         a.leader_username owner_username,a.leader_name owner_full_name,
         coalesce(a.source_member_count,0)::integer member_count,
         true is_imported_only
  from public.iris_clan_import_archive a
  where not exists (
    select 1 from public.clans c
    where c.deleted_at is null and c.source='Iris' and c.source_number=a.source_number
  )
)
select coalesce(
  json_agg(json_build_object(
    'name',x.name,
    'tag',coalesce(x.tag,''),
    'rating',x.rating,
    'level',x.level,
    'xp',x.xp,
    'balance',x.balance,
    'wins',x.wins,
    'losses',x.losses,
    'description',x.description,
    'type',x.type,
    'status',x.status,
    'created_at',x.created_at,
    'owner_tg_id',x.owner_tg_id,
    'owner_username',x.owner_username,
    'owner_full_name',x.owner_full_name,
    'member_count',x.member_count,
    'is_imported',x.is_imported_only
  ) order by x.is_imported_only,x.source_number nulls last,x.rating desc,x.name),
  '[]'::json
)
from catalog x;
$function$;

create or replace function public.bot_get_clan_by_position(p_position integer)
returns json
language sql
security definer
set search_path=public
as $function$
with catalog as (
  select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.balance,c.wins,c.losses,
         c.description,c.type,c.status,c.created_at,c.updated_at,c.owner_id,
         c.source,c.source_number,
         ia.leader_name ia_leader_name,
         ia.leader_username ia_leader_username,
         ia.source_member_count ia_member_count,
         ia.original_members,
         false is_imported_only
  from public.clans c
  left join public.iris_clan_import_archive ia on ia.source_number=c.source_number
  where c.deleted_at is null and c.status='active'

  union all

  select null::uuid id,a.clan_name name,null::text tag,
         coalesce(a.reputation,0)::integer rating,1::integer level,
         0::bigint xp,0::bigint balance,0 wins,0 losses,
         null::text description,a.clan_type::text type,'IMPORTED'::text status,
         a.founded_at::timestamptz created_at,now() updated_at,null::uuid owner_id,
         'Iris'::text source,a.source_number,
         a.leader_name ia_leader_name,a.leader_username ia_leader_username,
         a.source_member_count ia_member_count,a.original_members,
         true is_imported_only
  from public.iris_clan_import_archive a
  where not exists (
    select 1 from public.clans c
    where c.deleted_at is null and c.source='Iris' and c.source_number=a.source_number
  )
),
ranked as (
  select c.*,
         row_number() over (
           order by c.is_imported_only,c.source_number nulls last,c.rating desc,c.name
         )::integer position
  from catalog c
),
base_json as (
  select x.*,
         owner.telegram_id owner_tg_id,
         ia.leader_name ia_leader_name_fallback,
         ia.leader_username ia_leader_username_fallback
  from ranked x
  left join public.users owner on owner.id=x.owner_id
  left join public.iris_clan_import_archive ia on ia.source_number=x.source_number
  where x.position=greatest(1,coalesce(p_position,1))
)
select case
  when x.id is null and x.source_number is null then json_build_object('error','CLAN_NOT_FOUND')
  else json_build_object(
    'position',x.position,
    'id',x.id,
    'name',x.name,
    'tag',coalesce(x.tag,''),
    'type',x.type,
    'status',x.status,
    'owner_id',x.owner_id,
    'description',x.description,
    'rating',x.rating,
    'level',x.level,
    'xp',x.xp,
    'balance',x.balance,
    'wins',x.wins,
    'losses',x.losses,
    'created_at',x.created_at,
    'is_imported',x.is_imported_only,
    'leader',json_build_object(
      'tg_id',coalesce(
        (select u.telegram_id
         from public.users u
         where coalesce(x.ia_leader_username,x.ia_leader_username_fallback) is not null
           and lower(coalesce(u.telegram_username,''))=lower(coalesce(x.ia_leader_username,x.ia_leader_username_fallback))
         order by u.is_whitelisted desc,u.created_at asc limit 1),
        x.owner_tg_id
      ),
      'username',coalesce(x.ia_leader_username,x.ia_leader_username_fallback,
                           (select u.telegram_username from public.users u where u.id=x.owner_id)),
      'full_name',coalesce(x.ia_leader_name,x.ia_leader_name_fallback,
                            (select u.full_name from public.users u where u.id=x.owner_id)),
      'minecraft_nick',(select u.minecraft_nickname from public.users u where u.id=x.owner_id)
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
        where x.id is not null
          and cm.clan_id=x.id
          and cm.status='active'
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
        'tg_id',m.tg_id,'username',m.username,'full_name',m.full_name,
        'role',m.role,'joined_at',m.joined_at,'joined_text',m.joined_text
      ) order by case when m.role='leader' or m.role='owner' then 0 else 1 end,
               m.joined_at nulls last,m.full_name)
      from merged m
    ),'[]'::json)
  )
end
from base_json x;
$function$;