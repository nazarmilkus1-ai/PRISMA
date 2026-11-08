create or replace function private.prisma_notify_report_update()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_tg bigint;
  status_text text;
begin
  if not (
    old.status is distinct from new.status
    or old.assigned_to is distinct from new.assigned_to
  ) then
    return new;
  end if;

  status_text:=case new.status::text
    when 'OPEN' then 'Открыт'
    when 'IN_REVIEW' then 'В работе'
    when 'RESOLVED' then 'Решён'
    when 'DISMISSED' then 'Отклонён'
    else new.status::text
  end;

  select u.telegram_id into target_tg
  from public.users u
  where u.id=new.user_id;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data
  )
  select
    new.user_id,target_tg,'telegram','MODERATION','Репорт обновлён',
    'Статус репорта '||
      coalesce('#'||new.ticket_no::text,'#'||left(new.id::text,8))||
      ': '||status_text||'. Откройте репорт, чтобы посмотреть детали.',
    jsonb_build_object(
      'report_id',new.id,
      'ticket_no',new.ticket_no,
      'source','report_status_update'
    )
  where target_tg is not null;

  return new;
end;
$function$;