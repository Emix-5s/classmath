-- password auth (username only, no email)
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.user_credentials (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  password_hash text not null,
  created_at timestamptz not null default now()
);
grant all on public.user_credentials to service_role;
alter table public.user_credentials enable row level security;
-- no policies: only security-definer functions may touch credentials

create or replace function public.signup_user(_username text, _password text)
returns public.profiles
language plpgsql security definer set search_path to public, extensions
as $$
declare uname text; new_id uuid := gen_random_uuid(); p public.profiles;
begin
  uname := lower(regexp_replace(coalesce(_username,''), '[^a-zA-Z0-9_]', '', 'g'));
  if uname = '' then raise exception 'pick a username with letters or numbers'; end if;
  uname := left(uname, 20);
  if length(coalesce(_password,'')) < 4 then raise exception 'password must be at least 4 characters'; end if;
  if exists (select 1 from public.profiles where username = uname) then
    raise exception 'that username is taken'; end if;
  insert into public.profiles (id, username) values (new_id, uname) returning * into p;
  insert into public.user_roles (user_id, role) values (new_id, 'user') on conflict do nothing;
  insert into public.user_credentials (user_id, password_hash)
    values (new_id, crypt(_password, gen_salt('bf')));
  return p;
end; $$;

create or replace function public.login_user(_username text, _password text)
returns public.profiles
language plpgsql security definer set search_path to public, extensions
as $$
declare uname text; p public.profiles; h text;
begin
  uname := lower(regexp_replace(coalesce(_username,''), '[^a-zA-Z0-9_]', '', 'g'));
  select * into p from public.profiles where username = uname;
  if p.id is null then raise exception 'wrong username or password'; end if;
  select password_hash into h from public.user_credentials where user_id = p.id;
  if h is null or h <> crypt(coalesce(_password,''), h) then
    raise exception 'wrong username or password'; end if;
  if p.banned then raise exception 'this account is banned'; end if;
  return p;
end; $$;

-- VIP perks
create or replace function public.vip_mult(_tier text)
returns numeric language sql immutable set search_path to public as $$
  select case _tier when 'VIP+' then 1.5 when 'VIP' then 1.25 else 1.0 end;
$$;

create or replace function public.vip_max_bet(_tier text)
returns int language sql immutable set search_path to public as $$
  select case _tier when 'VIP+' then 5000 when 'VIP' then 1500 else 500 end;
$$;

-- shared settlement: deducts bet, pays bet*_payout (vip-boosted on wins), grants xp
create or replace function public.game_settle(_user uuid, _bet int, _payout numeric, _won boolean)
returns int language plpgsql security definer set search_path to public
as $$
declare p record; gain int; bal int;
begin
  if _user is null then raise exception 'sign in first'; end if;
  select * into p from public.profiles where id = _user for update;
  if p.id is null then raise exception 'profile not found'; end if;
  if _bet < 10 then raise exception 'minimum bet is 10'; end if;
  if _bet > public.vip_max_bet(p.vip_tier) then
    raise exception 'your max bet is % — upgrade VIP to raise it', public.vip_max_bet(p.vip_tier); end if;
  if p.coins < _bet then raise exception 'not enough coins'; end if;
  gain := floor(_bet * (case when _won then _payout * public.vip_mult(p.vip_tier) else _payout end))::int - _bet;
  update public.profiles
    set coins = coins + gain, xp = xp + 10, level = 1 + ((xp + 10) / 500)
    where id = _user returning coins into bal;
  if _won then
    insert into public.user_stats (user_id, flips_won) values (_user,1)
      on conflict (user_id) do update set flips_won = public.user_stats.flips_won + 1;
    perform public.bump_progress(_user,'high-roller',1);
  end if;
  return bal;
end; $$;

-- dice: pick 1-6, correct pays 5x
create or replace function public.play_dice(_user uuid, bet int, pick int)
returns jsonb language plpgsql security definer set search_path to public
as $$
declare roll int; won boolean; bal int;
begin
  if pick < 1 or pick > 6 then raise exception 'pick a number from 1 to 6'; end if;
  roll := 1 + floor(random()*6)::int;
  won := roll = pick;
  bal := public.game_settle(_user, bet, case when won then 5 else 0 end, won);
  return jsonb_build_object('roll',roll,'won',won,'coins',bal);
end; $$;

-- slots: three reels, triple pays 12x, pair pays 2x
create or replace function public.play_slots(_user uuid, bet int)
returns jsonb language plpgsql security definer set search_path to public
as $$
declare sym text[] := array['◈','★','☾','⬢','✦']; a text; b text; c text;
        payout numeric := 0; won boolean := false; bal int;
