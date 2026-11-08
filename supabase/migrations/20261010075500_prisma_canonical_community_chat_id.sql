-- PRISMA: resolve the invitation target from the canonical community setting.
-- Never infer the community from the most recently edited automoderation group.

insert into public.settings(key, value, description)
values (
  'telegram_groups',
  jsonb_build_object('main', null, 'admin', null, 'announcements', null),
  'Telegram group IDs'
)
on conflict (key) do nothing;

-- One-time safe backfill:
-- 1) preserve an explicitly configured main group;
-- 2) otherwise use the legacy main_chat_id;
-- 3) infer a group only when exactly one automoderation chat exists.
do $migration$
declare
  configured_main bigint;
  inferred_main bigint;
  configured_chat_count bigint;
begin
  select case
           when coalesce(s.value->>'main', '') ~ '^-?[0-9]+$'
             then (s.value->>'main')::bigint
           else null
         end
    into configured_main
  from public.settings s
  where s.key = 'telegram_groups';

  if configured_main is null then
    select cs.main_chat_id
      into inferred_main
    from public.chat_settings cs
    where cs.main_chat_id is not null
    order by cs.updated_at desc nulls last, cs.main_chat_id
    limit 1;

    if inferred_main is null then
      select min(cs.chat_id), count(distinct cs.chat_id)
        into inferred_main, configured_chat_count
      from public.chat_settings cs
      where cs.chat_id is not null;

      if configured_chat_count <> 1 then
        inferred_main := null;
      end if;
    end if;

    if inferred_main is not null then
      update public.settings s
      set value = jsonb_set(
            coalesce(s.value, '{}'::jsonb),
            '{main}',
            to_jsonb(inferred_main::text),
            true
          ),
          updated_at = now()
      where s.key = 'telegram_groups';
    end if;
  end if;
end;
$migration$;

create or replace function public.bot_get_community_chat_id()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  chat_id bigint;
begin
  select case
           when coalesce(s.value->>'main', '') ~ '^-?[0-9]+$'
             then (s.value->>'main')::bigint
           else null
         end
    into chat_id
  from public.settings s
  where s.key = 'telegram_groups';

  -- Compatibility for installations that still store the original main group.
  if chat_id is null then
    select cs.main_chat_id
      into chat_id
    from public.chat_settings cs
    where cs.main_chat_id is not null
    order by cs.updated_at desc nulls last, cs.main_chat_id
    limit 1;
  end if;

  -- Backward-compatible inference is safe only when there is exactly one chat.
  if chat_id is null then
    select case
             when count(distinct cs.chat_id) = 1 then min(cs.chat_id)
             else null
           end
      into chat_id
    from public.chat_settings cs
    where cs.chat_id is not null;
  end if;

  if chat_id is null then
    raise exception 'COMMUNITY_CHAT_NOT_CONFIGURED';
  end if;

  return chat_id;
end;
$function$;

revoke all on function public.bot_get_community_chat_id()
from public, anon, authenticated;
grant execute on function public.bot_get_community_chat_id()
to service_role;

create or replace function public.staff_get_community_chat_id()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  chat_id bigint;
begin
  if actor_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select u.id
    into actor_id
  from public.users u
  where u.auth_user_id = actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id, 'application.approve')
  limit 1;

  if actor_id is null then
    raise exception 'PERMISSION_DENIED';
  end if;

  select case
           when coalesce(s.value->>'main', '') ~ '^-?[0-9]+$'
             then (s.value->>'main')::bigint
           else null
         end
    into chat_id
  from public.settings s
  where s.key = 'telegram_groups';

  if chat_id is null then
    select cs.main_chat_id
      into chat_id
    from public.chat_settings cs
    where cs.main_chat_id is not null
    order by cs.updated_at desc nulls last, cs.main_chat_id
    limit 1;
  end if;

  if chat_id is null then
    select case
             when count(distinct cs.chat_id) = 1 then min(cs.chat_id)
             else null
           end
      into chat_id
    from public.chat_settings cs
    where cs.chat_id is not null;
  end if;

  if chat_id is null then
    raise exception 'COMMUNITY_CHAT_NOT_CONFIGURED';
  end if;

  return chat_id;
end;
$function$;

revoke all on function public.staff_get_community_chat_id()
from public, anon;
grant execute on function public.staff_get_community_chat_id()
to authenticated;
