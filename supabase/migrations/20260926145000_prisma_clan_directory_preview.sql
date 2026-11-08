-- Improve the participant clan directory gateway with safe owner and member previews.

create or replace function private.prisma_participant_list_clans(p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.rating desc nulls last,x.created_at asc)
    from (
      select
        c.id,c.name,c.tag,c.type,c.description,c.rating,c.points,c.level,c.xp,
        c.wins,c.losses,c.color,c.avatar_url,c.created_at,
        ou.minecraft_nickname as owner_nickname,
        (
          select count(*)
          from public.clan_members cm
          join public.users mu on mu.id=cm.user_id
          where cm.clan_id=c.id
            and cm.status='active'
            and mu.deleted_at is null
            and mu.status='ACCEPTED'
            and not mu.is_banned
        ) as member_count,
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'user_id',cm.user_id,'role',cm.role,'minecraft_nickname',mu.minecraft_nickname
          ) order by
            case cm.role when 'owner' then 0 when 'co_owner' then 1 when 'officer' then 2 when 'recruit' then 4 else 3 end,
            cm.joined_at asc
          )
          from (
            select cm.*
            from public.clan_members cm
            where cm.clan_id=c.id and cm.status='active'
            order by
              case cm.role when 'owner' then 0 when 'co_owner' then 1 when 'officer' then 2 when 'recruit' then 4 else 3 end,
              cm.joined_at asc
            limit 8
          ) cm
          join public.users mu on mu.id=cm.user_id
          where mu.deleted_at is null and mu.status='ACCEPTED' and not mu.is_banned
        ),'[]'::jsonb) as members
      from public.clans c
      left join public.users ou on ou.id=c.owner_id
      where c.deleted_at is null and c.status='active'
    ) x
  ),'[]'::jsonb);
end;
$function$;
