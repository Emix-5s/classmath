CREATE OR REPLACE FUNCTION public.rank_level(_user uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT coalesce(max(CASE role::text
    WHEN 'ton618' THEN 7 WHEN 'von' THEN 6 WHEN 'coverstar' THEN 5 WHEN 'owner' THEN 4
    WHEN 'co_owner' THEN 3 WHEN 'admin' THEN 3 WHEN 'super_mod' THEN 2 WHEN 'mod' THEN 1 ELSE 0 END), 0)
  FROM public.user_roles WHERE user_id = _user $$;

CREATE OR REPLACE FUNCTION public.rank_name(_user uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE public.rank_level(_user) WHEN 7 THEN 'ton618' WHEN 6 THEN 'von' WHEN 5 THEN 'coverstar'
    WHEN 4 THEN 'owner' WHEN 3 THEN 'co_owner' WHEN 2 THEN 'super_mod' WHEN 1 THEN 'mod' ELSE 'member' END $$;

CREATE OR REPLACE FUNCTION public.staff_device_ban(_actor uuid, _target uuid, _reason text DEFAULT ''::text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE dev text;
BEGIN
  IF public.rank_level(_actor) < 4 THEN RAISE EXCEPTION 'owner rank required'; END IF;
  IF public.rank_level(_actor) < 7 AND public.rank_level(_target) >= public.rank_level(_actor) THEN
    RAISE EXCEPTION 'you cannot act on someone of your rank or higher'; END IF;
  SELECT device_id INTO dev FROM public.profiles WHERE id = _target;
  IF dev IS NULL OR dev = '' THEN RAISE EXCEPTION 'no device id on record for that member yet'; END IF;
  INSERT INTO public.device_bans (device_id, reason, banned_by) VALUES (dev, coalesce(_reason,''), _actor)
  ON CONFLICT (device_id) DO UPDATE SET reason = excluded.reason, banned_by = excluded.banned_by;
  UPDATE public.profiles SET banned = true WHERE id = _target;
  INSERT INTO public.staff_log (actor, target, action, detail) VALUES (_actor, _target, 'device_ban', dev);
  RETURN dev;
END; $$;

CREATE OR REPLACE FUNCTION public.staff_set_identity(_actor uuid, _target uuid, _username text, _color text, _font text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE uname text;
BEGIN
  IF public.rank_level(_actor) < 5 THEN RAISE EXCEPTION 'coverst4r rank required'; END IF;
  IF public.rank_level(_actor) < 7 AND public.rank_level(_target) >= public.rank_level(_actor) THEN
    RAISE EXCEPTION 'you cannot act on someone of your rank or higher'; END IF;
  IF _username IS NOT NULL AND _username <> '' THEN
    uname := lower(regexp_replace(_username, '[^a-zA-Z0-9_]', '', 'g'));
    IF uname = '' THEN RAISE EXCEPTION 'that name has no usable characters'; END IF;
    IF exists (SELECT 1 FROM public.profiles WHERE username = uname AND id <> _target) THEN
      RAISE EXCEPTION 'that username is taken'; END IF;
    UPDATE public.profiles SET username = left(uname, 20) WHERE id = _target;
  END IF;
  IF _color IS NOT NULL AND _color <> '' THEN UPDATE public.profiles SET name_color = _color WHERE id = _target; END IF;
  IF _font IS NOT NULL AND _font <> '' THEN UPDATE public.profiles SET font_key = _font WHERE id = _target; END IF;
  INSERT INTO public.staff_log (actor, target, action, detail) VALUES (_actor, _target, 'set_identity', coalesce(_username,''));
END; $$;

CREATE OR REPLACE FUNCTION public.staff_set_rank(_actor uuid, _target uuid, _rank text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE lvl int := public.rank_level(_actor); want int;
BEGIN
  IF lvl < 3 THEN RAISE EXCEPTION 'co-owner rank required'; END IF;
  want := CASE _rank WHEN 'ton618' THEN 7 WHEN 'von' THEN 6 WHEN 'coverstar' THEN 5 WHEN 'owner' THEN 4
                     WHEN 'co_owner' THEN 3 WHEN 'super_mod' THEN 2 WHEN 'mod' THEN 1 WHEN 'member' THEN 0 ELSE -1 END;
  IF want < 0 THEN RAISE EXCEPTION 'unknown rank'; END IF;
  IF lvl < 7 AND (want >= lvl OR public.rank_level(_target) >= lvl) THEN
    RAISE EXCEPTION 'you can only manage ranks below your own'; END IF;
  DELETE FROM public.user_roles WHERE user_id = _target AND role::text IN ('mod','super_mod','co_owner','owner','admin','coverstar','von','ton618');
  IF want > 0 THEN INSERT INTO public.user_roles (user_id, role) VALUES (_target, _rank::public.app_role) ON CONFLICT DO NOTHING; END IF;
  INSERT INTO public.staff_log (actor, target, action, detail) VALUES (_actor, _target, 'set_rank', _rank);
END; $$;

CREATE OR REPLACE FUNCTION public.ton618_delete_all(_actor uuid, _target uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE dev text; uname text; msgs int;
BEGIN
  IF public.rank_level(_actor) < 7 THEN RAISE EXCEPTION 'TON 618 rank required'; END IF;
  IF _actor = _target THEN RAISE EXCEPTION 'you cannot delete yourself'; END IF;
  SELECT username, device_id INTO uname, dev FROM public.profiles WHERE id = _target;
  IF uname IS NULL THEN RAISE EXCEPTION 'target user not found'; END IF;
  IF dev IS NOT NULL AND dev <> '' THEN
    INSERT INTO public.device_bans (device_id, reason, banned_by) VALUES (dev, 'delete all: ' || uname, _actor)
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
  INSERT INTO public.staff_log (actor, action, detail) VALUES (_actor, 'delete_all', uname || ' (' || msgs::text || ' messages)');
  RETURN jsonb_build_object('username', uname, 'messages', msgs, 'device', coalesce(dev,''));
END; $$;

-- von powers: one dispatcher
CREATE OR REPLACE FUNCTION public.von_action(_actor uuid, _target uuid, _action text, _value text DEFAULT '') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE lvl int := public.rank_level(_actor); dev text; res jsonb := '{}'::jsonb; n int;
BEGIN
  IF lvl < 6 THEN RAISE EXCEPTION 'von rank required'; END IF;
  IF _target IS NOT NULL THEN
    IF NOT exists (SELECT 1 FROM public.profiles WHERE id = _target) THEN RAISE EXCEPTION 'target user not found'; END IF;
    IF lvl < 7 AND _target <> _actor AND public.rank_level(_target) >= lvl AND _action <> 'hwid' THEN
      RAISE EXCEPTION 'you cannot act on someone of your rank or higher'; END IF;
  END IF;
  CASE _action
  WHEN 'hwid' THEN
    SELECT device_id INTO dev FROM public.profiles WHERE id = _target;
    res := jsonb_build_object('device', coalesce(dev,''),
      'banned', exists (SELECT 1 FROM public.device_bans WHERE device_id = dev),
      'accounts', coalesce((SELECT jsonb_agg(username) FROM public.profiles WHERE device_id = dev AND dev IS NOT NULL AND dev <> ''), '[]'::jsonb));
  WHEN 'give_vip' THEN
    IF _value NOT IN ('VIP','VIP+') THEN RAISE EXCEPTION 'tier must be VIP or VIP+'; END IF;
    UPDATE public.profiles SET vip_tier = _value WHERE id = _target;
  WHEN 'remove_vip' THEN UPDATE public.profiles SET vip_tier = NULL WHERE id = _target;
  WHEN 'set_coins' THEN
    n := greatest(0, least(2147483647, _value::bigint))::int;
    UPDATE public.profiles SET coins = n WHERE id = _target;
  WHEN 'reset_xp' THEN UPDATE public.profiles SET xp = 0, level = 1 WHERE id = _target;
  WHEN 'give_xp' THEN
    n := greatest(0, least(1000000, _value::int));
    UPDATE public.profiles SET xp = xp + n, level = 1 + ((xp + n) / 500) WHERE id = _target;
  WHEN 'unmute' THEN UPDATE public.profiles SET muted_until = NULL WHERE id = _target;
  WHEN 'unban' THEN UPDATE public.profiles SET banned = false WHERE id = _target;
  WHEN 'reset_daily' THEN UPDATE public.profiles SET last_claim_at = NULL WHERE id = _target;
  WHEN 'mass_unmute' THEN
    UPDATE public.profiles SET muted_until = NULL WHERE muted_until > now();
    GET DIAGNOSTICS n = ROW_COUNT; res := jsonb_build_object('count', n);
  ELSE RAISE EXCEPTION 'unknown action';
  END CASE;
  INSERT INTO public.staff_log (actor, target, action, detail) VALUES (_actor, _target, 'von_' || _action, coalesce(_value,''));
  RETURN res;
END; $$;
GRANT EXECUTE ON FUNCTION public.von_action(uuid, uuid, text, text) TO anon, authenticated;