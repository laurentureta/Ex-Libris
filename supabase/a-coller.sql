-- Signet : dernière étape, à coller une fois dans Supabase › SQL Editor › Run.
create or replace function public.signet_push(k text, d jsonb, base integer) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k); cur integer;
begin
  if d is null or jsonb_typeof(d) <> 'object' or octet_length(d::text) > 4000000 then raise exception 'bad_data'; end if;
  select rev into cur from signet_libraries where key_hash = h for update;
  if not found then
    insert into signet_libraries(key_hash, data, rev) values (h, d, 1) on conflict (key_hash) do nothing;
    if not found then
      select rev into cur from signet_libraries where key_hash = h;
      return jsonb_build_object('ok', false, 'rev', cur, 'data', (select data from signet_libraries where key_hash = h));
    end if;
    return jsonb_build_object('ok', true, 'rev', 1);
  end if;
  if cur <> coalesce(base, 0) then
    return jsonb_build_object('ok', false, 'rev', cur, 'data', (select data from signet_libraries where key_hash = h));
  end if;
  update signet_libraries set data = d, rev = cur + 1, updated_at = now() where key_hash = h;
  delete from signet_covers c where c.key_hash = h
    and not exists (select 1 from jsonb_array_elements(coalesce(d->'books', '[]'::jsonb)) x where (x->>'id')::bigint = c.book_id);
  return jsonb_build_object('ok', true, 'rev', cur + 1);
end $$;

create or replace function public.signet_friend_remove(k text, fid uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid;
begin
  select id into me from signet_profiles where key_hash = signet_h(k);
  if me is null then return false; end if;
  delete from signet_friends where (a = me and b = fid) or (a = fid and b = me);
  return true;
end $$;

create or replace function public.signet_challenge_leave(k text, cid uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid;
begin
  select id into me from signet_profiles where key_hash = signet_h(k);
  if me is null then return false; end if;
  delete from signet_members where challenge = cid and profile = me;
  delete from signet_challenges c where c.id = cid and not exists (select 1 from signet_members m where m.challenge = cid);
  return true;
end $$;

create or replace function public.signet_forget(k text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k);
begin
  delete from signet_shares where key_hash = h;
  delete from signet_push_subs where key_hash = h;
  delete from signet_profiles where key_hash = h;
  delete from signet_libraries where key_hash = h;
  return true;
end $$;

create or replace function public.signet_share_off(k text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from signet_shares where key_hash = signet_h(k);
  return true;
end $$;

create or replace function public.signet_push_sub(k text, endpoint text, tz text, hour integer, days text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k); t timestamp;
begin
  if endpoint is null or endpoint !~ '^https://' or length(endpoint) > 1000 then raise exception 'bad_endpoint'; end if;
  if hour < 0 or hour > 23 or days !~ '^[1-7]{0,7}$' then raise exception 'bad_time'; end if;
  begin t := now() at time zone tz; exception when others then raise exception 'bad_tz'; end;
  if (select count(*) from signet_push_subs where key_hash = h) >= 6 then
    delete from signet_push_subs where signet_push_subs.endpoint in (select s.endpoint from signet_push_subs s where s.key_hash = h order by created_at limit 1);
  end if;
  insert into signet_push_subs(endpoint, key_hash, tz, hour, days) values (signet_push_sub.endpoint, h, signet_push_sub.tz, signet_push_sub.hour, signet_push_sub.days)
    on conflict (endpoint) do update set key_hash = excluded.key_hash, tz = excluded.tz, hour = excluded.hour, days = excluded.days;
  return true;
end $$;

create or replace function public.signet_push_unsub(k text, endpoint text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from signet_push_subs where signet_push_subs.endpoint = signet_push_unsub.endpoint and key_hash = signet_h(k);
  return true;
end $$;

create or replace function public.signet_push_gone(e text) returns boolean
language sql security definer set search_path = public, pg_temp as $$
  delete from signet_push_subs where endpoint = e returning true
$$;

revoke all on function public.signet_push(text, jsonb, integer), public.signet_friend_remove(text, uuid), public.signet_challenge_leave(text, uuid),
  public.signet_forget(text), public.signet_share_off(text), public.signet_push_sub(text, text, text, integer, text), public.signet_push_unsub(text, text),
  public.signet_push_gone(text) from public, anon, authenticated;
grant execute on function public.signet_push(text, jsonb, integer), public.signet_friend_remove(text, uuid), public.signet_challenge_leave(text, uuid),
  public.signet_forget(text), public.signet_share_off(text), public.signet_push_sub(text, text, text, integer, text), public.signet_push_unsub(text, text) to anon, authenticated;
grant execute on function public.signet_push_gone(text) to service_role;
