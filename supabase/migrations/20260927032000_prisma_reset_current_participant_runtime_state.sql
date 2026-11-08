update public.users
set
  rating=1000,
  activity_score=0,
  level=1,
  xp=0,
  profile_links='{}'::jsonb,
  locale='ru',
  is_banned=false,
  ban_reason=null,
  is_muted=false,
  muted_until=null,
  last_seen_at=null,
  last_login_at=null,
  community_first_seen_at=null,
  clan_id=null,
  updated_at=now()
where status='ACCEPTED'
  and is_whitelisted=true
  and deleted_at is null;