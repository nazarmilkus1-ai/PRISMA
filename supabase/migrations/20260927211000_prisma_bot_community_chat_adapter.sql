-- PRISMA v2: trusted bot adapter for resolving the configured community chat.

create or replace function public.bot_get_community_chat_id()
returns bigint
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
 chat_id bigint;
begin
 select cs.chat_id
 into chat_id
 from public.chat_settings cs
 where cs.chat_id is not null
 order by cs.updated_at desc nulls last,cs.chat_id
 limit 1;

 if chat_id is null then
   raise exception 'COMMUNITY_CHAT_NOT_CONFIGURED';
 end if;

 return chat_id;
end;
$function$;

revoke all on function public.bot_get_community_chat_id() from public,anon,authenticated;
grant execute on function public.bot_get_community_chat_id() to service_role;
