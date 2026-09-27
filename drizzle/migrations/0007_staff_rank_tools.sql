-- numeric rank ladder: member 0, mod 1, super_mod 2, co_owner/admin 3, owner 4
CREATE OR REPLACE FUNCTION public.rank_level(_user uuid)
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT coalesce(max(
    CASE role::text
      WHEN 'owner' THEN 4
      WHEN 'co_owner' THEN 3
      WHEN 'admin' THEN 3
      WHEN 'super_mod' THEN 2
      WHEN 'mod' THEN 1
      ELSE 0
    END), 0)
  FROM public.user_roles WHERE user_id = _user
$$;

CREATE OR REPLACE FUNCTION public.rank_name(_user uuid)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE public.rank_level(_user)
    WHEN 4 THEN 'owner'
    WHEN 3 THEN 'co_owner'
    WHEN 2 THEN 'super_mod'
    WHEN 1 THEN 'mod'
    ELSE 'member' END
$$;

-- last known ip per profile (filled by the app on sign in)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_ip text;

CREATE TABLE IF NOT EXISTS public.ip_bans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ip text NOT NULL UNIQUE,
  reason text NOT NULL DEFAULT '',
  banned_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ip_bans TO authenticated;
GRANT SELECT ON public.ip_bans TO anon;
GRANT ALL ON public.ip_bans TO service_role;
ALTER TABLE public.ip_bans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff read ip bans" ON public.ip_bans;
CREATE POLICY "staff read ip bans" ON public.ip_bans FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.staff_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor uuid,
  target uuid,
  action text NOT NULL,
  detail text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.staff_log TO authenticated;
GRANT SELECT ON public.staff_log TO anon;
GRANT ALL ON public.staff_log TO service_role;
ALTER TABLE public.staff_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read staff log" ON public.staff_log;
CREATE POLICY "read staff log" ON public.staff_log FOR SELECT TO anon, authenticated USING (true);

