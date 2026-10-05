CREATE OR REPLACE FUNCTION public.elite_action(_actor uuid, _target uuid, _action text, _value text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
DECLARE
  a int := public.rank_level(_actor);
  n int := 0; v bigint; uname text;
  ton text[] := ARRAY['t_max_coins','t_zero_coins','t_max_level','t_rename','t_reset_password','t_mute_all','t_set_all_coins','t_reset_all_xp','t_remove_all_vip','t_skins_all','t_ban_all_members','t_complete_achievements','t_swap_coins','t_clone_look'];
  glob text[] := ARRAY['t_mute_all','t_set_all_coins','t_reset_all_xp','t_remove_all_vip','t_skins_all','t_ban_all_members'];
BEGIN
  IF a < 5 THEN RAISE EXCEPTION 'COVERST4R rank required'; END IF;
  IF _action = ANY(ton) AND a < 7 THEN RAISE EXCEPTION 'TON 618 only'; END IF;
  IF NOT (_action = ANY(glob)) THEN
    IF _target IS NULL OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = _target) THEN RAISE EXCEPTION 'pick a member first'; END IF;
    IF public.rank_level(_target) >= a THEN RAISE EXCEPTION 'cannot act on someone of your rank or higher'; END IF;
  END IF;
  CASE _action
    WHEN 'c_set_xp' THEN v := least(greatest(coalesce(nullif(_value,'')::bigint,0),0),100000000);
      UPDATE profiles SET xp = v::int WHERE id = _target;
    WHEN 'c_reset_coins' THEN UPDATE profiles SET coins = 500 WHERE id = _target;
    WHEN 'c_halve_coins' THEN UPDATE profiles SET coins = coins / 2 WHERE id = _target;
    WHEN 'c_give_vip' THEN UPDATE profiles SET vip_tier = 'VIP+' WHERE id = _target;
    WHEN 'c_remove_vip' THEN UPDATE profiles SET vip_tier = NULL WHERE id = _target;
    WHEN 'c_reset_font' THEN UPDATE profiles SET font_key = 'body' WHERE id = _target;
    WHEN 'c_reset_color' THEN UPDATE profiles SET name_color = '#ffffff' WHERE id = _target;
    WHEN 'c_random_color' THEN UPDATE profiles SET name_color = '#' || lpad(to_hex((random()*16777215)::int),6,'0') WHERE id = _target;
    WHEN 'c_random_skin' THEN
      INSERT INTO inventory (user_id, item_id) SELECT _target, s.id FROM shop_items s
      WHERE NOT EXISTS (SELECT 1 FROM inventory i WHERE i.user_id=_target AND i.item_id=s.id) ORDER BY random() LIMIT 1;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'c_mute_day' THEN UPDATE profiles SET muted_until = now() + interval '1 day' WHERE id = _target;
    WHEN 'c_unmute' THEN UPDATE profiles SET muted_until = NULL WHERE id = _target;
    WHEN 'c_ban' THEN UPDATE profiles SET banned = true WHERE id = _target;
    WHEN 'c_unban' THEN UPDATE profiles SET banned = false WHERE id = _target;
    WHEN 'c_reset_achievements' THEN DELETE FROM user_achievements WHERE user_id = _target; GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 't_max_coins' THEN UPDATE profiles SET coins = 2147483647 WHERE id = _target;
    WHEN 't_zero_coins' THEN UPDATE profiles SET coins = 0 WHERE id = _target;
    WHEN 't_max_level' THEN UPDATE profiles SET level = 1000, xp = 100000000 WHERE id = _target;
    WHEN 't_rename' THEN
      uname := left(lower(regexp_replace(coalesce(_value,''),'[^a-zA-Z0-9_]','','g')),20);
      IF uname = '' THEN RAISE EXCEPTION 'invalid name'; END IF;
      IF EXISTS (SELECT 1 FROM profiles WHERE username = uname AND id <> _target) THEN RAISE EXCEPTION 'that username is taken'; END IF;
      UPDATE profiles SET username = uname WHERE id = _target;
    WHEN 't_reset_password' THEN
      IF length(coalesce(_value,'')) < 4 THEN RAISE EXCEPTION 'password must be at least 4 characters'; END IF;
      INSERT INTO user_credentials (user_id, password_hash) VALUES (_target, crypt(_value, gen_salt('bf')))
      ON CONFLICT (user_id) DO UPDATE SET password_hash = EXCLUDED.password_hash;
    WHEN 't_complete_achievements' THEN
      INSERT INTO user_achievements (user_id, achievement_id, progress)
      SELECT _target, ac.id, ac.goal FROM achievements ac
      WHERE NOT EXISTS (SELECT 1 FROM user_achievements u WHERE u.user_id=_target AND u.achievement_id=ac.id);
      UPDATE user_achievements u SET progress = ac.goal FROM achievements ac WHERE u.achievement_id=ac.id AND u.user_id=_target;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 't_swap_coins' THEN
      SELECT coins INTO v FROM profiles WHERE id = _target;
      UPDATE profiles SET coins = (SELECT coins FROM profiles WHERE id = _actor) WHERE id = _target;
      UPDATE profiles SET coins = v::int WHERE id = _actor;
    WHEN 't_clone_look' THEN
      UPDATE profiles t SET name_color = me.name_color, font_key = me.font_key FROM profiles me WHERE me.id=_actor AND t.id=_target;
    WHEN 't_mute_all' THEN v := least(greatest(coalesce(nullif(_value,'')::bigint,10),1),525600);
      UPDATE profiles SET muted_until = now() + make_interval(mins => v::int) WHERE public.rank_level(id) < 1;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 't_set_all_coins' THEN v := least(greatest(coalesce(nullif(_value,'')::bigint,500),0),2147483647);
      UPDATE profiles SET coins = v::int WHERE id <> _actor; GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 't_reset_all_xp' THEN UPDATE profiles SET xp = 0, level = 1 WHERE id <> _actor; GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 't_remove_all_vip' THEN UPDATE profiles SET vip_tier = NULL WHERE id <> _actor AND vip_tier IS NOT NULL; GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 't_skins_all' THEN
      INSERT INTO inventory (user_id, item_id) SELECT p.id, s.id FROM profiles p CROSS JOIN shop_items s
      WHERE NOT EXISTS (SELECT 1 FROM inventory i WHERE i.user_id=p.id AND i.item_id=s.id);
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 't_ban_all_members' THEN UPDATE profiles SET banned = true WHERE public.rank_level(id) < 1; GET DIAGNOSTICS n = ROW_COUNT;
    ELSE RAISE EXCEPTION 'unknown power';
  END CASE;
  INSERT INTO staff_log (actor, target, action, detail) VALUES (_actor, _target, _action, coalesce(CASE WHEN _action='t_reset_password' THEN '' ELSE _value END,''));
  RETURN jsonb_build_object('count', n);
END; $$;
GRANT EXECUTE ON FUNCTION public.elite_action(uuid,uuid,text,text) TO anon, authenticated;