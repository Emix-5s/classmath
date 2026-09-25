create or replace function public.message_spam_guard()
returns trigger language plpgsql security definer set search_path to public as $$
begin
  if length(trim(new.content)) = 0 or length(new.content) > 500 then
    raise exception 'messages must be 1-500 characters'; end if;
  if exists (select 1 from public.messages where user_id = new.user_id and created_at > now() - interval '1.5 seconds') then
    raise exception 'slow down — wait a moment between messages'; end if;
  if (select count(*) from public.messages where user_id = new.user_id and created_at > now() - interval '15 seconds') >= 6 then
    raise exception 'spam detected — wait a few seconds'; end if;
  if exists (select 1 from public.messages where user_id = new.user_id and lower(content) = lower(new.content) and created_at > now() - interval '30 seconds') then
    raise exception 'no repeating the same message'; end if;
  return new;
end; $$;
drop trigger if exists messages_spam_guard on public.messages;
create trigger messages_spam_guard before insert on public.messages
for each row execute function public.message_spam_guard();

create or replace function public.equip_item(_user uuid, _item uuid)
returns void language plpgsql security definer set search_path to public as $$
declare it record;
begin
  if _item is null then
    update public.profiles set name_color = '#ffffff' where id = _user; return; end if;
  select * into it from public.shop_items where id = _item;
  if it is null then raise exception 'item not found'; end if;
  if not exists (select 1 from public.inventory where user_id = _user and item_id = _item) then
    raise exception 'you do not own that'; end if;
  update public.profiles set
    name_color = case when it.kind = 'skin' then it.value else name_color end,
    font_key = case when it.kind = 'font' then it.value else font_key end,
    vip_tier = case when it.kind = 'vip' then it.value else vip_tier end
  where id = _user;
end; $$;

create or replace function public.reset_font(_user uuid)
returns void language sql security definer set search_path to public as $$
  update public.profiles set font_key = 'body' where id = _user;
$$;

create or replace function public.delete_own_message(_user uuid, _message uuid)
returns void language plpgsql security definer set search_path to public as $$
begin
  update public.messages set deleted = true, content = '[message deleted]'
  where id = _message and user_id = _user and not deleted;
  if not found then raise exception 'you can only delete your own messages'; end if;
end; $$;