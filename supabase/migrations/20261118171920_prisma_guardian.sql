-- Guardian (agent B): state, event log and confirmable proposals.
-- Panel/bot never touch tables directly; everything goes through RPCs.

create table if not exists public.guardian_events (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  kind text not null check (char_length(kind) <= 60),
  severity text not null default 'info' check (severity in ('info','warn','error')),
  summary text not null check (char_length(summary) <= 500),
  details jsonb not null default '{}'::jsonb
);
create index if not exists guardian_events_created_idx on public.guardian_events (created_at desc);

create table if not exists public.guardian_state (
  key text primary key check (char_length(key) <= 60),
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.guardian_proposals (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  source text not null check (source in ('bot_agent','guardian','staff')),
  kind text not null check (kind in ('render_redeploy','render_rollback','vercel_redeploy','note')),
  title text not null check (char_length(title) <= 200),
  body text not null default '' check (char_length(body) <= 3000),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','executed','failed','expired')),
  decided_by uuid references public.users(id) on delete set null,
  decided_at timestamptz,
  executed_at timestamptz,
  result text check (result is null or char_length(result) <= 1000)
);
create index if not exists guardian_proposals_status_idx on public.guardian_proposals (status, created_at desc);

alter table public.guardian_events enable row level security;
alter table public.guardian_state enable row level security;
alter table public.guardian_proposals enable row level security;
revoke all on public.guardian_events, public.guardian_state, public.guardian_proposals from public, anon, authenticated;
revoke all on sequence public.guardian_events_id_seq from public, anon, authenticated;

-- ---------- service-role RPCs (tick / bot) ----------

create or replace function public.guardian_log_event(p_kind text, p_severity text, p_summary text, p_details jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into public.guardian_events(kind, severity, summary, details)
  values (left(p_kind, 60), coalesce(nullif(p_severity,''),'info'), left(p_summary, 500), coalesce(p_details,'{}'::jsonb))
  returning id into v_id;
  delete from public.guardian_events where created_at < now() - interval '30 days';
  return v_id;
end $$;

create or replace function public.guardian_state_get(p_key text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select value from public.guardian_state where key = p_key), '{}'::jsonb)
$$;

create or replace function public.guardian_state_set(p_key text, p_value jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.guardian_state(key, value, updated_at) values (p_key, coalesce(p_value,'{}'::jsonb), now())
  on conflict (key) do update set value = excluded.value, updated_at = now()
$$;

-- Safe-action gate: at most one action per cooldown and p_daily_cap per 24h (counted in guardian_events).
create or replace function public.guardian_auto_action_gate(p_action text, p_cooldown_min int, p_daily_cap int)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_last timestamptz; v_day int;
begin
  select max(created_at), count(*) filter (where created_at > now() - interval '24 hours')
    into v_last, v_day
  from public.guardian_events where kind = 'auto:' || p_action;
  if v_last is not null and v_last > now() - make_interval(mins => p_cooldown_min) then return false; end if;
  if v_day >= p_daily_cap then return false; end if;
  insert into public.guardian_events(kind, severity, summary) values ('auto:' || p_action, 'warn', 'safe auto action: ' || p_action);
  return true;
end $$;

create or replace function public.guardian_proposal_create(p_source text, p_kind text, p_title text, p_body text default '', p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  -- dedupe: same kind+title still pending
  select id into v_id from public.guardian_proposals where status = 'pending' and kind = p_kind and title = left(p_title,200) limit 1;
  if v_id is not null then return v_id; end if;
  update public.guardian_proposals set status = 'expired' where status = 'pending' and created_at < now() - interval '3 days';
  insert into public.guardian_proposals(source, kind, title, body, payload)
  values (p_source, p_kind, left(p_title,200), left(coalesce(p_body,''),3000), coalesce(p_payload,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.guardian_proposal_take(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.guardian_proposals%rowtype;
begin
  select * into r from public.guardian_proposals where id = p_id and status = 'approved' and executed_at is null for update skip locked;
  if not found then return null; end if;
  update public.guardian_proposals set executed_at = now() where id = p_id;
  return to_jsonb(r);
end $$;

create or replace function public.guardian_proposal_finish(p_id uuid, p_ok boolean, p_result text)
returns void language sql security definer set search_path = '' as $$
  update public.guardian_proposals
     set status = case when p_ok then 'executed' else 'failed' end, result = left(coalesce(p_result,''),1000), executed_at = now()
   where id = p_id and status = 'approved'
$$;

-- ---------- staff RPCs (authenticated, permission-checked) ----------

create or replace function public.staff_guardian_overview()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_ok boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select exists(select 1 from public.users u where u.auth_user_id = v_uid and u.deleted_at is null
                and private.prisma_has_user_permission(u.id, 'ops.view')) into v_ok;
  if not v_ok then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'proposals', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc)
        from (select * from public.guardian_proposals order by created_at desc limit 30) p), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc)
        from (select * from public.guardian_events order by created_at desc limit 50) e), '[]'::jsonb),
    'state', coalesce((select jsonb_object_agg(key, value) from public.guardian_state), '{}'::jsonb)
  );
