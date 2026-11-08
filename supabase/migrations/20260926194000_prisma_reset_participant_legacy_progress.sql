update public.users
set activity_score=0, updated_at=now()
where status='ACCEPTED' and is_whitelisted and deleted_at is null
  and activity_score<>0;