begin
  a := sym[1 + floor(random()*5)::int];
  b := sym[1 + floor(random()*5)::int];
  c := sym[1 + floor(random()*5)::int];
  if a = b and b = c then payout := 12; won := true;
  elsif a = b or b = c or a = c then payout := 2; won := true;
  end if;
  bal := public.game_settle(_user, bet, payout, won);
  if a = b and b = c then perform public.bump_progress(_user,'jackpot',1); end if;
  return jsonb_build_object('reels',array[a,b,c],'won',won,'payout',payout,'coins',bal);
end; $$;

-- rock paper scissors: win pays 2x, draw refunds
create or replace function public.play_rps(_user uuid, bet int, pick text)
returns jsonb language plpgsql security definer set search_path to public
as $$
declare opts text[] := array['rock','paper','scissors']; house text; res text;
        payout numeric; won boolean; bal int;
begin
  if pick not in ('rock','paper','scissors') then raise exception 'invalid pick'; end if;
  house := opts[1 + floor(random()*3)::int];
  if house = pick then res := 'draw';
  elsif (pick,house) in (('rock','scissors'),('paper','rock'),('scissors','paper')) then res := 'win';
  else res := 'lose'; end if;
  payout := case res when 'win' then 2 when 'draw' then 1 else 0 end;
  won := res = 'win';
  bal := public.game_settle(_user, bet, payout, won);
  return jsonb_build_object('house',house,'result',res,'coins',bal);
end; $$;

-- hi-lo: call higher or lower on the next card, win pays 2x, tie refunds
create or replace function public.play_hilo(_user uuid, bet int, call text)
returns jsonb language plpgsql security definer set search_path to public
as $$
declare a int; b int; res text; payout numeric; won boolean; bal int;
begin
  if call not in ('higher','lower') then raise exception 'invalid call'; end if;
  a := 2 + floor(random()*13)::int;
  b := 2 + floor(random()*13)::int;
  if b = a then res := 'push';
  elsif (b > a and call = 'higher') or (b < a and call = 'lower') then res := 'win';
  else res := 'lose'; end if;
  payout := case res when 'win' then 2 when 'push' then 1 else 0 end;
  won := res = 'win';
  bal := public.game_settle(_user, bet, payout, won);
  return jsonb_build_object('card',a,'next',b,'result',res,'coins',bal);
end; $$;

-- promo codes
create table if not exists public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  reward int not null,
  note text not null default '',
  active boolean not null default true
);
grant all on public.promo_codes to service_role;
alter table public.promo_codes enable row level security;

create table if not exists public.code_redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  code_id uuid not null references public.promo_codes(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, code_id)
);
grant all on public.code_redemptions to service_role;
alter table public.code_redemptions enable row level security;

insert into public.promo_codes (code, reward, note) values
  ('welcome100', 100, 'starter boost'),
  ('nexusarcade', 500, 'arcade launch'),
  ('luckyseven', 777, 'lucky drop'),
  ('chatterbox', 300, 'community code'),
  ('neonnights', 1000, 'weekend code'),
  ('cxyilo-vip', 2500, 'founder code')
on conflict (code) do nothing;

create or replace function public.redeem_code(_user uuid, _code text)
returns jsonb language plpgsql security definer set search_path to public
as $$
declare c record;
begin
  if _user is null then raise exception 'sign in first'; end if;
  select * into c from public.promo_codes where code = lower(trim(_code)) and active;
  if c.id is null then raise exception 'that code is not valid'; end if;
  if exists (select 1 from public.code_redemptions where user_id = _user and code_id = c.id) then
    raise exception 'you already used that code'; end if;
  insert into public.code_redemptions (user_id, code_id) values (_user, c.id);
  update public.profiles set coins = coins + c.reward where id = _user;
  perform public.bump_progress(_user,'code-hunter',1);
  return jsonb_build_object('reward', c.reward, 'note', c.note);
end; $$;

-- new mod code
create or replace function public.claim_mod(_user uuid, _code text)
returns void language plpgsql security definer set search_path to public
as $$
begin
  if _code is distinct from 'cxyilo' then raise exception 'wrong mod code'; end if;
  insert into public.user_roles (user_id, role) values (_user, 'mod') on conflict do nothing;
end; $$;

-- new achievements
insert into public.achievements (key, name, description, goal, reward, sort_order) values
  ('jackpot', 'Jackpot', 'Hit three matching slot symbols', 1, 1000, 20),
  ('code-hunter', 'Code Hunter', 'Redeem 3 promo codes', 3, 400, 21)
on conflict (key) do nothing;
