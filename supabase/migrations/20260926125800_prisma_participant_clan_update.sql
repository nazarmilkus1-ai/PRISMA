CREATE OR REPLACE FUNCTION private.prisma_participant_update_clan(
  p_user_id uuid,p_name text,p_tag text,p_description text,p_type text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare
  clan_id uuid;
  clean_name text:=trim(coalesce(p_name,''));
  clean_tag text:=upper(trim(coalesce(p_tag,'')));
  clean_description text:=nullif(trim(coalesce(p_description,'')),'');
  clean_type text:=lower(trim(coalesce(p_type,'')));
begin
  perform private.prisma_participant_require_access(p_user_id);

  select cm.clan_id into clan_id
  from public.clan_members cm
  where cm.user_id=p_user_id and cm.status='active' and cm.role='owner'
  limit 1;

  if clan_id is null then raise exception 'OWNER_ONLY'; end if;
  if char_length(clean_name) not between 2 and 32 then raise exception 'INVALID_CLAN_NAME'; end if;
  if clean_tag !~ '^[A-Z0-9]{2,6}$' then raise exception 'INVALID_CLAN_TAG'; end if;
  if char_length(coalesce(clean_description,''))>500 then raise exception 'INVALID_CLAN_DESCRIPTION'; end if;
  if clean_type not in ('open','closed') then raise exception 'INVALID_CLAN_TYPE'; end if;

  if exists(select 1 from public.clans c where c.id<>clan_id and c.deleted_at is null and lower(c.name)=lower(clean_name))
    then raise exception 'CLAN_NAME_TAKEN'; end if;

  if exists(select 1 from public.clans c where c.id<>clan_id and c.deleted_at is null and lower(c.tag)=lower(clean_tag))
    then raise exception 'CLAN_TAG_TAKEN'; end if;

  update public.clans
  set name=clean_name,tag=clean_tag,description=clean_description,type=clean_type,updated_at=now()
  where id=clan_id and deleted_at is null and status='active';

  return jsonb_build_object('success',true,'clan_id',clan_id,'name',clean_name,'tag',clean_tag,'type',clean_type);
end;
$function$;

CREATE OR REPLACE FUNCTION public.participant_update_clan(
  p_name text,p_tag text,p_description text DEFAULT NULL,p_type text DEFAULT 'open'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_update_clan(uid,p_name,p_tag,p_description,p_type);
end;
$function$;

revoke all on function public.participant_update_clan(text,text,text,text) from public;
grant execute on function public.participant_update_clan(text,text,text,text) to authenticated;