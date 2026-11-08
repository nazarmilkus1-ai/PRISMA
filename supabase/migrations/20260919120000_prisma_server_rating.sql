insert into public.polls (question, options, kind, is_active, status, allow_multiple, max_choices, allow_add_options, allow_change_vote, show_voters, shuffle_options, has_correct_answer, visibility, anonymous, kind_text)
select 'Как ты оцениваешь сервер PRISMA?', array['1★','2★','3★','4★','5★'], 'SERVER_RATING'::public.poll_kind, true, 'active', false, 1, false, true, false, false, false, 'public', false, 'server_rating'
where not exists (select 1 from public.polls where kind='SERVER_RATING'::public.poll_kind and is_active=true);

create or replace function public.bot_rate_server(p_tg_id bigint, p_value integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user_id uuid; v_poll_id uuid;
begin
  if p_value < 1 or p_value > 5 then return jsonb_build_object('success',false,'error','INVALID_VALUE'); end if;
  select u.id into v_user_id from public.users u where u.telegram_id=p_tg_id and u.status='ACCEPTED'::public.application_status and u.deleted_at is null limit 1;
  if v_user_id is null then return jsonb_build_object('success',false,'error','NOT_APPROVED'); end if;
  select p.id into v_poll_id from public.polls p where p.kind='SERVER_RATING'::public.poll_kind and p.is_active=true and p.status='active' order by p.created_at desc limit 1;
  if v_poll_id is null then return jsonb_build_object('success',false,'error','RATING_NOT_CONFIGURED'); end if;
  insert into public.poll_ratings(poll_id,user_id,option_index,value) values(v_poll_id,v_user_id,p_value-1,p_value)
  on conflict (poll_id,user_id) do update set option_index=excluded.option_index,value=excluded.value;
  return jsonb_build_object('success',true,'value',p_value);
end;
$$;

revoke all on function public.bot_rate_server(bigint,integer) from public;
revoke all on function public.bot_rate_server(bigint,integer) from anon;
revoke all on function public.bot_rate_server(bigint,integer) from authenticated;
grant execute on function public.bot_rate_server(bigint,integer) to service_role;
