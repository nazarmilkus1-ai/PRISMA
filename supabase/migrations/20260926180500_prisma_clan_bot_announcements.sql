create or replace function public.bot_get_clan_info(p_tg_id bigint)
returns json language plpgsql security definer set search_path='public'
as $function$
declare uid uuid; cid uuid; out json;
begin
  select id,clan_id into uid,cid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then return json_build_object('error','USER_NOT_FOUND'); end if;
  if cid is null then return json_build_object('error','NO_CLAN'); end if;

  select json_build_object(
    'id',c.id,'name',c.name,'tag',c.tag,'type',c.type,'status',c.status,
    'owner_id',c.owner_id,'level',c.level,'xp',c.xp,'balance',c.balance,
    'wins',c.wins,'losses',c.losses,'description',c.description,
    'members',coalesce((
      select json_agg(
        json_build_object('user_id',u.id,'tg_id',u.telegram_id,'full_name',u.full_name,
          'minecraft_nick',u.minecraft_nickname,'role',cm.role)
        order by case cm.role when 'owner' then 0 when 'co_owner' then 1
          when 'officer' then 2 when 'recruit' then 4 else 3 end, cm.joined_at
      )
      from public.clan_members cm join public.users u on u.id=cm.user_id
      where cm.clan_id=c.id and cm.status='active' and u.deleted_at is null
    ),'[]'::json),
    'announcements',coalesce((
      select json_agg(
        json_build_object('id',a.id,'title',a.title,'body',a.body,'created_at',a.created_at,
          'author_nickname',u.minecraft_nickname)
        order by a.created_at desc
      )
      from public.clan_announcements a
      left join public.users u on u.id=a.author_id
      where a.clan_id=c.id
      limit 20
    ),'[]'::json)
  ) into out
  from public.clans c
  where c.id=cid and c.status='active' and c.deleted_at is null;

  if out is null then return json_build_object('error','CLAN_NOT_FOUND'); end if;
  return out;
end;
$function$;

create or replace function public.bot_create_clan_announcement(p_tg_id bigint,p_title text,p_body text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_create_clan_announcement(uid,p_title,p_body);
end;
$function$;

revoke execute on function public.bot_get_clan_info(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_clan_info(bigint) to service_role;
revoke execute on function public.bot_create_clan_announcement(bigint,text,text) from public,anon,authenticated;
grant execute on function public.bot_create_clan_announcement(bigint,text,text) to service_role;