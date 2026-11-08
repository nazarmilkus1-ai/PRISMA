-- Keep poll source classification without exposing audit logs.

create or replace function public.get_public_polls(p_limit integer default 20)
returns jsonb
language sql security definer set search_path=''
as $function$
  select coalesce((
    select jsonb_agg(to_jsonb(p) order by p.created_at desc)
    from (
      select
        po.id,po.question,po.description,po.kind,po.kind_text,po.expires_at,
        po.status,po.visibility,po.allow_multiple,po.max_choices,po.allow_change_vote,
        po.created_at,
        exists(select 1 from public.admins a where a.user_id=po.created_by) as admin_created,
        coalesce((
          select jsonb_agg(
            jsonb_build_object('id',o.id,'poll_id',o.poll_id,'text',o.text,'position',o.position)
            order by o.position
          )
          from public.poll_options o
          where o.poll_id=po.id
        ),'[]'::jsonb) as options
      from public.polls po
      where po.visibility='public' and po.status='active'
      order by po.created_at desc
      limit greatest(1,least(coalesce(p_limit,20),100))
    ) p
  ),'[]'::jsonb);
$function$;