-- record client ip, and report whether that ip is blocked
CREATE OR REPLACE FUNCTION public.record_ip(_user uuid, _ip text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF _ip IS NULL OR _ip = '' THEN RETURN false; END IF;
  UPDATE public.profiles SET last_ip = _ip WHERE id = _user;
  RETURN exists (SELECT 1 FROM public.ip_bans WHERE ip = _ip);
END; $$;

-- moderation: rank 1+, cannot act on someone of equal or higher rank
CREATE OR REPLACE FUNCTION public.mod_action(_actor uuid, _target uuid, _action text, _minutes integer DEFAULT 10)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE lvl int := public.rank_level(_actor);
BEGIN
  IF lvl < 1 THEN RAISE EXCEPTION 'you are not staff'; END IF;
  IF lvl < 4 AND public.rank_level(_target) >= lvl THEN
    RAISE EXCEPTION 'you cannot moderate someone of your rank or higher'; END IF;
  IF _action = 'mute' THEN
    UPDATE public.profiles SET muted_until = now() + make_interval(mins => _minutes) WHERE id = _target;
  ELSIF _action = 'unmute' THEN
    UPDATE public.profiles SET muted_until = null WHERE id = _target;
  ELSIF _action = 'ban' THEN
    UPDATE public.profiles SET banned = true WHERE id = _target;
  ELSIF _action = 'unban' THEN
    UPDATE public.profiles SET banned = false WHERE id = _target;
  ELSE RAISE EXCEPTION 'unknown action'; END IF;
  INSERT INTO public.staff_log (actor, target, action) VALUES (_actor, _target, _action);
END; $$;

CREATE OR REPLACE FUNCTION public.delete_message(_actor uuid, _message uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.rank_level(_actor) < 1 THEN RAISE EXCEPTION 'you are not staff'; END IF;
  UPDATE public.messages SET deleted = true, content = '[removed by staff]' WHERE id = _message;
  INSERT INTO public.staff_log (actor, action) VALUES (_actor, 'delete_message');
END; $$;

-- coin grants with per-rank caps (owner uncapped)
CREATE OR REPLACE FUNCTION public.mod_grant_coins(_actor uuid, _target uuid, _amount integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE lvl int := public.rank_level(_actor); cap bigint;
BEGIN
  IF lvl < 1 THEN RAISE EXCEPTION 'you are not staff'; END IF;
  cap := CASE lvl WHEN 1 THEN 100000 WHEN 2 THEN 500000 WHEN 3 THEN 1000000 ELSE 2000000000 END;
  IF _amount = 0 THEN RAISE EXCEPTION 'amount cannot be zero'; END IF;
  IF _amount < 0 AND lvl < 3 THEN RAISE EXCEPTION 'only co-owners and the owner can remove coins'; END IF;
  IF abs(_amount) > cap THEN RAISE EXCEPTION 'your limit is % coins', cap; END IF;
  UPDATE public.profiles SET coins = greatest(0, coins + _amount) WHERE id = _target;
  IF NOT found THEN RAISE EXCEPTION 'target user not found'; END IF;
  INSERT INTO public.staff_log (actor, target, action, detail)
  VALUES (_actor, _target, 'grant_coins', _amount::text);
END; $$;

-- super mod+: wipe a member's recent messages
CREATE OR REPLACE FUNCTION public.purge_user_messages(_actor uuid, _target uuid, _minutes integer DEFAULT 60)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE lvl int := public.rank_level(_actor); n int;
BEGIN
  IF lvl < 2 THEN RAISE EXCEPTION 'super mod rank required'; END IF;
  IF lvl < 4 AND public.rank_level(_target) >= lvl THEN
    RAISE EXCEPTION 'you cannot purge someone of your rank or higher'; END IF;
  UPDATE public.messages SET deleted = true, content = '[removed by staff]'
   WHERE user_id = _target AND NOT deleted AND created_at > now() - make_interval(mins => _minutes);
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO public.staff_log (actor, target, action, detail)
  VALUES (_actor, _target, 'purge_messages', n::text);
  RETURN n;
END; $$;

-- super mod+: reset a member's cosmetics
CREATE OR REPLACE FUNCTION public.staff_reset_look(_actor uuid, _target uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.rank_level(_actor) < 2 THEN RAISE EXCEPTION 'super mod rank required'; END IF;
  UPDATE public.profiles SET name_color = '#ffffff', font_key = 'body' WHERE id = _target;
  INSERT INTO public.staff_log (actor, target, action) VALUES (_actor, _target, 'reset_look');
END; $$;

-- co-owner+: change someone's rank, never at or above your own (owner may do anything)
CREATE OR REPLACE FUNCTION public.staff_set_rank(_actor uuid, _target uuid, _rank text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE lvl int := public.rank_level(_actor); want int;
BEGIN
  IF lvl < 3 THEN RAISE EXCEPTION 'co-owner rank required'; END IF;
  want := CASE _rank WHEN 'owner' THEN 4 WHEN 'co_owner' THEN 3 WHEN 'super_mod' THEN 2
                     WHEN 'mod' THEN 1 WHEN 'member' THEN 0 ELSE -1 END;
  IF want < 0 THEN RAISE EXCEPTION 'unknown rank'; END IF;
  IF lvl < 4 AND (want >= lvl OR public.rank_level(_target) >= lvl) THEN
    RAISE EXCEPTION 'you can only manage ranks below your own'; END IF;
  DELETE FROM public.user_roles
   WHERE user_id = _target AND role::text IN ('mod','super_mod','co_owner','owner','admin');
  IF want > 0 THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (_target, _rank::public.app_role)
    ON CONFLICT DO NOTHING;
  END IF;
  INSERT INTO public.staff_log (actor, target, action, detail)
  VALUES (_actor, _target, 'set_rank', _rank);
END; $$;

-- owner: block / unblock an address
CREATE OR REPLACE FUNCTION public.staff_ip_ban(_actor uuid, _target uuid, _reason text DEFAULT '')
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE addr text;
BEGIN
  IF public.rank_level(_actor) < 4 THEN RAISE EXCEPTION 'owner rank required'; END IF;
  SELECT last_ip INTO addr FROM public.profiles WHERE id = _target;
  IF addr IS NULL OR addr = '' THEN RAISE EXCEPTION 'no address on record for that member yet'; END IF;
  INSERT INTO public.ip_bans (ip, reason, banned_by) VALUES (addr, coalesce(_reason,''), _actor)
  ON CONFLICT (ip) DO UPDATE SET reason = excluded.reason, banned_by = excluded.banned_by;
  UPDATE public.profiles SET banned = true WHERE id = _target;
  INSERT INTO public.staff_log (actor, target, action, detail) VALUES (_actor, _target, 'ip_ban', addr);
  RETURN addr;
END; $$;

CREATE OR REPLACE FUNCTION public.staff_ip_unban(_actor uuid, _ip text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.rank_level(_actor) < 4 THEN RAISE EXCEPTION 'owner rank required'; END IF;
  DELETE FROM public.ip_bans WHERE ip = _ip;
  INSERT INTO public.staff_log (actor, action, detail) VALUES (_actor, 'ip_unban', _ip);
END; $$;

-- owner: clear a whole room
CREATE OR REPLACE FUNCTION public.staff_wipe_room(_actor uuid, _room uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE n int;
BEGIN
  IF public.rank_level(_actor) < 4 THEN RAISE EXCEPTION 'owner rank required'; END IF;
  UPDATE public.messages SET deleted = true, content = '[cleared by the owner]'
   WHERE room_id = _room AND NOT deleted;
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO public.staff_log (actor, action, detail) VALUES (_actor, 'wipe_room', n::text);
  RETURN n;
END; $$;