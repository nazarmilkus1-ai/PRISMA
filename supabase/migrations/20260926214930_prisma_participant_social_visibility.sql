-- Participant-controlled visibility for social status on the player passport.

alter table public.users
  add column if not exists social_visibility text not null default 'PRIVATE';

alter table public.users
  drop constraint if exists users_social_visibility_check;

alter table public.users
  add constraint users_social_visibility_check
  check (social_visibility in ('PRIVATE','PUBLIC'));

create or replace function public.participant_update_social_visibility(p_visibility text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
  clean_visibility text:=upper(trim(coalesce(p_visibility,'PRIVATE')));
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);

  if clean_visibility not in ('PRIVATE','PUBLIC') then
    raise exception 'INVALID_SOCIAL_VISIBILITY';
  end if;

  update public.users
  set social_visibility=clean_visibility,
      updated_at=now()
  where id=uid;

  return jsonb_build_object('success',true,'visibility',clean_visibility);
end;
$function$;

revoke all on function public.participant_update_social_visibility(text) from public,anon;
grant execute on function public.participant_update_social_visibility(text) to authenticated;

create or replace function public.participant_get_public_social(p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  viewer_id uuid;
  target public.users%rowtype;
  result jsonb;
begin
  select u.id into viewer_id
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if viewer_id is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(viewer_id);

  select u.* into target
  from public.users u
  where u.deleted_at is null
    and u.status='ACCEPTED'
    and not u.is_banned
    and u.minecraft_nickname is not null
    and lower(u.minecraft_nickname)=lower(trim(p_nickname))
  limit 1;

  if target.id is null then
    return null;
  end if;

  if coalesce(target.social_visibility,'PRIVATE') <> 'PUBLIC' then
    return jsonb_build_object('visibility','PRIVATE');
  end if;

  select jsonb_build_object(
    'visibility','PUBLIC',
    'marriage',coalesce((
      select jsonb_build_object(
        'partner_nickname',p.minecraft_nickname,
        'married_at',m.married_at
      )
      from public.marriages m
      join public.users p
        on p.id=case when m.user_a_id=target.id then m.user_b_id else m.user_a_id end
      where m.status='ACTIVE'
        and (m.user_a_id=target.id or m.user_b_id=target.id)
        and p.deleted_at is null
        and coalesce(p.social_visibility,'PRIVATE')='PUBLIC'
      order by m.married_at desc
      limit 1
    ),'null'::jsonb),
    'relationship',coalesce((
      select jsonb_build_object(
        'partner_nickname',p.minecraft_nickname,
        'started_at',r.started_at
      )
      from public.relationships r
      join public.users p
        on p.id=case when r.user_a_id=target.id then r.user_b_id else r.user_a_id end
      where r.status='ACTIVE'
        and (r.user_a_id=target.id or r.user_b_id=target.id)
        and p.deleted_at is null
        and coalesce(p.social_visibility,'PRIVATE')='PUBLIC'
      order by r.started_at desc
      limit 1
    ),'null'::jsonb)
  ) into result;

  return result;
end;
$function$;

revoke all on function public.participant_get_public_social(text) from public,anon;
grant execute on function public.participant_get_public_social(text) to authenticated;
