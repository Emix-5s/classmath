CREATE TABLE public.club_sessions (token uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE, expires_at timestamptz NOT NULL DEFAULT now() + interval '7 days');
GRANT ALL ON public.club_sessions TO service_role;
ALTER TABLE public.club_sessions ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.open_club_session(_username text, _password text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE p public.profiles; t uuid;
BEGIN p := public.login_user(_username, _password); INSERT INTO public.club_sessions(user_id) VALUES(p.id) RETURNING token INTO t; RETURN t; END; $$;
CREATE OR REPLACE FUNCTION public.session_member(_token uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN SELECT s.user_id INTO u FROM public.club_sessions s JOIN public.profiles p ON p.id=s.user_id WHERE s.token=_token AND s.expires_at>now() AND NOT p.banned; IF u IS NULL THEN RAISE EXCEPTION 'Please sign in again to continue'; END IF; RETURN u; END; $$;
REVOKE ALL ON FUNCTION public.session_member(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.open_club_session(text,text) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.inspect_member(_token uuid, _target uuid, _offset integer DEFAULT 0) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE actor uuid; details jsonb; history jsonb; total integer;
BEGIN actor := public.session_member(_token); IF public.rank_level(actor) <> 7 THEN RAISE EXCEPTION 'Only TON 618 can open member records'; END IF;
SELECT jsonb_build_object('id',p.id,'username',p.username,'coins',p.coins,'xp',p.xp,'level',p.level,'vip',p.vip_tier,'banned',p.banned,'muted_until',p.muted_until,'device_id',p.device_id,'created_at',p.created_at,'rank',public.rank_name(p.id)) INTO details FROM public.profiles p WHERE p.id=_target;
IF details IS NULL THEN RAISE EXCEPTION 'Member not found'; END IF;
SELECT count(*) INTO total FROM public.messages WHERE user_id=_target;
SELECT coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) INTO history FROM (SELECT m.id,m.content,m.deleted,m.created_at,r.name AS room FROM public.messages m JOIN public.rooms r ON r.id=m.room_id WHERE m.user_id=_target ORDER BY m.created_at DESC,m.id LIMIT 50 OFFSET greatest(0,_offset)) m;
RETURN jsonb_build_object('profile',details,'messages',history,'total',total); END; $$;
REVOKE ALL ON FUNCTION public.inspect_member(uuid,uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.inspect_member(uuid,uuid,integer) TO anon, authenticated;
CREATE TABLE public.platformer_upgrades (user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE, speed integer NOT NULL DEFAULT 0, jump integer NOT NULL DEFAULT 0);
GRANT ALL ON public.platformer_upgrades TO service_role;
ALTER TABLE public.platformer_upgrades ENABLE ROW LEVEL SECURITY;
CREATE TABLE public.platformer_runs (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE, started_at timestamptz NOT NULL DEFAULT now(), collected integer[] NOT NULL DEFAULT '{}');
GRANT ALL ON public.platformer_runs TO service_role;
ALTER TABLE public.platformer_runs ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.platformer_open(_token uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; run uuid; upgrades jsonb;
BEGIN u := public.session_member(_token); IF (SELECT count(*) FROM public.platformer_runs WHERE user_id=u AND started_at>now()-interval '1 minute') >= 5 THEN RAISE EXCEPTION 'Wait a minute before starting another run'; END IF;
INSERT INTO public.platformer_upgrades(user_id) VALUES(u) ON CONFLICT DO NOTHING;
INSERT INTO public.platformer_runs(user_id) VALUES(u) RETURNING id INTO run;
SELECT jsonb_build_object('speed',speed,'jump',jump) INTO upgrades FROM public.platformer_upgrades WHERE user_id=u;
RETURN jsonb_build_object('run',run,'upgrades',upgrades); END; $$;
CREATE OR REPLACE FUNCTION public.platformer_collect(_token uuid, _run uuid, _coin integer) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; r public.platformer_runs; balance integer; recent integer;
BEGIN u := public.session_member(_token); SELECT * INTO r FROM public.platformer_runs WHERE id=_run AND user_id=u FOR UPDATE;
IF r.id IS NULL OR r.started_at<now()-interval '1 hour' THEN RAISE EXCEPTION 'Start a new run'; END IF;
IF _coin<0 OR _coin>=30 THEN RAISE EXCEPTION 'Invalid coin'; END IF;
IF _coin=ANY(r.collected) THEN SELECT coins INTO balance FROM public.profiles WHERE id=u; RETURN balance; END IF;
IF extract(epoch FROM now()-r.started_at) < (_coin / 3) * 2 THEN RAISE EXCEPTION 'Coin not reachable yet'; END IF;
PERFORM 1 FROM public.profiles WHERE id=u FOR UPDATE;
SELECT coalesce(sum(cardinality(collected)),0) INTO recent FROM public.platformer_runs WHERE user_id=u AND started_at>now()-interval '1 hour';
IF recent>=500 THEN RAISE EXCEPTION 'Hourly platformer reward limit reached'; END IF;
UPDATE public.platformer_runs SET collected=array_append(collected,_coin) WHERE id=_run;
UPDATE public.profiles SET coins=least(coins::bigint+1,2147483647)::integer WHERE id=u RETURNING coins INTO balance; RETURN balance; END; $$;
CREATE OR REPLACE FUNCTION public.platformer_buy(_token uuid, _kind text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; n integer; cost integer; balance integer;
BEGIN u := public.session_member(_token); IF _kind NOT IN ('speed','jump') THEN RAISE EXCEPTION 'Invalid upgrade'; END IF;
PERFORM 1 FROM public.profiles WHERE id=u FOR UPDATE;
INSERT INTO public.platformer_upgrades(user_id) VALUES(u) ON CONFLICT DO NOTHING;
SELECT CASE WHEN _kind='speed' THEN speed ELSE jump END INTO n FROM public.platformer_upgrades WHERE user_id=u FOR UPDATE;
IF n>=3 THEN RAISE EXCEPTION 'Upgrade is already maxed'; END IF;
cost := (n+1)*25;
UPDATE public.profiles SET coins=coins-cost WHERE id=u AND coins>=cost RETURNING coins INTO balance;
IF balance IS NULL THEN RAISE EXCEPTION 'Not enough coins'; END IF;
UPDATE public.platformer_upgrades SET speed=CASE WHEN _kind='speed' THEN speed+1 ELSE speed END,jump=CASE WHEN _kind='jump' THEN jump+1 ELSE jump END WHERE user_id=u;
RETURN jsonb_build_object('coins',balance,'level',n+1); END; $$;
REVOKE ALL ON FUNCTION public.platformer_open(uuid), public.platformer_collect(uuid,uuid,integer), public.platformer_buy(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platformer_open(uuid), public.platformer_collect(uuid,uuid,integer), public.platformer_buy(uuid,text) TO anon, authenticated;
REVOKE SELECT ON public.profiles FROM anon, authenticated;
GRANT SELECT(id,username,coins,xp,level,name_color,font_key,vip_tier,muted_until,banned,last_claim_at,streak,created_at) ON public.profiles TO anon, authenticated;