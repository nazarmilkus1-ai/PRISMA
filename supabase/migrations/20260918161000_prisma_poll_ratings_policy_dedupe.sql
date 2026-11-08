-- Keep a single authenticated SELECT policy for poll_ratings.
drop policy if exists poll_ratings_staff_read_v2 on public.poll_ratings;
