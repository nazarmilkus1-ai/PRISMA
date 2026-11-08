create or replace function public.mc_create_clan(p_user_id uuid,p_name text,p_tag text)
returns json language plpgsql security definer set search_path=''
as $$
declare cid uuid; tag_base text; tag_value text; suffix integer:=0;
begin
  if not exists(select 1 from public.users where id=p_user_id and status='ACCEPTED' and is_whitelisted) then raise exception 'USER_NOT_ALLOWED'; end if;
  if exists(select 1 from public.clan_members where user_id=p_user_id and status='active') then raise exception 'USER_ALREADY_IN_CLAN'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 32 then raise exception 'INVALID_CLAN_NAME'; end if;
  tag_base:=upper(regexp_replace(trim(coalesce(p_tag,'')),'[^A-Z0-9]','','g'));
  if char_length(tag_base)<2 then tag_base:='C'||substr(md5(lower(trim(p_name))),1,5); else tag_base:=left(tag_base,6); end if;
  tag_value:=tag_base;
  while exists(select 1 from public.clans where deleted_at is null and lower(tag)=lower(tag_value)) loop
    suffix:=suffix+1;
    tag_value:=left(tag_base,greatest(1,6-char_length(suffix::text)))||suffix::text;
  end loop;
  if exists(select 1 from public.clans where deleted_at is null and lower(name)=lower(trim(p_name))) then raise exception 'CLAN_NAME_TAKEN'; end if;
  insert into public.clans(name,tag,owner_id,type,status) values(trim(p_name),tag_value,p_user_id,'open','active') returning id into cid;
  insert into public.clan_members(clan_id,user_id,role,status) values(cid,p_user_id,'owner','active')
  on conflict (user_id) do update set clan_id=excluded.clan_id,role='owner',status='active',joined_at=now();
  update public.users set clan_id=cid,updated_at=now() where id=p_user_id;
  return json_build_object('success',true,'clan_id',cid,'tag',tag_value,'name',trim(p_name));
end;
$$;

create or replace function public.mc_join_clan(p_user_id uuid,p_clan_name text)
returns json language plpgsql security definer set search_path=''
as $$
declare cid uuid; cname text; ctag text;
begin
  if not exists(select 1 from public.users where id=p_user_id and status='ACCEPTED' and is_whitelisted) then raise exception 'USER_NOT_ALLOWED'; end if;
  if exists(select 1 from public.clan_members where user_id=p_user_id and status='active') then raise exception 'USER_ALREADY_IN_CLAN'; end if;
  select id,name,tag into cid,cname,ctag from public.clans
  where deleted_at is null and status='active' and lower(name)=lower(trim(p_clan_name)) limit 1;
  if cid is null then raise exception 'CLAN_NOT_FOUND'; end if;
  insert into public.clan_members(clan_id,user_id,role,status) values(cid,p_user_id,'member','active')
  on conflict (user_id) do update set clan_id=excluded.clan_id,role='member',status='active',joined_at=now();
  update public.users set clan_id=cid,updated_at=now() where id=p_user_id;
  return json_build_object('success',true,'clan_id',cid,'tag',ctag,'name',cname);
end;
$$;