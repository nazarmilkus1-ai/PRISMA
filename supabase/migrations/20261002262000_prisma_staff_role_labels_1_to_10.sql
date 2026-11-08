-- PRISMA staff display ranks: normalize every role to a visible 1–10 ladder.
-- Keep roles.priority unchanged: it is an internal RBAC hierarchy value and is
-- used by moderation and staff-management authorization checks.
update public.roles
set rank_label = case name
  when 'owner' then '10'
  when 'head_admin' then '9'
  when 'head_staff' then '8'
  when 'admin' then '7'
  when 'senior_moderator' then '6'
  when 'moderator' then '5'
  when 'helper' then '4'
  when 'developer' then '3'
  when 'builder' then '2'
  when 'game_designer' then '2'
  when 'event_manager' then '2'
  when 'media' then '1'
  when 'content_maker' then '1'
  else rank_label
end
where name in (
  'owner','head_admin','head_staff','admin','senior_moderator','moderator','helper',
  'developer','builder','game_designer','event_manager','media','content_maker'
);
