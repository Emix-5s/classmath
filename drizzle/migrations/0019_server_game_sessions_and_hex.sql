CREATE TABLE public.game_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT now(),
  last_claim_at timestamptz NOT NULL DEFAULT now(),
  credits_claimed integer NOT NULL DEFAULT 0
);
GRANT ALL ON public.game_sessions TO service_role;
ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.start_game_session(_user uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE sid uuid; recent int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = _user AND NOT banned) THEN RAISE EXCEPTION 'account not found'; END IF;
  SELECT count(*) INTO recent FROM game_sessions WHERE user_id = _user AND started_at > now() - interval '1 minute';
  IF recent >= 5 THEN RAISE EXCEPTION 'too many game sessions'; END IF;
  INSERT INTO game_sessions (user_id) VALUES (_user) RETURNING id INTO sid;
  RETURN sid;
END $$;

CREATE OR REPLACE FUNCTION public.synth_purge_claim(_user uuid, _session uuid, _credits integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s record; allowed int; use_credits int; _coins int; _hour int;
BEGIN
  IF _credits IS NULL OR _credits < 10 THEN RETURN jsonb_build_object('coins',0); END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = _user AND NOT banned) THEN RAISE EXCEPTION 'account not found'; END IF;
  SELECT * INTO s FROM game_sessions WHERE id = _session AND user_id = _user FOR UPDATE;
  IF s.id IS NULL THEN RAISE EXCEPTION 'invalid game session'; END IF;
  IF s.last_claim_at > now() - interval '8 seconds' THEN RETURN jsonb_build_object('coins',0,'reason','too fast'); END IF;
  -- at most 20 credits per real second played since last claim, max 5 minutes banked
  allowed := least(extract(epoch FROM (now() - s.last_claim_at))::int, 300) * 20;
  use_credits := least(_credits, allowed, 10000);
  _coins := use_credits / 10;
  SELECT coalesce(sum(amount),0) INTO _hour FROM game_payouts WHERE user_id = _user AND created_at > now() - interval '1 hour';
  _coins := greatest(0, least(_coins, 5000 - _hour));
  UPDATE game_sessions SET last_claim_at = now(), credits_claimed = credits_claimed + use_credits WHERE id = s.id;
  IF _coins = 0 THEN RETURN jsonb_build_object('coins',0,'reason','hourly cap'); END IF;
  INSERT INTO game_payouts(user_id, amount) VALUES (_user, _coins);
  UPDATE profiles SET coins = least(2147483647::bigint, coins::bigint + _coins)::integer WHERE id = _user;
  RETURN jsonb_build_object('coins', _coins);
END $$;

REVOKE EXECUTE ON FUNCTION public.synth_purge_reward(uuid, integer) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.synth_purge_reward(uuid, integer) IS 'DEPRECATED: replaced by synth_purge_claim';

CREATE OR REPLACE FUNCTION public.set_name_hex(_user uuid, _hex text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF _hex !~ '^#[0-9A-Fa-f]{6}$' THEN RAISE EXCEPTION 'colour must look like #ff00aa'; END IF;
  UPDATE profiles SET name_color = lower(_hex) WHERE id = _user AND NOT banned;
  IF NOT found THEN RAISE EXCEPTION 'account not found'; END IF;
END $$;