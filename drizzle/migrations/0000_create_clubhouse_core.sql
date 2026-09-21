-- ROLES
create type public.app_role as enum ('admin','mod','user');

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);
grant select on public.user_roles to authenticated;
grant all on public.user_roles to service_role;
alter table public.user_roles enable row level security;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role)
$$;

create policy "roles readable by authenticated" on public.user_roles for select to authenticated using (true);
create policy "admins manage roles" on public.user_roles for all to authenticated
  using (public.has_role(auth.uid(),'admin')) with check (public.has_role(auth.uid(),'admin'));

-- PROFILES
create table public.profiles (
  id uuid primary key,
  username text not null unique,
  coins integer not null default 500,
  xp integer not null default 0,
  level integer not null default 1,
  name_color text not null default '#ffffff',
  font_key text not null default 'body',
  vip_tier text,
  muted_until timestamptz,
  banned boolean not null default false,
  last_claim_at timestamptz,
  streak integer not null default 0,
  created_at timestamptz not null default now()
);
grant select, insert, update on public.profiles to authenticated;
grant select on public.profiles to anon;
grant all on public.profiles to service_role;
alter table public.profiles enable row level security;
create policy "profiles are public" on public.profiles for select using (true);
create policy "users update own profile" on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);
create policy "mods update any profile" on public.profiles for update to authenticated
  using (public.has_role(auth.uid(),'mod') or public.has_role(auth.uid(),'admin'))
  with check (public.has_role(auth.uid(),'mod') or public.has_role(auth.uid(),'admin'));

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare base text; final text; n int := 0;
begin
  base := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1),'player'), '[^a-zA-Z0-9_]','','g'));
  if base = '' then base := 'player'; end if;
  final := base;
  while exists (select 1 from public.profiles where username = final) loop
    n := n + 1; final := base || n::text;
  end loop;
  insert into public.profiles (id, username) values (new.id, final);
  insert into public.user_roles (user_id, role) values (new.id, 'user') on conflict do nothing;
  return new;
end; $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ROOMS
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  mod_only boolean not null default false,
  sort_order integer not null default 0
);
grant select on public.rooms to anon, authenticated;
grant all on public.rooms to service_role;
alter table public.rooms enable row level security;
create policy "rooms are public" on public.rooms for select using (true);

insert into public.rooms (slug,name,mod_only,sort_order) values
  ('general','general',false,1),
  ('arcade','arcade',false,2),
  ('trading','trading',false,3),
  ('mod-desk','mod-desk',true,4);

-- MESSAGES
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null,
  content text not null,
  deleted boolean not null default false,
  created_at timestamptz not null default now()
);
create index messages_room_created_idx on public.messages (room_id, created_at desc);
grant select, insert, update on public.messages to authenticated;
grant all on public.messages to service_role;
alter table public.messages enable row level security;
create policy "messages readable by authenticated" on public.messages for select to authenticated using (true);
create policy "users send own messages" on public.messages for insert to authenticated
  with check (auth.uid() = user_id and not exists (
    select 1 from public.profiles p where p.id = auth.uid() and (p.banned or (p.muted_until is not null and p.muted_until > now()))
  ));
create policy "mods moderate messages" on public.messages for update to authenticated
  using (public.has_role(auth.uid(),'mod') or public.has_role(auth.uid(),'admin'))
  with check (public.has_role(auth.uid(),'mod') or public.has_role(auth.uid(),'admin'));
alter publication supabase_realtime add table public.messages;

-- SHOP
create table public.shop_items (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  kind text not null check (kind in ('skin','font','vip')),
  rarity text not null check (rarity in ('common','rare','epic','mythic')),
  price integer not null,
  value text not null,
  sort_order integer not null default 0
);
grant select on public.shop_items to anon, authenticated;
grant all on public.shop_items to service_role;
alter table public.shop_items enable row level security;
create policy "shop is public" on public.shop_items for select using (true);

