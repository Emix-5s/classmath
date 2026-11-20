DROP POLICY IF EXISTS "guests update profiles" ON public.profiles;
REVOKE UPDATE ON public.profiles FROM anon, authenticated;
DROP POLICY IF EXISTS "read device bans" ON public.device_bans;
REVOKE SELECT ON public.device_bans FROM anon, authenticated;
DROP POLICY IF EXISTS "staff read ip bans" ON public.ip_bans;
REVOKE SELECT ON public.ip_bans FROM anon, authenticated;
DROP POLICY IF EXISTS "read staff log" ON public.staff_log;
REVOKE SELECT ON public.staff_log FROM anon, authenticated;
DROP POLICY IF EXISTS "read user stats" ON public.user_stats;
REVOKE SELECT ON public.user_stats FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.list_device_bans(_token uuid)
RETURNS TABLE(id uuid, device_id text, reason text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE _me uuid := public.session_member(_token);
BEGIN
  IF _me IS NULL OR public.rank_level(_me) < 4 THEN RAISE EXCEPTION 'not allowed'; END IF;
  RETURN QUERY SELECT b.id, b.device_id, b.reason FROM public.device_bans b ORDER BY b.created_at DESC;
END $$;
REVOKE ALL ON FUNCTION public.list_device_bans(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.list_device_bans(uuid) TO anon, authenticated;