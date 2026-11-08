DROP POLICY IF EXISTS clans_authenticated_select ON public.clans;
DROP POLICY IF EXISTS clans_public_select ON public.clans;
CREATE POLICY clans_select ON public.clans
FOR SELECT TO anon,authenticated
USING (deleted_at IS NULL AND status='active');

DROP POLICY IF EXISTS events_public_read ON public.events;
DROP POLICY IF EXISTS events_read ON public.events;
CREATE POLICY events_select ON public.events
FOR SELECT TO anon,authenticated
USING (
  status <> 'draft'
  OR (SELECT private.has_permission('event.manage'::text))
);

DROP POLICY IF EXISTS news_public_select ON public.news;
DROP POLICY IF EXISTS news_staff_read ON public.news;
CREATE POLICY news_select ON public.news
FOR SELECT TO anon,authenticated
USING (
  is_published
  OR EXISTS (
    SELECT 1
    FROM public.admins
    WHERE admins.user_id=(SELECT auth.uid())
  )
);