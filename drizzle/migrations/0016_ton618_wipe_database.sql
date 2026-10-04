CREATE OR REPLACE FUNCTION public.ton618_wipe_database(_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  keep uuid[];
  m int; p int;
BEGIN
  IF public.rank_level(_actor) < 7 THEN RAISE EXCEPTION 'TON 618 only'; END IF;
  SELECT array_agg(id) INTO keep FROM profiles
    WHERE lower(username) IN ('will','eminjesse3','bigv','kylerthemonk');
  keep := coalesce(keep, ARRAY[]::uuid[]) || _actor;

  DELETE FROM messages WHERE id IS NOT NULL;
  GET DIAGNOSTICS m = ROW_COUNT;
  DELETE FROM user_achievements WHERE id IS NOT NULL;
  DELETE FROM code_redemptions WHERE NOT (user_id = ANY(keep));
  DELETE FROM user_stats WHERE NOT (user_id = ANY(keep));
  DELETE FROM user_roles WHERE NOT (user_id = ANY(keep));
  DELETE FROM user_credentials WHERE NOT (user_id = ANY(keep));
  DELETE FROM inventory WHERE NOT (user_id = ANY(keep));
  DELETE FROM profiles WHERE NOT (id = ANY(keep));
  GET DIAGNOSTICS p = ROW_COUNT;

  INSERT INTO staff_log (action, actor, detail) VALUES ('wipe_database', _actor, m || ' messages, ' || p || ' accounts');
  RETURN jsonb_build_object('messages', m, 'profiles', p);
END $$;

GRANT EXECUTE ON FUNCTION public.ton618_wipe_database(uuid) TO anon, authenticated, service_role;