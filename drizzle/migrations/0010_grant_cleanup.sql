DROP FUNCTION IF EXISTS public.mod_grant_coins(uuid, uuid, integer);
CREATE OR REPLACE FUNCTION public.mod_grant_coins(_actor uuid, _target uuid, _amount bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE lvl int := public.rank_level(_actor); cap bigint;
BEGIN
  IF lvl < 1 THEN RAISE EXCEPTION 'you are not staff'; END IF;
  cap := CASE lvl WHEN 1 THEN 100000 WHEN 2 THEN 500000 WHEN 3 THEN 10000000 ELSE 2000000000 END;
  IF _amount = 0 THEN RAISE EXCEPTION 'amount cannot be zero'; END IF;
  IF _amount < 0 AND lvl < 3 THEN RAISE EXCEPTION 'only co-owners and above can remove coins'; END IF;
  IF abs(_amount) > cap THEN RAISE EXCEPTION 'your limit is % coins', cap; END IF;
  UPDATE public.profiles SET coins = least(2147483647::bigint, greatest(0, coins::bigint + _amount))::int WHERE id = _target;
  IF NOT found THEN RAISE EXCEPTION 'target user not found'; END IF;
  INSERT INTO public.staff_log (actor, target, action, detail)
  VALUES (_actor, _target, 'grant_coins', _amount::text);
END; $$;