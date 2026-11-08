-- Canonical staff mutation contracts for PRISMA polls.

create or replace function public.staff_create_poll(
  p_question text,
  p_options text[],
  p_closes_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid;
  poll_id uuid;
  clean_options text[];
  clean_question text:=trim(coalesce(p_question,''));
begin
  select u.id into actor_id
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ADMIN_PROFILE_NOT_LINKED'; end if;
  if not exists (
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_id and p.key='poll.create'
  ) then raise exception 'FORBIDDEN'; end if;

  select array_agg(distinct trim(v) order by trim(v))
    into clean_options
  from unnest(coalesce(p_options,array[]::text[])) v
  where trim(v) <> '';

  if char_length(clean_question) not between 3 and 300 then raise exception 'INVALID_QUESTION'; end if;
  if coalesce(array_length(clean_options,1),0) < 2 then raise exception 'INVALID_OPTIONS'; end if;
  if coalesce(array_length(clean_options,1),0) > 8 then raise exception 'TOO_MANY_OPTIONS'; end if;

  insert into public.polls(
    question,options,kind,is_active,created_at,closes_at,expires_at,
    created_by,status,allow_multiple,max_choices,allow_add_options,
    allow_change_vote,show_voters,shuffle_options,has_correct_answer,
    correct_options,publish_at,visibility,anonymous,kind_text
  )
  values(
    clean_question,clean_options,'POLL',true,now(),p_closes_at,p_closes_at,
    actor_id,'active',false,1,false,true,false,false,false,
    array[]::integer[],now(),'public',false,'POLL'
  )
  returning id into poll_id;

  insert into public.poll_options(poll_id,text,position,is_correct)
  select poll_id,v,row_number() over(),false
  from unnest(clean_options) v;

  insert into public.audit_logs(
    actor_user_id,action,target_type,target_id,old_data,new_data
  )
  values(
    actor_id,'POLL_CREATE','poll',poll_id,null,
    jsonb_build_object('question',clean_question,'option_count',array_length(clean_options,1),'closes_at',p_closes_at)
  );

  return jsonb_build_object('success',true,'id',poll_id);
end;
$function$;

create or replace function public.staff_manage_poll(
  p_poll_id uuid,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid;
  existing public.polls%rowtype;
  next_status text;
begin
  select u.id into actor_id
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ADMIN_PROFILE_NOT_LINKED'; end if;
  if not exists (
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_id and p.key='poll.manage'
  ) then raise exception 'FORBIDDEN'; end if;

  select * into existing from public.polls where id=p_poll_id for update;
  if not found then raise exception 'POLL_NOT_FOUND'; end if;

  next_status:=case when p_is_active then 'active' else 'finished' end;

  update public.polls
  set is_active=p_is_active,
      status=next_status,
      finished_at=case when p_is_active then null else coalesce(finished_at,now()) end
  where id=p_poll_id;

  insert into public.audit_logs(
    actor_user_id,action,target_type,target_id,old_data,new_data
  )
  values(
    actor_id,
    case when p_is_active then 'POLL_OPEN' else 'POLL_FINISH' end,
    'poll',p_poll_id,
    jsonb_build_object('is_active',existing.is_active,'status',existing.status,'finished_at',existing.finished_at),
    jsonb_build_object('is_active',p_is_active,'status',next_status,'finished_at',case when p_is_active then null else coalesce(existing.finished_at,now()) end)
  );

  return jsonb_build_object('success',true,'id',p_poll_id,'is_active',p_is_active,'status',next_status);
end;
$function$;

revoke all on function public.staff_create_poll(text,text[],timestamptz) from public,anon;
grant execute on function public.staff_create_poll(text,text[],timestamptz) to authenticated;

revoke all on function public.staff_manage_poll(uuid,boolean) from public,anon;
grant execute on function public.staff_manage_poll(uuid,boolean) to authenticated;
