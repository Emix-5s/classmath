CREATE TABLE public.game_payouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.game_payouts TO service_role;
ALTER TABLE public.game_payouts ENABLE ROW LEVEL SECURITY;
CREATE INDEX game_payouts_user_time ON public.game_payouts(user_id, created_at);

CREATE OR REPLACE FUNCTION public.synth_purge_reward(_user uuid, _credits integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _coins integer; _hour integer; _last timestamptz;
BEGIN
  IF _credits IS NULL OR _credits < 10 THEN RETURN jsonb_build_object('coins',0); END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = _user AND NOT banned) THEN RAISE EXCEPTION 'account not found'; END IF;
  SELECT max(created_at) INTO _last FROM game_payouts WHERE user_id = _user;
  IF _last IS NOT NULL AND _last > now() - interval '8 seconds' THEN RETURN jsonb_build_object('coins',0,'reason','too fast'); END IF;
  _coins := least(_credits / 10, 1000);
  SELECT coalesce(sum(amount),0) INTO _hour FROM game_payouts WHERE user_id = _user AND created_at > now() - interval '1 hour';
  _coins := greatest(0, least(_coins, 5000 - _hour));
  IF _coins = 0 THEN RETURN jsonb_build_object('coins',0,'reason','hourly cap'); END IF;
  INSERT INTO game_payouts(user_id, amount) VALUES (_user, _coins);
  UPDATE profiles SET coins = least(2147483647::bigint, coins::bigint + _coins)::integer WHERE id = _user;
  RETURN jsonb_build_object('coins', _coins);
END $$;
GRANT EXECUTE ON FUNCTION public.synth_purge_reward(uuid, integer) TO anon, authenticated;