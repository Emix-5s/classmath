create or replace function public.mod_grant_coins(
  _actor uuid,
  _target uuid,
  _amount integer
)
returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  if not (public.has_role(_actor, 'mod') or public.has_role(_actor, 'admin')) then
    raise exception 'Not authorized: moderator role required';
  end if;
  if _amount <= 0 or _amount > 100000 then
    raise exception 'Amount must be between 1 and 100,000';
  end if;
  update public.profiles
  set coins = coins + _amount
  where id = _target;
  if not found then
    raise exception 'Target user not found';
  end if;
end; $$;

grant execute on function public.mod_grant_coins(uuid, uuid, integer) to authenticated;