alter table public.rooms add column if not exists locked boolean not null default false;

create or replace function public.staff_freeze_room(_actor uuid, _room uuid, _locked boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.rank_level(_actor) < 6 then raise exception 'TON 618 only'; end if;
  update public.rooms set locked = _locked where id = _room;
  insert into public.staff_log (actor_id, action, target_id, detail)
  values (_actor, case when _locked then 'freeze_room' else 'unfreeze_room' end, _room, null);
end $$;

create or replace function public.staff_grant_all(_actor uuid, _amount bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if public.rank_level(_actor) < 6 then raise exception 'TON 618 only'; end if;
  if _amount is null or _amount < 1 or _amount > 100000 then raise exception 'amount must be 1-100000 per person'; end if;
  update public.profiles set coins = least(coins + _amount, 2147483647);
  get diagnostics n = row_count;
  insert into public.staff_log (actor_id, action, detail) values (_actor, 'coin_rain', _amount::text);
  return n;
end $$;

create or replace function public.message_spam_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare last_at timestamptz; recent int; dup int; room_locked boolean;
begin
  if length(new.content) < 1 or length(new.content) > 500 then
    raise exception 'message must be 1-500 characters';
  end if;
  select locked into room_locked from public.rooms where id = new.room_id;
  if room_locked and public.rank_level(new.user_id) < 1 then
    raise exception 'this room is frozen by staff';
  end if;
  select max(created_at) into last_at from public.messages where user_id = new.user_id;
  if last_at is not null and last_at > now() - interval '1.5 seconds' then
    raise exception 'slow down a little';
  end if;
  select count(*) into recent from public.messages where user_id = new.user_id and created_at > now() - interval '15 seconds';
  if recent >= 6 then raise exception 'too many messages, take a breath'; end if;
  select count(*) into dup from public.messages where user_id = new.user_id and content = new.content and created_at > now() - interval '30 seconds';
  if dup > 0 then raise exception 'you already said that'; end if;
  return new;
end $$;