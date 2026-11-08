create table if not exists public.telegram_chat_activity(
 chat_id bigint not null,
 user_id uuid not null references public.users(id) on delete cascade,
 activity_date date not null default current_date,
 message_count integer not null default 0,
 first_message_at timestamptz not null default now(),
 last_message_at timestamptz not null default now(),
 primary key(chat_id,user_id,activity_date)
);
create index if not exists telegram_chat_activity_user_idx on public.telegram_chat_activity(chat_id,user_id,activity_date desc);
create index if not exists telegram_chat_activity_last_idx on public.telegram_chat_activity(chat_id,last_message_at desc);
alter table public.telegram_chat_activity enable row level security;

create or replace function public.bot_record_telegram_activity(p_chat_id bigint,p_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then return json_build_object('error','USER_NOT_FOUND'); end if;
 insert into public.telegram_chat_activity(chat_id,user_id,activity_date,message_count,first_message_at,last_message_at)
 values(p_chat_id,uid,current_date,1,now(),now())
 on conflict(chat_id,user_id,activity_date) do update set message_count=telegram_chat_activity.message_count+1,last_message_at=now();
 return json_build_object('success',true);
end $$;

create or replace function public.bot_chat_top(p_chat_id bigint,p_days integer default null,p_limit integer default 10)
returns json language sql security definer set search_path=public as $$
 select coalesce(json_agg(x order by x.messages desc,x.last_message_at desc),'[]'::json)
 from (
  select a.user_id,u.telegram_id as tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         sum(a.message_count)::integer as messages,max(a.last_message_at) as last_message_at
  from public.telegram_chat_activity a join public.users u on u.id=a.user_id
  where a.chat_id=p_chat_id and (p_days is null or a.activity_date >= current_date-greatest(0,p_days-1)::integer) and u.deleted_at is null
  group by a.user_id,u.telegram_id,u.full_name,u.telegram_username,u.minecraft_nickname
  order by messages desc,last_message_at desc
  limit greatest(1,least(coalesce(p_limit,10),100))
 ) x $$;