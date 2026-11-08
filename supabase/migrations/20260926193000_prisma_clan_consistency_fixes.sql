-- Keep open/closed clan admission consistent across bot, Minecraft and participant site.
create or replace function public.mc_join_clan(
  p_user_id uuid,
  p_clan_name text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  cid uuid;
  cname text;
  ctag text;
begin
  if not exists(
    select 1 from public.users
    where id=p_user_id and status='ACCEPTED' and is_whitelisted
  ) then
    raise exception 'USER_NOT_ALLOWED';
  end if;

  if exists(
    select 1 from public.clan_members
    where user_id=p_user_id and status='active'
  ) then
    raise exception 'USER_ALREADY_IN_CLAN';
  end if;

  select id,name,tag into cid,cname,ctag
  from public.clans
  where deleted_at is null
    and status='active'
    and type='open'
    and lower(name)=lower(trim(p_clan_name))
  limit 1;

  if cid is null then
    if exists(
      select 1 from public.clans
      where deleted_at is null
        and status='active'
        and lower(name)=lower(trim(p_clan_name))
    ) then
      raise exception 'CLAN_NOT_OPEN';
    end if;
    raise exception 'CLAN_NOT_FOUND';
  end if;

  insert into public.clan_members(clan_id,user_id,role,status)
  values(cid,p_user_id,'member','active')
  on conflict (user_id) do update
    set clan_id=excluded.clan_id,role='member',status='active',joined_at=now();

  update public.users set clan_id=cid,updated_at=now() where id=p_user_id;

  return json_build_object('success',true,'clan_id',cid,'tag',ctag,'name',cname);
end;
$function$;

-- Determine CLAN_FIRST_WIN from the canonical war record, not from denormalized counters.
create or replace function private.prisma_clan_unlock_achievements(
  p_clan_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  a record;
  v_members integer;
  v_villages integer;
  v_wins integer;
  v_activity integer;
  v_first_win boolean;
  v_clan_name text;
begin
  select c.name,c.wins into v_clan_name,v_wins
  from public.clans c
  where c.id=p_clan_id
    and c.status='active'
    and c.deleted_at is null;

  if v_clan_name is null then return; end if;

  select count(*)::integer into v_members
  from public.clan_members cm
  where cm.clan_id=p_clan_id and cm.status='active';

  select count(*)::integer into v_villages
  from public.clan_villages cv
  where cv.clan_id=p_clan_id and cv.status='active';

  select count(*)::integer into v_activity
  from public.clan_activity ca
  where ca.clan_id=p_clan_id;

  select exists(
    select 1
    from public.clan_wars w
    where w.winner_clan_id=p_clan_id
      and w.status='finished'
  ) into v_first_win;

  for a in
    select id,code,title,description,icon,xp_reward
    from public.achievements
    where
      (code='CLAN_FOUNDER' and v_members>=1)
      or (code='CLAN_FIVE' and v_members>=5)
      or (code='CLAN_TEN' and v_members>=10)
      or (code='CLAN_TERRITORY_MASTER' and v_villages>=3)
      or (code='CLAN_FIRST_WIN' and v_first_win)
      or (code='CLAN_VETERAN' and v_activity>=25)
  loop
    insert into public.clan_achievements(clan_id,achievement_id,unlocked_at)
    values(p_clan_id,a.id,now())
    on conflict (clan_id,achievement_id) do nothing;

    if found then
      insert into public.notifications(
        user_id,telegram_id,channel,kind,title,body,data,status,available_at
      )
      select
        cm.user_id,u.telegram_id,'telegram','CLAN',
        'Новое достижение клана',
        'Клан "'||v_clan_name||'" открыл достижение "'||a.title||'".',
        jsonb_build_object(
          'clan_id',p_clan_id,
          'achievement_id',a.id,
          'code',a.code,
          'xp_reward',a.xp_reward,
          'source','clan_achievement'
        ),
        'pending',now()
      from public.clan_members cm
      join public.users u on u.id=cm.user_id
      where cm.clan_id=p_clan_id
        and cm.status='active'
        and u.deleted_at is null
        and u.status='ACCEPTED'::public.application_status
        and not u.is_banned;
    end if;
  end loop;
end;
$function$;