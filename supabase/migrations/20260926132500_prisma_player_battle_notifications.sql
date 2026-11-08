alter table public.notification_preferences
  add column if not exists battles boolean not null default true;

update public.notification_preferences set battles=true where battles is null;

create or replace function private.prisma_notify_player_battle()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_id uuid:=new.opponent_id;
  actor_id uuid:=new.challenger_id;
  actor_nick text;
  target_tg bigint;
  result_text text;
  points_text text;
begin
  if new.status<>'COMPLETED' then return new; end if;

  select u.minecraft_nickname into actor_nick
  from public.users u where u.id=actor_id;

  result_text:=case
    when new.winner_id is null then 'Ничья.'
    when new.winner_id=actor_id then 'Вы проиграли этот бой.'
    else 'Вы выиграли этот бой.'
  end;

  points_text:=case
    when new.points_awarded>0 then
      ' Рейтинг: '||case when new.winner_id=target_id then '+' else '−' end||new.points_awarded||'.'
    else ''
  end;

  select u.telegram_id into target_tg
  from public.users u where u.id=target_id;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select target_id,target_tg,'telegram','BATTLE','Player Battle',
    coalesce(actor_nick,'Участник')||' провёл с вами Player Battle: '||
    new.opponent_score||' : '||new.challenger_score||'. '||result_text||points_text,
    jsonb_build_object('battle_id',new.id,'source','player_battle')
  where target_tg is not null
    and not exists(
      select 1 from public.notifications n
      where n.user_id=target_id and n.kind='BATTLE'
        and n.data->>'battle_id'=new.id::text
    );

  return new;
end;
$function$;

drop trigger if exists player_battle_notification on public.player_battles;
create trigger player_battle_notification
after insert on public.player_battles
for each row execute function private.prisma_notify_player_battle();