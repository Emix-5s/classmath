CREATE OR REPLACE FUNCTION public.staff_set_rank(_actor uuid, _target uuid, _rank text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE lvl int := public.rank_level(_actor); want int;
BEGIN
  IF lvl < 3 THEN RAISE EXCEPTION 'co-owner rank required'; END IF;
  want := CASE _rank WHEN 'ton618' THEN 6 WHEN 'coverstar' THEN 5 WHEN 'owner' THEN 4
                     WHEN 'co_owner' THEN 3 WHEN 'super_mod' THEN 2
                     WHEN 'mod' THEN 1 WHEN 'member' THEN 0 ELSE -1 END;
  IF want < 0 THEN RAISE EXCEPTION 'unknown rank'; END IF;
  IF lvl < 6 AND (want >= lvl OR public.rank_level(_target) >= lvl) THEN
    RAISE EXCEPTION 'you can only manage ranks below your own'; END IF;
  DELETE FROM public.user_roles
   WHERE user_id = _target AND role::text IN ('mod','super_mod','co_owner','owner','admin','coverstar','ton618');
  IF want > 0 THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (_target, _rank::public.app_role)
    ON CONFLICT DO NOTHING;
  END IF;
  INSERT INTO public.staff_log (actor, target, action, detail)
  VALUES (_actor, _target, 'set_rank', _rank);
END; $$;