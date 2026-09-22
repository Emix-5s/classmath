-- Switch the clubhouse to username-only guest identities (no sign-in).

-- 1. Guest-friendly access policies
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('profiles','messages','rooms','shop_items','inventory','achievements','user_achievements','user_stats','user_roles')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

grant select, insert, update on public.profiles to anon, authenticated;
grant select, insert on public.messages to anon, authenticated;
grant select on public.rooms, public.shop_items, public.achievements, public.inventory, public.user_achievements, public.user_stats, public.user_roles to anon, authenticated;

create policy "guests read profiles" on public.profiles for select to anon, authenticated using (true);
create policy "guests create profiles" on public.profiles for insert to anon, authenticated with check (true);
create policy "guests update profiles" on public.profiles for update to anon, authenticated using (true) with check (true);

create policy "guests read messages" on public.messages for select to anon, authenticated using (true);
create policy "guests post messages" on public.messages for insert to anon, authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = messages.user_id
        and p.banned = false
        and (p.muted_until is null or p.muted_until < now())
    )
  );

create policy "read rooms" on public.rooms for select to anon, authenticated using (true);
create policy "read shop" on public.shop_items for select to anon, authenticated using (true);
create policy "read achievements" on public.achievements for select to anon, authenticated using (true);
create policy "read inventory" on public.inventory for select to anon, authenticated using (true);
create policy "read user achievements" on public.user_achievements for select to anon, authenticated using (true);
create policy "read user stats" on public.user_stats for select to anon, authenticated using (true);
create policy "read roles" on public.user_roles for select to anon, authenticated using (true);

-- 2. Guest creation / login by username
create or replace function public.create_guest(_username text)
returns public.profiles
language plpgsql security definer set search_path to 'public'
as $$
declare base text; final text; n int := 0; new_id uuid := gen_random_uuid(); p public.profiles;
begin
  base := lower(regexp_replace(coalesce(_username,''), '[^a-zA-Z0-9_]', '', 'g'));
  if base = '' then raise exception 'pick a handle with letters or numbers'; end if;
  base := left(base, 20);
  final := base;
  while exists (select 1 from public.profiles where username = final) loop
    n := n + 1; final := left(base, 18) || n::text;
  end loop;
  insert into public.profiles (id, username) values (new_id, final) returning * into p;
  insert into public.user_roles (user_id, role) values (new_id, 'user') on conflict do nothing;
  return p;
end; $$;

create or replace function public.claim_mod(_user uuid, _code text)
returns void
language plpgsql security definer set search_path to 'public'
as $$
begin
  if _code is distinct from 'nexus-mod' then raise exception 'wrong mod code'; end if;
  insert into public.user_roles (user_id, role) values (_user, 'mod') on conflict do nothing;
end; $$;

-- 3. Rewrite gameplay functions to take the guest id explicitly
drop function if exists public.play_coin_flip(integer, text);
create function public.play_coin_flip(_user uuid, bet integer, guess text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare uid uuid := _user; bal int; flip text; won boolean;
begin
  if uid is null then raise exception 'pick a handle first'; end if;
  if bet < 10 or bet > 500 then raise exception 'bet must be between 10 and 500'; end if;
  select coins into bal from public.profiles where id = uid for update;
  if bal is null then raise exception 'profile not found'; end if;
  if bal < bet then raise exception 'not enough coins'; end if;
  flip := case when random() < 0.5 then 'heads' else 'tails' end;
  won := (flip = guess);
  update public.profiles set coins = coins + (case when won then bet else -bet end),
    xp = xp + 10, level = 1 + ((xp + 10) / 500) where id = uid returning coins into bal;
  if won then
    insert into public.user_stats (user_id, flips_won) values (uid,1)
      on conflict (user_id) do update set flips_won = public.user_stats.flips_won + 1;
    perform public.bump_progress(uid,'high-roller',1);
  end if;
  return jsonb_build_object('flip',flip,'won',won,'coins',bal);
end; $$;

drop function if exists public.buy_item(uuid);
create function public.buy_item(_user uuid, _item uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare uid uuid := _user; it record; bal int;
begin
  if uid is null then raise exception 'pick a handle first'; end if;
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
  perform public.bump_progress(uid,'collector',1);
  return jsonb_build_object('coins',bal);
end; $$;

drop function if exists public.claim_daily();
create function public.claim_daily(_user uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare uid uuid := _user; p record; reward int; new_streak int;
begin
  if uid is null then raise exception 'pick a handle first'; end if;
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

drop function if exists public.claim_achievement(uuid);
create function public.claim_achievement(_user uuid, _achievement uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare uid uuid := _user; a record; ua record;
begin
  if uid is null then raise exception 'pick a handle first'; end if;
  select * into a from public.achievements where id = _achievement;
  select * into ua from public.user_achievements where user_id = uid and achievement_id = _achievement;
  if ua is null or ua.claimed or ua.progress < a.goal then raise exception 'not claimable'; end if;
  update public.user_achievements set claimed = true where id = ua.id;
  update public.profiles set coins = coins + a.reward where id = uid;
  return jsonb_build_object('reward',a.reward);
end; $$;

drop function if exists public.mod_action(uuid, text, integer);
create function public.mod_action(_actor uuid, _target uuid, _action text, _minutes integer default 10)
returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  if not (public.has_role(_actor,'mod') or public.has_role(_actor,'admin')) then
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

drop function if exists public.delete_message(uuid);
create function public.delete_message(_actor uuid, _message uuid)
returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  if not (public.has_role(_actor,'mod') or public.has_role(_actor,'admin')) then
    raise exception 'not a moderator'; end if;
  update public.messages set deleted = true, content = '[removed by a moderator]' where id = _message;
end; $$;

grant execute on function public.create_guest(text), public.claim_mod(uuid, text),
  public.play_coin_flip(uuid, integer, text), public.buy_item(uuid, uuid),
  public.claim_daily(uuid), public.claim_achievement(uuid, uuid),
  public.mod_action(uuid, uuid, text, integer), public.delete_message(uuid, uuid)
  to anon, authenticated;