end $$;

create or replace function public.staff_guardian_decide(p_id uuid, p_approve boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_actor uuid; r public.guardian_proposals%rowtype;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into v_actor from public.users u
   where u.auth_user_id = v_uid and u.deleted_at is null
     and private.prisma_has_user_permission(u.id, 'ops.manage') limit 1;
  if v_actor is null then raise exception 'FORBIDDEN'; end if;
  update public.guardian_proposals
     set status = case when p_approve then 'approved' else 'rejected' end, decided_by = v_actor, decided_at = now()
   where id = p_id and status = 'pending'
   returning * into r;
  if not found then raise exception 'NOT_PENDING'; end if;
  insert into public.guardian_events(kind, severity, summary, details)
  values ('proposal', 'info', (case when p_approve then 'approved: ' else 'rejected: ' end) || r.title, jsonb_build_object('id', r.id, 'by', v_actor));
  return to_jsonb(r);
end $$;

-- ---------- permissions ----------

insert into public.permissions(key, description)
values ('ops.view', 'Просмотр охранника (здоровье сервисов, предложения)'),
       ('ops.manage', 'Подтверждение действий охранника')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.name in ('owner', 'head_admin') and p.key in ('ops.view', 'ops.manage')
on conflict do nothing;

-- ---------- ACL ----------

revoke all on function public.guardian_log_event(text,text,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.guardian_state_get(text) from public, anon, authenticated, service_role;
revoke all on function public.guardian_state_set(text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.guardian_auto_action_gate(text,int,int) from public, anon, authenticated, service_role;
revoke all on function public.guardian_proposal_create(text,text,text,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.guardian_proposal_take(uuid) from public, anon, authenticated, service_role;
revoke all on function public.guardian_proposal_finish(uuid,boolean,text) from public, anon, authenticated, service_role;
revoke all on function public.staff_guardian_overview() from public, anon, authenticated, service_role;
revoke all on function public.staff_guardian_decide(uuid,boolean) from public, anon, authenticated, service_role;

grant execute on function public.guardian_log_event(text,text,text,jsonb) to service_role;
grant execute on function public.guardian_state_get(text) to service_role;
grant execute on function public.guardian_state_set(text,jsonb) to service_role;
grant execute on function public.guardian_auto_action_gate(text,int,int) to service_role;
grant execute on function public.guardian_proposal_create(text,text,text,text,jsonb) to service_role;
grant execute on function public.guardian_proposal_take(uuid) to service_role;
grant execute on function public.guardian_proposal_finish(uuid,boolean,text) to service_role;
grant execute on function public.staff_guardian_overview() to authenticated, service_role;
grant execute on function public.staff_guardian_decide(uuid,boolean) to authenticated, service_role;