insert into public.shop_items (key,name,kind,rarity,price,value,sort_order) values
  ('neon-script','Neon Script','font','rare',800,'display',1),
  ('arc-reactor','Arc Reactor','skin','mythic',2400,'#22d3ee',2),
  ('mono-type','Mono Type','font','common',250,'mono',3),
  ('vip-tier','VIP Tier','vip','epic',1500,'VIP',4),
  ('coin-gold','Coin Gold','skin','rare',900,'#fbbf24',5),
  ('rose-pulse','Rose Pulse','skin','epic',1400,'#f472b6',6),
  ('mint-glow','Mint Glow','skin','common',300,'#34d399',7),
  ('vip-elite','VIP Elite','vip','mythic',5000,'VIP+',8);

create table public.inventory (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  item_id uuid not null references public.shop_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, item_id)
);
grant select on public.inventory to authenticated;
grant all on public.inventory to service_role;
alter table public.inventory enable row level security;
create policy "users read own inventory" on public.inventory for select to authenticated using (auth.uid() = user_id);

-- ACHIEVEMENTS
create table public.achievements (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text not null,
  reward integer not null,
  goal integer not null default 1,
  sort_order integer not null default 0
);
grant select on public.achievements to anon, authenticated;
grant all on public.achievements to service_role;
alter table public.achievements enable row level security;
create policy "achievements are public" on public.achievements for select using (true);

insert into public.achievements (key,name,description,reward,goal,sort_order) values
  ('first-word','First Word','Send your first message',100,1,1),
  ('chatterbox','Chatterbox','Send 50 messages',400,50,2),
  ('high-roller','High Roller','Win 5 coin flips',500,5,3),
  ('collector','Collector','Own 3 shop items',600,3,4),
  ('streak-7','7-day streak','Claim rewards 7 days in a row',350,7,5);

create table public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  progress integer not null default 0,
  claimed boolean not null default false,
  unique (user_id, achievement_id)
);
grant select on public.user_achievements to authenticated;
grant all on public.user_achievements to service_role;
alter table public.user_achievements enable row level security;
create policy "users read own achievements" on public.user_achievements for select to authenticated using (auth.uid() = user_id);

-- STATS
create table public.user_stats (
  user_id uuid primary key,
  messages_sent integer not null default 0,
  flips_won integer not null default 0
);
grant select on public.user_stats to authenticated;
grant all on public.user_stats to service_role;
alter table public.user_stats enable row level security;
create policy "users read own stats" on public.user_stats for select to authenticated using (auth.uid() = user_id);

-- helpers
create or replace function public.bump_progress(_user uuid, _key text, _amount int)
returns void language plpgsql security definer set search_path = public as $$
declare a record;
begin
  select * into a from public.achievements where key = _key;
  if a is null then return; end if;
  insert into public.user_achievements (user_id, achievement_id, progress)
  values (_user, a.id, least(_amount, a.goal))
  on conflict (user_id, achievement_id)
  do update set progress = least(public.user_achievements.progress + _amount, a.goal);
end; $$;

create or replace function public.after_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare total int;
begin
  insert into public.user_stats (user_id, messages_sent) values (new.user_id, 1)
  on conflict (user_id) do update set messages_sent = public.user_stats.messages_sent + 1
  returning messages_sent into total;
  perform public.bump_progress(new.user_id,'first-word',1);
  perform public.bump_progress(new.user_id,'chatterbox',1);
  return new;
end; $$;
create trigger messages_after_insert after insert on public.messages
  for each row execute function public.after_message();

