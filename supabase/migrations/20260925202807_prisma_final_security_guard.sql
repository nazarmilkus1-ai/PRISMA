-- Final browser/database boundary for PRISMA v2.

alter function public.participant_create_clan(text) security definer;
alter function public.participant_get_clan(uuid) security definer;
alter function public.participant_join_clan(uuid) security definer;
alter function public.participant_leave_clan() security definer;
alter function public.participant_list_clans() security definer;
alter function public.participant_create_report(text,text,text) security definer;
alter function public.site_submit_application(text,date,text,text,text,text,text) security definer;
alter function public.staff_decide_application(uuid,text,text) security definer;
alter function public.staff_update_report(uuid,text,text,uuid,jsonb) security definer;

revoke usage on schema private from public,anon,authenticated;
revoke all on all functions in schema private from public,anon,authenticated;

grant execute on function public.participant_create_clan(text) to authenticated;
grant execute on function public.participant_get_clan(uuid) to authenticated;
grant execute on function public.participant_join_clan(uuid) to authenticated;
grant execute on function public.participant_leave_clan() to authenticated;
grant execute on function public.participant_list_clans() to authenticated;
grant execute on function public.participant_create_report(text,text,text) to authenticated;
grant execute on function public.site_submit_application(text,date,text,text,text,text,text) to authenticated;
grant execute on function public.staff_decide_application(uuid,text,text) to authenticated;
grant execute on function public.staff_update_report(uuid,text,text,uuid,jsonb) to authenticated;
