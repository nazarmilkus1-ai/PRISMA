create table if not exists public.relationship_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.users(id) on delete cascade,
  target_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'PENDING',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint relationship_requests_status_check check (status in ('PENDING','ACCEPTED','REJECTED','CANCELLED')),
  constraint relationship_requests_not_self check (requester_id <> target_id)
);

create index if not exists relationship_requests_target_idx on public.relationship_requests(target_id,status,created_at desc);
create unique index if not exists relationship_requests_pending_unique on public.relationship_requests(requester_id,target_id) where status='PENDING';

create table if not exists public.relationships (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references public.users(id) on delete cascade,
  user_b_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'ACTIVE',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  constraint relationships_status_check check (status in ('ACTIVE','ENDED')),
  constraint relationships_pair_check check (user_a_id < user_b_id),
  constraint relationships_not_self check (user_a_id <> user_b_id)
);

create unique index if not exists relationships_active_pair_unique on public.relationships(user_a_id,user_b_id) where status='ACTIVE';
create unique index if not exists relationships_one_active_per_user_a on public.relationships(user_a_id) where status='ACTIVE';
create unique index if not exists relationships_one_active_per_user_b on public.relationships(user_b_id) where status='ACTIVE';

create table if not exists public.marriage_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.users(id) on delete cascade,
  target_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'PENDING',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint marriage_requests_status_check check (status in ('PENDING','ACCEPTED','REJECTED','CANCELLED')),
  constraint marriage_requests_not_self check (requester_id <> target_id)
);

create index if not exists marriage_requests_target_idx on public.marriage_requests(target_id,status,created_at desc);
create unique index if not exists marriage_requests_pending_unique on public.marriage_requests(requester_id,target_id) where status='PENDING';

create table if not exists public.marriages (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references public.users(id) on delete cascade,
  user_b_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'ACTIVE',
  married_at timestamptz not null default now(),
  divorced_at timestamptz,
  constraint marriages_status_check check (status in ('ACTIVE','DIVORCED')),
  constraint marriages_pair_check check (user_a_id < user_b_id),
  constraint marriages_not_self check (user_a_id <> user_b_id)
);

create unique index if not exists marriages_active_pair_unique on public.marriages(user_a_id,user_b_id) where status='ACTIVE';
create unique index if not exists marriages_one_active_per_user_a on public.marriages(user_a_id) where status='ACTIVE';
create unique index if not exists marriages_one_active_per_user_b on public.marriages(user_b_id) where status='ACTIVE';

alter table public.relationship_requests enable row level security;
alter table public.relationships enable row level security;
alter table public.marriage_requests enable row level security;
alter table public.marriages enable row level security;

