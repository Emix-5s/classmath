CREATE OR REPLACE FUNCTION public.power_action(_actor uuid, _target uuid, _action text, _value text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a int := public.rank_level(_actor);
  t int := 0;
  n int := 0;
  v bigint;
  global_actions text[] := ARRAY['global_xp','reset_all_dailies','mass_unban','lock_all','unlock_all','wipe_all_messages','vip_all','clear_staff_log'];
  ton_actions text[] := ARRAY['global_xp','reset_all_dailies','mass_unban','lock_all','unlock_all','wipe_all_messages','vip_all','clear_staff_log','demote','steal_coins'];
  info jsonb;
BEGIN
  IF a < 6 THEN RAISE EXCEPTION 'not allowed'; END IF;
  IF _action = ANY(ton_actions) AND a < 7 THEN RAISE EXCEPTION 'TON 618 only'; END IF;
  IF NOT (_action = ANY(global_actions)) THEN
    IF _target IS NULL OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = _target) THEN RAISE EXCEPTION 'pick a member first'; END IF;
    t := public.rank_level(_target);
    IF _action <> 'whois' AND t >= a THEN RAISE EXCEPTION 'cannot act on someone of your rank or higher'; END IF;
  END IF;

  CASE _action
    WHEN 'take_coins' THEN
      v := greatest(0, coalesce(nullif(_value,'')::bigint, 0));
      UPDATE profiles SET coins = greatest(0, coins - least(v, 2147483647)::int) WHERE id = _target;
    WHEN 'double_coins' THEN
      UPDATE profiles SET coins = least(coins::bigint * 2, 2147483647)::int WHERE id = _target;
    WHEN 'set_level' THEN
      v := least(greatest(coalesce(nullif(_value,'')::bigint,1),1),1000);
      UPDATE profiles SET level = v::int WHERE id = _target;
    WHEN 'set_color' THEN
      IF _value !~ '^#[0-9A-Fa-f]{6}$' THEN RAISE EXCEPTION 'colour must look like #ff00aa'; END IF;
      UPDATE profiles SET name_color = _value WHERE id = _target;
    WHEN 'clear_inventory' THEN
      DELETE FROM inventory WHERE user_id = _target;
      UPDATE profiles SET name_color = DEFAULT, font_key = DEFAULT WHERE id = _target;
    WHEN 'give_all_items' THEN
      INSERT INTO inventory (user_id, item_id)
      SELECT _target, s.id FROM shop_items s
      WHERE NOT EXISTS (SELECT 1 FROM inventory i WHERE i.user_id = _target AND i.item_id = s.id);
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'reset_streak' THEN
      UPDATE profiles SET streak = 0 WHERE id = _target;
    WHEN 'mute_custom' THEN
      v := least(greatest(coalesce(nullif(_value,'')::bigint,10),1),525600);
      UPDATE profiles SET muted_until = now() + make_interval(mins => v::int) WHERE id = _target;
    WHEN 'clear_messages' THEN
      UPDATE messages SET deleted = true WHERE user_id = _target AND deleted = false;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'whois' THEN
      SELECT jsonb_build_object('username', username, 'coins', coins, 'xp', xp, 'level', level,
        'vip', vip_tier, 'banned', banned, 'muted_until', muted_until, 'joined', created_at,
        'rank', public.rank_name(_target),
        'messages', (SELECT count(*) FROM messages m WHERE m.user_id = _target))
      INTO info FROM profiles WHERE id = _target;
      RETURN info;
    WHEN 'demote' THEN
      DELETE FROM user_roles WHERE user_id = _target;
    WHEN 'steal_coins' THEN
      SELECT coins INTO v FROM profiles WHERE id = _target;
      UPDATE profiles SET coins = 0 WHERE id = _target;
      UPDATE profiles SET coins = least(coins::bigint + v, 2147483647)::int WHERE id = _actor;
      n := v;
    WHEN 'global_xp' THEN
      v := least(greatest(coalesce(nullif(_value,'')::bigint,100),1),100000);
      UPDATE profiles SET xp = least(xp::bigint + v, 2147483647)::int WHERE id IS NOT NULL;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'reset_all_dailies' THEN
      UPDATE profiles SET last_claim_at = NULL WHERE last_claim_at IS NOT NULL;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'mass_unban' THEN
      UPDATE profiles SET banned = false WHERE banned = true;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'lock_all' THEN
      UPDATE rooms SET locked = true WHERE locked = false;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'unlock_all' THEN
      UPDATE rooms SET locked = false WHERE locked = true;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'wipe_all_messages' THEN
      UPDATE messages SET deleted = true WHERE deleted = false;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'vip_all' THEN
      UPDATE profiles SET vip_tier = coalesce(nullif(_value,''),'VIP') WHERE vip_tier IS NULL;
      GET DIAGNOSTICS n = ROW_COUNT;
    WHEN 'clear_staff_log' THEN
      DELETE FROM staff_log WHERE created_at IS NOT NULL;
      GET DIAGNOSTICS n = ROW_COUNT;
    ELSE RAISE EXCEPTION 'unknown power';
  END CASE;

  INSERT INTO staff_log (action, actor, target, detail) VALUES (_action, _actor, _target, coalesce(_value,''));
  RETURN jsonb_build_object('count', n);
END $$;

GRANT EXECUTE ON FUNCTION public.power_action(uuid, uuid, text, text) TO anon, authenticated, service_role;