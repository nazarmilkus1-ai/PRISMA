-- "Forget me": removes a person's PRISMA_AI chat log and long-memory summary. Bot-only (service_role).
create or replace function public.bot_ai_forget(p_tg_id bigint)
returns void language plpgsql security definer set search_path to ''
as $function$
begin
  delete from public.ai_chat_log where telegram_id = p_tg_id;
  delete from public.ai_chat_summary where telegram_id = p_tg_id;
end;
$function$;

revoke all on function public.bot_ai_forget(bigint) from public, anon, authenticated;
grant execute on function public.bot_ai_forget(bigint) to service_role;