-- RPCs
create or replace function public.play_coin_flip(bet integer, guess text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); bal int; flip text; won boolean; wins int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if bet < 10 or bet > 500 then raise exception 'bet must be between 10 and 500'; end if;
  select coins into bal from public.profiles where id = uid for update;
  if bal < bet then raise exception 'not enough coins'; end if;
  flip := case when random() < 0.5 then 'heads' else 'tails' end;
  won := (flip = guess);
  update public.profiles set coins = coins + (case when won then bet else -bet end),
    xp = xp + 10, level = 1 + ((xp + 10) / 500) where id = uid returning coins into bal;
  if won then
    insert into public.user_stats (user_id, flips_won) values (uid,1)
      on conflict (user_id) do update set flips_won = public.user_stats.flips_won + 1
      returning flips_won into wins;
    perform public.bump_progress(uid,'high-roller',1);
  end if;
  return jsonb_build_object('flip',flip,'won',won,'coins',bal);
end; $$;
grant execute on function public.play_coin_flip(integer,text) to authenticated;

create or replace function public.buy_item(_item uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); it record; bal int; owned int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into it from public.shop_items where id = _item;
  if it is null then raise exception 'item not found'; end if;
  if exists (select 1 from public.inventory where user_id = uid and item_id = _item) then
    raise exception 'already owned'; end if;
  select coins into bal from public.profiles where id = uid for update;
  if bal < it.price then raise exception 'not enough coins'; end if;
  update public.profiles set coins = coins - it.price,
    vip_tier = case when it.kind = 'vip' then it.value else vip_tier end,
    name_color = case when it.kind = 'skin' then it.value else name_color end,
    font_key = case when it.kind = 'font' then it.value else font_key end
  where id = uid returning coins into bal;
  insert into public.inventory (user_id, item_id) values (uid, _item);
  select count(*) into owned from public.inventory where user_id = uid;
  perform public.bump_progress(uid,'collector',1);
  return jsonb_build_object('coins',bal);
end; $$;
grant execute on function public.buy_item(uuid) to authenticated;

create or replace function public.claim_daily()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); p record; reward int; new_streak int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into p from public.profiles where id = uid for update;
  if p.last_claim_at is not null and p.last_claim_at > now() - interval '20 hours' then
    raise exception 'already claimed today'; end if;
  new_streak := case when p.last_claim_at is not null and p.last_claim_at > now() - interval '48 hours'
    then p.streak + 1 else 1 end;
  reward := 100 + (least(new_streak,7) * 50);
  update public.profiles set coins = coins + reward, streak = new_streak, last_claim_at = now() where id = uid;
  perform public.bump_progress(uid,'streak-7',1);
  return jsonb_build_object('reward',reward,'streak',new_streak);
end; $$;
grant execute on function public.claim_daily() to authenticated;

create or replace function public.claim_achievement(_achievement uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a record; ua record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into a from public.achievements where id = _achievement;
  select * into ua from public.user_achievements where user_id = uid and achievement_id = _achievement;
  if ua is null or ua.claimed or ua.progress < a.goal then raise exception 'not claimable'; end if;
  update public.user_achievements set claimed = true where id = ua.id;
  update public.profiles set coins = coins + a.reward where id = uid;
  return jsonb_build_object('reward',a.reward);
end; $$;
grant execute on function public.claim_achievement(uuid) to authenticated;

create or replace function public.mod_action(_target uuid, _action text, _minutes integer default 10)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if not (public.has_role(uid,'mod') or public.has_role(uid,'admin')) then
    raise exception 'not a moderator'; end if;
  if _action = 'mute' then
    update public.profiles set muted_until = now() + make_interval(mins => _minutes) where id = _target;
  elsif _action = 'unmute' then
    update public.profiles set muted_until = null where id = _target;
  elsif _action = 'ban' then
    update public.profiles set banned = true where id = _target;
  elsif _action = 'unban' then
    update public.profiles set banned = false where id = _target;
  else raise exception 'unknown action'; end if;
end; $$;
grant execute on function public.mod_action(uuid,text,integer) to authenticated;

create or replace function public.delete_message(_message uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.has_role(auth.uid(),'mod') or public.has_role(auth.uid(),'admin')) then
    raise exception 'not a moderator'; end if;
  update public.messages set deleted = true, content = '[removed by a moderator]' where id = _message;
end; $$;
grant execute on function public.delete_message(uuid) to authenticated;