-- device (HWID) tagging
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS device_id text;

CREATE TABLE IF NOT EXISTS public.device_bans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id text NOT NULL UNIQUE,
  reason text NOT NULL DEFAULT '',
  banned_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.device_bans TO anon, authenticated;
GRANT ALL ON public.device_bans TO service_role;
ALTER TABLE public.device_bans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read device bans" ON public.device_bans;
CREATE POLICY "read device bans" ON public.device_bans FOR SELECT USING (true);

-- rank ladder now: ton618 6, coverstar 5, owner 4, co_owner/admin 3, super_mod 2, mod 1
CREATE OR REPLACE FUNCTION public.rank_level(_user uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT coalesce(max(
    CASE role::text
      WHEN 'ton618' THEN 6
      WHEN 'coverstar' THEN 5
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
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE public.rank_level(_user)
    WHEN 6 THEN 'ton618'
    WHEN 5 THEN 'coverstar'
    WHEN 4 THEN 'owner'
    WHEN 3 THEN 'co_owner'
    WHEN 2 THEN 'super_mod'
    WHEN 1 THEN 'mod'
    ELSE 'member' END
$$;

-- bigger grant caps for the top ranks
CREATE OR REPLACE FUNCTION public.mod_grant_coins(_actor uuid, _target uuid, _amount bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE lvl int := public.rank_level(_actor); cap bigint;
BEGIN
  IF lvl < 1 THEN RAISE EXCEPTION 'you are not staff'; END IF;
  cap := CASE lvl WHEN 1 THEN 100000 WHEN 2 THEN 500000 WHEN 3 THEN 10000000
                  WHEN 4 THEN 2000000000 ELSE 1000000000000000 END;
  IF _amount = 0 THEN RAISE EXCEPTION 'amount cannot be zero'; END IF;
  IF _amount < 0 AND lvl < 3 THEN RAISE EXCEPTION 'only co-owners and above can remove coins'; END IF;
  IF abs(_amount) > cap THEN RAISE EXCEPTION 'your limit is % coins', cap; END IF;
  UPDATE public.profiles SET coins = greatest(0, coins + _amount) WHERE id = _target;
  IF NOT found THEN RAISE EXCEPTION 'target user not found'; END IF;
  INSERT INTO public.staff_log (actor, target, action, detail)
  VALUES (_actor, _target, 'grant_coins', _amount::text);
END; $$;

-- register a device, return true when that device is banned
CREATE OR REPLACE FUNCTION public.record_device(_user uuid, _device text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF _device IS NULL OR _device = '' THEN RETURN false; END IF;
  UPDATE public.profiles SET device_id = _device WHERE id = _user;
  RETURN exists (SELECT 1 FROM public.device_bans WHERE device_id = _device);
END; $$;

-- device ban / unban (owner rank 4+)
CREATE OR REPLACE FUNCTION public.staff_device_ban(_actor uuid, _target uuid, _reason text DEFAULT '')
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE dev text;
BEGIN
  IF public.rank_level(_actor) < 4 THEN RAISE EXCEPTION 'owner rank required'; END IF;
  IF public.rank_level(_actor) < 6 AND public.rank_level(_target) >= public.rank_level(_actor) THEN
    RAISE EXCEPTION 'you cannot act on someone of your rank or higher'; END IF;
  SELECT device_id INTO dev FROM public.profiles WHERE id = _target;
  IF dev IS NULL OR dev = '' THEN RAISE EXCEPTION 'no device id on record for that member yet'; END IF;
  INSERT INTO public.device_bans (device_id, reason, banned_by) VALUES (dev, coalesce(_reason,''), _actor)
  ON CONFLICT (device_id) DO UPDATE SET reason = excluded.reason, banned_by = excluded.banned_by;
  UPDATE public.profiles SET banned = true WHERE id = _target;
  INSERT INTO public.staff_log (actor, target, action, detail) VALUES (_actor, _target, 'device_ban', dev);
  RETURN dev;
END; $$;

CREATE OR REPLACE FUNCTION public.staff_device_unban(_actor uuid, _device text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF public.rank_level(_actor) < 4 THEN RAISE EXCEPTION 'owner rank required'; END IF;
  DELETE FROM public.device_bans WHERE device_id = _device;
  INSERT INTO public.staff_log (actor, action, detail) VALUES (_actor, 'device_unban', _device);
END; $$;

-- change someone's name, colour and font (coverstar rank 5+)
CREATE OR REPLACE FUNCTION public.staff_set_identity(_actor uuid, _target uuid, _username text,
                                                     _color text, _font text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE uname text;
BEGIN
  IF public.rank_level(_actor) < 5 THEN RAISE EXCEPTION 'coverst4r rank required'; END IF;
  IF public.rank_level(_actor) < 6 AND public.rank_level(_target) >= public.rank_level(_actor) THEN
    RAISE EXCEPTION 'you cannot act on someone of your rank or higher'; END IF;
  IF _username IS NOT NULL AND _username <> '' THEN
    uname := lower(regexp_replace(_username, '[^a-zA-Z0-9_]', '', 'g'));
    IF uname = '' THEN RAISE EXCEPTION 'that name has no usable characters'; END IF;
    IF exists (SELECT 1 FROM public.profiles WHERE username = uname AND id <> _target) THEN
      RAISE EXCEPTION 'that username is taken'; END IF;
    UPDATE public.profiles SET username = left(uname, 20) WHERE id = _target;
  END IF;
  IF _color IS NOT NULL AND _color <> '' THEN
    UPDATE public.profiles SET name_color = _color WHERE id = _target; END IF;
  IF _font IS NOT NULL AND _font <> '' THEN
    UPDATE public.profiles SET font_key = _font WHERE id = _target; END IF;
  INSERT INTO public.staff_log (actor, target, action, detail)
  VALUES (_actor, _target, 'set_identity', coalesce(_username,''));
END; $$;

-- mute a device across every account (owner rank 4+)
CREATE OR REPLACE FUNCTION public.staff_device_mute(_actor uuid, _target uuid, _minutes integer DEFAULT 60)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE dev text; n int;
BEGIN
  IF public.rank_level(_actor) < 4 THEN RAISE EXCEPTION 'owner rank required'; END IF;
  SELECT device_id INTO dev FROM public.profiles WHERE id = _target;
  IF dev IS NULL OR dev = '' THEN RAISE EXCEPTION 'no device id on record for that member yet'; END IF;
  UPDATE public.profiles SET muted_until = now() + make_interval(mins => _minutes) WHERE device_id = dev;
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO public.staff_log (actor, target, action, detail) VALUES (_actor, _target, 'device_mute', dev);
  RETURN n;
END; $$;

-- TON 618 only: wipe an account, every message, and ban the device
CREATE OR REPLACE FUNCTION public.ton618_delete_all(_actor uuid, _target uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE dev text; uname text; msgs int;
BEGIN
  IF public.rank_level(_actor) < 6 THEN RAISE EXCEPTION 'TON 618 rank required'; END IF;
  IF _actor = _target THEN RAISE EXCEPTION 'you cannot delete yourself'; END IF;
  SELECT username, device_id INTO uname, dev FROM public.profiles WHERE id = _target;
  IF uname IS NULL THEN RAISE EXCEPTION 'target user not found'; END IF;

  IF dev IS NOT NULL AND dev <> '' THEN
    INSERT INTO public.device_bans (device_id, reason, banned_by)
    VALUES (dev, 'delete all: ' || uname, _actor)
    ON CONFLICT (device_id) DO UPDATE SET reason = excluded.reason, banned_by = excluded.banned_by;
  END IF;

  SELECT count(*) INTO msgs FROM public.messages WHERE user_id = _target;
  DELETE FROM public.messages WHERE user_id = _target;
  DELETE FROM public.code_redemptions WHERE user_id = _target;
  DELETE FROM public.user_achievements WHERE user_id = _target;
  DELETE FROM public.user_stats WHERE user_id = _target;
  DELETE FROM public.user_roles WHERE user_id = _target;
  DELETE FROM public.user_credentials WHERE user_id = _target;
  DELETE FROM public.inventory WHERE user_id = _target;
  DELETE FROM public.profiles WHERE id = _target;

  INSERT INTO public.staff_log (actor, action, detail)
  VALUES (_actor, 'delete_all', uname || ' (' || msgs::text || ' messages)');
  RETURN jsonb_build_object('username', uname, 'messages', msgs, 'device', coalesce(dev,''));
END; $$;

-- allow deleting the rows the wipe needs
DROP POLICY IF EXISTS "staff delete messages" ON public.messages;