create or replace function public.bot_relationship_request(p_tg_id bigint,p_target_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare a uuid; b uuid; rid uuid;
begin
 select id into a from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 select id into b from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if a is null or b is null then raise exception 'USER_NOT_FOUND'; end if;
 if a=b then raise exception 'SELF_RELATIONSHIP_FORBIDDEN'; end if;
 if exists(select 1 from public.relationships where status='ACTIVE' and (user_a_id in (a,b) or user_b_id in (a,b))) then raise exception 'ALREADY_IN_RELATIONSHIP'; end if;
 if exists(select 1 from public.relationship_requests where requester_id=b and target_id=a and status='PENDING') then raise exception 'INCOMING_REQUEST_EXISTS'; end if;
 if exists(select 1 from public.relationship_requests where requester_id=a and target_id=b and status='PENDING') then raise exception 'REQUEST_ALREADY_SENT'; end if;
 insert into public.relationship_requests(requester_id,target_id) values(a,b) returning id into rid;
 return json_build_object('success',true,'request_id',rid);
end $$;

create or replace function public.bot_relationship_respond(p_tg_id bigint,p_accept boolean)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid; req public.relationship_requests%rowtype; lo uuid; hi uuid; rid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 select * into req from public.relationship_requests where target_id=uid and status='PENDING' order by created_at desc limit 1 for update;
 if not found then raise exception 'NO_PENDING_RELATIONSHIP_REQUEST'; end if;
 if not p_accept then
   update public.relationship_requests set status='REJECTED',responded_at=now() where id=req.id;
   return json_build_object('success',true,'accepted',false);
 end if;
 if exists(select 1 from public.relationships where status='ACTIVE' and (user_a_id in (uid,req.requester_id) or user_b_id in (uid,req.requester_id))) then raise exception 'ALREADY_IN_RELATIONSHIP'; end if;
 if req.requester_id < uid then lo:=req.requester_id; hi:=uid; else lo:=uid; hi:=req.requester_id; end if;
 insert into public.relationships(user_a_id,user_b_id,status) values(lo,hi,'ACTIVE') returning id into rid;
 update public.relationship_requests set status='ACCEPTED',responded_at=now() where id=req.id;
 return json_build_object('success',true,'accepted',true,'relationship_id',rid);
end $$;

create or replace function public.bot_relationship_end(p_tg_id bigint,p_target_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare a uuid; b uuid;
begin
 select id into a from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 select id into b from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if a is null or b is null then raise exception 'USER_NOT_FOUND'; end if;
 update public.relationships set status='ENDED',ended_at=now()
 where status='ACTIVE' and ((user_a_id=a and user_b_id=b) or (user_a_id=b and user_b_id=a));
 if not found then raise exception 'RELATIONSHIP_NOT_FOUND'; end if;
 return json_build_object('success',true);
end $$;

create or replace function public.bot_relationship_info(p_tg_id bigint)
returns json language sql stable security definer set search_path=public as $$
 select coalesce((
  select json_build_object('active',true,'partner_tg_id',p.telegram_id,'partner_name',p.full_name,'partner_username',p.telegram_username,'started_at',r.started_at)
  from public.users u
  join public.relationships r on r.status='ACTIVE' and (r.user_a_id=u.id or r.user_b_id=u.id)
  join public.users p on p.id=case when r.user_a_id=u.id then r.user_b_id else r.user_a_id end
  where u.telegram_id=p_tg_id and u.deleted_at is null and p.deleted_at is null
  limit 1
 ),json_build_object('active',false));
$$;

create or replace function public.bot_marriage_request(p_tg_id bigint,p_target_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare a uuid; b uuid; rid uuid;
begin
 select id into a from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 select id into b from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if a is null or b is null then raise exception 'USER_NOT_FOUND'; end if;
 if a=b then raise exception 'SELF_MARRIAGE_FORBIDDEN'; end if;
 if exists(select 1 from public.marriages where status='ACTIVE' and (user_a_id in (a,b) or user_b_id in (a,b))) then raise exception 'ALREADY_MARRIED'; end if;
 if exists(select 1 from public.marriage_requests where requester_id=b and target_id=a and status='PENDING') then raise exception 'INCOMING_MARRIAGE_REQUEST_EXISTS'; end if;
 if exists(select 1 from public.marriage_requests where requester_id=a and target_id=b and status='PENDING') then raise exception 'MARRIAGE_REQUEST_ALREADY_SENT'; end if;
 insert into public.marriage_requests(requester_id,target_id) values(a,b) returning id into rid;
 return json_build_object('success',true,'request_id',rid);
end $$;

create or replace function public.bot_marriage_respond(p_tg_id bigint,p_accept boolean)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid; req public.marriage_requests%rowtype; lo uuid; hi uuid; mid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 select * into req from public.marriage_requests where target_id=uid and status='PENDING' order by created_at desc limit 1 for update;
 if not found then raise exception 'NO_PENDING_MARRIAGE_REQUEST'; end if;
 if not p_accept then
   update public.marriage_requests set status='REJECTED',responded_at=now() where id=req.id;
   return json_build_object('success',true,'accepted',false);
 end if;
 if exists(select 1 from public.marriages where status='ACTIVE' and (user_a_id in (uid,req.requester_id) or user_b_id in (uid,req.requester_id))) then raise exception 'ALREADY_MARRIED'; end if;
 if req.requester_id < uid then lo:=req.requester_id; hi:=uid; else lo:=uid; hi:=req.requester_id; end if;
 insert into public.marriages(user_a_id,user_b_id,status) values(lo,hi,'ACTIVE') returning id into mid;
 update public.marriage_requests set status='ACCEPTED',responded_at=now() where id=req.id;
 return json_build_object('success',true,'accepted',true,'marriage_id',mid);
end $$;

create or replace function public.bot_marriage_divorce(p_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 update public.marriages set status='DIVORCED',divorced_at=now() where status='ACTIVE' and (user_a_id=uid or user_b_id=uid);
 if not found then raise exception 'NO_ACTIVE_MARRIAGE'; end if;
 return json_build_object('success',true);
end $$;

create or replace function public.bot_marriage_info(p_tg_id bigint)
returns json language sql stable security definer set search_path=public as $$
 select coalesce((
  select json_build_object('active',true,'partner_tg_id',p.telegram_id,'partner_name',p.full_name,'married_at',m.married_at)
  from public.users u
  join public.marriages m on m.status='ACTIVE' and (m.user_a_id=u.id or m.user_b_id=u.id)
  join public.users p on p.id=case when m.user_a_id=u.id then m.user_b_id else m.user_a_id end
  where u.telegram_id=p_tg_id and u.deleted_at is null and p.deleted_at is null
  limit 1
 ),json_build_object('active',false));
$$;

revoke execute on function public.bot_relationship_request(bigint,bigint) from public,anon,authenticated;
revoke execute on function public.bot_relationship_respond(bigint,boolean) from public,anon,authenticated;
revoke execute on function public.bot_relationship_end(bigint,bigint) from public,anon,authenticated;
revoke execute on function public.bot_relationship_info(bigint) from public,anon,authenticated;
revoke execute on function public.bot_marriage_request(bigint,bigint) from public,anon,authenticated;
revoke execute on function public.bot_marriage_respond(bigint,boolean) from public,anon,authenticated;
revoke execute on function public.bot_marriage_divorce(bigint) from public,anon,authenticated;
revoke execute on function public.bot_marriage_info(bigint) from public,anon,authenticated;

grant execute on function public.bot_relationship_request(bigint,bigint) to service_role;
grant execute on function public.bot_relationship_respond(bigint,boolean) to service_role;
grant execute on function public.bot_relationship_end(bigint,bigint) to service_role;
grant execute on function public.bot_relationship_info(bigint) to service_role;
grant execute on function public.bot_marriage_request(bigint,bigint) to service_role;
grant execute on function public.bot_marriage_respond(bigint,boolean) to service_role;
grant execute on function public.bot_marriage_divorce(bigint) to service_role;
grant execute on function public.bot_marriage_info(bigint) to service_role;
