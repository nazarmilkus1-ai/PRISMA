-- Heartbeat must indicate liveness, not rewrite the login timestamp.
CREATE OR REPLACE FUNCTION public.touch_online_players(p_nicknames text[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare affected integer:=0;
begin
  if p_nicknames is null or cardinality(p_nicknames)=0 then return 0; end if;

  update public.users u
     set last_seen_at=now(),
         updated_at=now()
   where u.deleted_at is null
     and u.status='ACCEPTED'
     and u.is_whitelisted
     and exists(
       select 1 from unnest(p_nicknames) n(nick)
       where lower(trim(nick))=lower(trim(u.minecraft_nickname))
     );

  get diagnostics affected=row_count;
  return affected;
end;
$function$;
