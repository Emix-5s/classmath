ALTER TABLE public.user_roles ADD COLUMN role_key text NOT NULL DEFAULT 'user';
UPDATE public.user_roles SET role_key = CASE role::text WHEN 'ton618' THEN 'owner' WHEN 'owner' THEN 'owner' WHEN 'von' THEN 'admin' WHEN 'coverstar' THEN 'admin' WHEN 'co_owner' THEN 'admin' WHEN 'super_mod' THEN 'admin' WHEN 'admin' THEN 'admin' WHEN 'mod' THEN 'mod' ELSE 'user' END;
ALTER TABLE public.user_roles ADD CONSTRAINT club_four_roles CHECK (role_key IN ('user','mod','admin','owner'));
COMMENT ON COLUMN public.user_roles.role IS 'DEPRECATED: replaced by role_key; retained for compatibility only';
CREATE OR REPLACE FUNCTION public.rank_level(_user uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$ SELECT coalesce(max(CASE role_key WHEN 'owner' THEN 7 WHEN 'admin' THEN 6 WHEN 'mod' THEN 1 ELSE 0 END),0) FROM public.user_roles WHERE user_id=_user $$;
CREATE OR REPLACE FUNCTION public.rank_name(_user uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$ SELECT CASE public.rank_level(_user) WHEN 7 THEN 'Owner' WHEN 6 THEN 'Admin' WHEN 1 THEN 'Moderator' ELSE 'Member' END $$;
CREATE OR REPLACE FUNCTION public.club_request_user() RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE t text; u uuid;
BEGIN
 t := coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-club-token','');
 IF t !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN NULL; END IF;
 SELECT s.user_id INTO u FROM public.club_sessions s JOIN public.profiles p ON p.id=s.user_id WHERE s.token=t::uuid AND s.expires_at>now() AND NOT p.banned AND NOT EXISTS (SELECT 1 FROM public.device_bans b WHERE b.device_id=p.device_id);
 RETURN u;
END $$;
CREATE OR REPLACE FUNCTION public.assert_club_user(_user uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ BEGIN IF _user IS NULL OR public.club_request_user() IS DISTINCT FROM _user THEN RAISE EXCEPTION 'Please sign in again to continue'; END IF; END $$;
CREATE OR REPLACE FUNCTION public.assert_club_staff(_actor uuid, _target uuid, _minimum integer) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a integer;
BEGIN
 PERFORM public.assert_club_user(_actor); a:=public.rank_level(_actor);
 IF a<_minimum THEN RAISE EXCEPTION 'Your role cannot use this power'; END IF;
 IF _target IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=_target) THEN RAISE EXCEPTION 'Member not found'; END IF;
 IF _target IS NOT NULL AND a<7 AND public.rank_level(_target)>=a THEN RAISE EXCEPTION 'You can only manage lower-ranked members'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.current_club_rank() RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$ DECLARE u uuid:=public.club_request_user(); BEGIN IF u IS NULL THEN RAISE EXCEPTION 'Please sign in again to continue'; END IF; RETURN CASE public.rank_level(u) WHEN 7 THEN 3 WHEN 6 THEN 2 WHEN 1 THEN 1 ELSE 0 END; END $$;
CREATE OR REPLACE FUNCTION public.session_member(_token uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ DECLARE u uuid; BEGIN SELECT s.user_id INTO u FROM public.club_sessions s JOIN public.profiles p ON p.id=s.user_id WHERE s.token=_token AND s.expires_at>now() AND NOT p.banned AND NOT EXISTS(SELECT 1 FROM public.device_bans b WHERE b.device_id=p.device_id); IF u IS NULL THEN RAISE EXCEPTION 'Please sign in again to continue'; END IF; RETURN u; END $$;
CREATE OR REPLACE FUNCTION public.staff_set_rank(_actor uuid,_target uuid,_rank text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 PERFORM public.assert_club_staff(_actor,_target,7);
 IF _rank NOT IN ('user','member','mod','admin','owner') THEN RAISE EXCEPTION 'Choose Member, Moderator, Admin, or Owner'; END IF;
 PERFORM pg_advisory_xact_lock(846182);
 IF public.rank_level(_target)=7 AND _rank<>'owner' AND NOT EXISTS(SELECT 1 FROM public.user_roles WHERE role_key='owner' AND user_id<>_target) THEN RAISE EXCEPTION 'The last Owner cannot be removed'; END IF;
 DELETE FROM public.user_roles WHERE user_id=_target;
 INSERT INTO public.user_roles(user_id,role,role_key) VALUES(_target,'user',CASE WHEN _rank='member' THEN 'user' ELSE _rank END);
 INSERT INTO public.staff_log(actor,target,action,detail) VALUES(_actor,_target,'set_rank',_rank);
END $$;
CREATE OR REPLACE FUNCTION public.mod_grant_coins(_actor uuid,_target uuid,_amount bigint) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE cap bigint;
BEGIN
 PERFORM public.assert_club_staff(_actor,_target,6);
 cap:=CASE WHEN public.rank_level(_actor)=7 THEN 2000000000 ELSE 10000000 END;
 IF _amount IS NULL OR _amount=0 OR _amount > cap OR _amount < -cap THEN RAISE EXCEPTION 'Coin amount exceeds your role limit'; END IF;
 UPDATE public.profiles SET coins=least(2147483647::bigint,greatest(0,coins::bigint+_amount))::integer WHERE id=_target;
 INSERT INTO public.staff_log(actor,target,action,detail) VALUES(_actor,_target,'grant_coins',_amount::text);
END $$;
CREATE OR REPLACE FUNCTION public.reset_font(_user uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ BEGIN PERFORM public.assert_club_user(_user); UPDATE public.profiles SET font_key='body' WHERE id=_user; END $$;
DO $secure$
DECLARE f record; d text; guard text; minrank integer;
BEGIN
 FOR f IN SELECT p.oid,p.proname,p.proargnames FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND (('_actor'=ANY(p.proargnames)) OR ('_user'=ANY(p.proargnames))) AND p.proname NOT IN ('assert_club_user','assert_club_staff','staff_set_rank','mod_grant_coins','reset_font','bump_progress','game_settle','synth_purge_reward','claim_mod') LOOP
  d:=pg_get_functiondef(f.oid);
  IF '_actor'=ANY(f.proargnames) THEN
   minrank:=CASE WHEN f.proname IN ('mod_action','delete_message') THEN 1 WHEN f.proname IN ('purge_user_messages','staff_reset_look','staff_set_identity','von_action','power_action','elite_action') THEN 6 ELSE 7 END;
   guard:=' PERFORM public.assert_club_staff(_actor,' || CASE WHEN '_target'=ANY(f.proargnames) THEN '_target' ELSE 'NULL' END || ',' || minrank::text || '); ';
   IF f.proname='mod_action' THEN guard:=guard || ' IF public.rank_level(_actor)=1 AND (_action NOT IN (''mute'',''unmute'') OR (_action=''mute'' AND (_minutes IS NULL OR _minutes<1 OR _minutes>10))) THEN RAISE EXCEPTION ''Moderator may only mute for up to ten minutes or unmute''; END IF; '; END IF;
   IF f.proname='delete_message' THEN guard:=guard || ' PERFORM public.assert_club_staff(_actor,(SELECT user_id FROM public.messages WHERE id=_message),1); '; END IF;
   IF f.proname='von_action' THEN guard:=guard || ' IF _action IN (''hwid'',''mass_unmute'') THEN PERFORM public.assert_club_staff(_actor,NULL,7); END IF; '; END IF;
   IF f.proname='power_action' THEN guard:=guard || ' IF _action=''whois'' OR _target IS NULL OR _action IN (''global_xp'',''reset_all_dailies'',''mass_unban'',''lock_all'',''unlock_all'',''wipe_all_messages'',''vip_all'',''clear_staff_log'',''demote'',''steal_coins'') THEN PERFORM public.assert_club_staff(_actor,NULL,7); END IF; IF _action=''demote'' AND public.rank_level(_target)=7 THEN RAISE EXCEPTION ''Change Owner roles using the rank controls''; END IF; '; END IF;
   IF f.proname='elite_action' THEN guard:=guard || ' IF left(_action,2)=''t_'' THEN PERFORM public.assert_club_staff(_actor,NULL,7); END IF; '; d:=replace(d,'IF public.rank_level(_target) >= a THEN','IF a < 7 AND public.rank_level(_target) >= a THEN'); d:=replace(d,'WHEN ''t_reset_password'' THEN','WHEN ''t_reset_password'' THEN DELETE FROM public.club_sessions WHERE user_id=_target;'); END IF;
   IF f.proname='ton618_delete_all' THEN guard:=guard || ' IF public.rank_level(_target)=7 AND NOT EXISTS(SELECT 1 FROM public.user_roles WHERE role_key=''owner'' AND user_id<>_target) THEN RAISE EXCEPTION ''The last Owner cannot be deleted''; END IF; '; d:=replace(d,'DELETE FROM public.profiles WHERE id = _target;','DELETE FROM public.platformer_runs WHERE user_id=_target; DELETE FROM public.platformer_upgrades WHERE user_id=_target; DELETE FROM public.game_payouts WHERE user_id=_target; DELETE FROM public.game_sessions WHERE user_id=_target; DELETE FROM public.club_sessions WHERE user_id=_target; DELETE FROM public.profiles WHERE id = _target;'); END IF;
  ELSE guard:=' PERFORM public.assert_club_user(_user); ';
  END IF;
  d:=regexp_replace(d,'\mBEGIN\M', 'BEGIN ' || guard,'i');
  d:=replace(replace(replace(replace(d,'TON 618','Owner'),'COVERST4R','Admin'),'co-owner rank required','Admin rank required'),'von rank required','Admin rank required');
  EXECUTE d;
 END LOOP;
END $secure$;
DO $policies$
DECLARE r record;
BEGIN
 FOR r IN SELECT tablename,policyname FROM pg_policies WHERE schemaname='public' AND tablename IN ('profiles','messages','inventory','user_achievements','user_roles','rooms','shop_items','achievements') LOOP EXECUTE format('DROP POLICY %I ON public.%I',r.policyname,r.tablename); END LOOP;
END $policies$;
REVOKE ALL ON public.profiles,public.messages,public.inventory,public.user_achievements,public.user_roles,public.rooms,public.shop_items,public.achievements FROM anon,authenticated;
GRANT SELECT(id,username,coins,xp,level,name_color,font_key,vip_tier,muted_until,banned,last_claim_at,streak,created_at) ON public.profiles TO anon,authenticated;
GRANT SELECT ON public.messages,public.inventory,public.user_achievements,public.rooms,public.shop_items,public.achievements TO anon,authenticated;
GRANT SELECT(user_id,role_key) ON public.user_roles TO anon,authenticated;
GRANT INSERT(room_id,user_id,content) ON public.messages TO anon,authenticated;
CREATE POLICY club_public_profiles ON public.profiles FOR SELECT TO anon,authenticated USING(public.club_request_user() IS NOT NULL);
CREATE POLICY club_own_inventory ON public.inventory FOR SELECT TO anon,authenticated USING(user_id=public.club_request_user());
CREATE POLICY club_own_achievements ON public.user_achievements FOR SELECT TO anon,authenticated USING(user_id=public.club_request_user());
CREATE POLICY club_badges ON public.user_roles FOR SELECT TO anon,authenticated USING(public.club_request_user() IS NOT NULL);
CREATE POLICY club_rooms ON public.rooms FOR SELECT TO anon,authenticated USING(public.club_request_user() IS NOT NULL AND (NOT mod_only OR public.rank_level(public.club_request_user())>=1));
CREATE POLICY club_shop ON public.shop_items FOR SELECT TO anon,authenticated USING(public.club_request_user() IS NOT NULL);
CREATE POLICY club_achievements ON public.achievements FOR SELECT TO anon,authenticated USING(public.club_request_user() IS NOT NULL);
CREATE POLICY club_read_messages ON public.messages FOR SELECT TO anon,authenticated USING(public.club_request_user() IS NOT NULL AND NOT deleted AND EXISTS(SELECT 1 FROM public.rooms r WHERE r.id=room_id AND (NOT r.mod_only OR public.rank_level(public.club_request_user())>=1)));
CREATE POLICY club_post_messages ON public.messages FOR INSERT TO anon,authenticated WITH CHECK(user_id=public.club_request_user() AND EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=user_id AND NOT p.banned AND (p.muted_until IS NULL OR p.muted_until<now())) AND EXISTS(SELECT 1 FROM public.rooms r WHERE r.id=room_id AND (NOT r.mod_only OR public.rank_level(public.club_request_user())>=1)));
DO $permissions$
DECLARE f record;
BEGIN
 FOR f IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' LOOP
  EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.oid::regprocedure);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',f.oid::regprocedure);
  IF f.proname IN ('club_request_user','rank_level','current_club_rank','signup_user','login_user','open_club_session','buy_item','claim_achievement','claim_daily','delete_message','delete_own_message','elite_action','equip_item','inspect_member','list_device_bans','mod_action','mod_grant_coins','platformer_buy','platformer_collect','platformer_open','play_coin_flip','play_dice','play_hilo','play_rps','play_slots','power_action','purge_user_messages','record_device','redeem_code','reset_font','set_name_hex','staff_device_ban','staff_device_mute','staff_device_unban','staff_freeze_room','staff_grant_all','staff_reset_look','staff_set_identity','staff_set_rank','staff_wipe_room','start_game_session','synth_purge_claim','ton618_delete_all','ton618_wipe_database','von_action') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon,authenticated',f.oid::regprocedure); END IF;
 END LOOP;
END $permissions$;
CREATE OR REPLACE FUNCTION public.list_device_bans(_token uuid) RETURNS TABLE(id uuid,device_id text,reason text) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$ BEGIN IF public.rank_level(public.session_member(_token))<7 THEN RAISE EXCEPTION 'Owner only'; END IF; RETURN QUERY SELECT b.id,b.device_id,b.reason FROM public.device_bans b ORDER BY b.created_at DESC; END $$;