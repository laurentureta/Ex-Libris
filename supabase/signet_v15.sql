-- Signet 1.5 : bibliothèque partageable par lien, rappels de lecture (Web Push).

create table if not exists public.signet_shares (
  slug text primary key,
  key_hash text not null unique,
  snap jsonb not null default '{}'::jsonb,
  views integer not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists public.signet_push_subs (
  endpoint text primary key,
  key_hash text not null,
  tz text not null default 'Europe/Paris',
  hour integer not null default 21 check (hour between 0 and 23),
  days text not null default '1234567',
  last_sent date,
  created_at timestamptz not null default now()
);
create index if not exists signet_push_subs_key on public.signet_push_subs(key_hash);
create table if not exists public.signet_config (
  k text primary key,
  v text not null
);
alter table public.signet_shares enable row level security;
alter table public.signet_push_subs enable row level security;
alter table public.signet_config enable row level security;
revoke all on public.signet_shares, public.signet_push_subs, public.signet_config from anon, authenticated;
insert into public.signet_config(k, v) values ('cron', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')) on conflict (k) do nothing;

create or replace function public.signet_share_put(k text, snap jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k); s text;
begin
  if snap is null or jsonb_typeof(snap) <> 'object' or octet_length(snap::text) > 900000 then raise exception 'bad_snap'; end if;
  select slug into s from signet_shares where key_hash = h;
  if found then
    update signet_shares set snap = signet_share_put.snap, updated_at = now() where key_hash = h;
    return jsonb_build_object('slug', s);
  end if;
  loop
    s := lower(signet_code(8));
    exit when not exists (select 1 from signet_shares where slug = s);
  end loop;
  insert into signet_shares(slug, key_hash, snap) values (s, h, signet_share_put.snap);
  return jsonb_build_object('slug', s);
end $$;

create or replace function public.signet_share_get(slug text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record;
begin
  update signet_shares set views = views + 1 where signet_shares.slug = lower(btrim(signet_share_get.slug)) returning snap, updated_at, views into r;
  if not found then return null; end if;
  return jsonb_build_object('snap', r.snap, 'at', r.updated_at, 'views', r.views);
end $$;

create or replace function public.signet_share_off(k text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from signet_shares where key_hash = signet_h(k);
  return true;
end $$;

create or replace function public.signet_vapid() returns text
language sql security definer set search_path = public, pg_temp as $$
  select v from signet_config where k = 'vapid_pub'
$$;

create or replace function public.signet_push_sub(k text, endpoint text, tz text, hour integer, days text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k); t timestamp;
begin
  if endpoint is null or endpoint !~ '^https://' or length(endpoint) > 1000 then raise exception 'bad_endpoint'; end if;
  if hour < 0 or hour > 23 or days !~ '^[1-7]{0,7}$' then raise exception 'bad_time'; end if;
  begin t := now() at time zone tz; exception when others then raise exception 'bad_tz'; end;
  if (select count(*) from signet_push_subs where key_hash = h) >= 6 then
    delete from signet_push_subs where endpoint in (select s.endpoint from signet_push_subs s where s.key_hash = h order by created_at limit 1);
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

-- réservées au serveur (fonction Edge avec la clé de service)
create or replace function public.signet_push_take() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb;
begin
  with due as (
    select endpoint, (now() at time zone tz)::date as d from signet_push_subs
    where hour = extract(hour from now() at time zone tz)::integer
      and position(extract(isodow from now() at time zone tz)::integer::text in days) > 0
      and (last_sent is null or last_sent < (now() at time zone tz)::date)
    limit 500 for update skip locked
  ), upd as (
    update signet_push_subs s set last_sent = due.d from due where s.endpoint = due.endpoint returning s.endpoint
  )
  select coalesce(jsonb_agg(endpoint), '[]'::jsonb) into r from upd;
  return r;
end $$;

create or replace function public.signet_push_gone(e text) returns boolean
language sql security definer set search_path = public, pg_temp as $$
  delete from signet_push_subs where endpoint = e returning true
$$;

create or replace function public.signet_config_get() returns jsonb
language sql security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from signet_config
$$;

create or replace function public.signet_config_set(k text, v text) returns boolean
language sql security definer set search_path = public, pg_temp as $$
  insert into signet_config(k, v) values (k, v) on conflict (k) do nothing returning true
$$;

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

revoke all on function public.signet_share_put(text, jsonb), public.signet_share_get(text), public.signet_share_off(text), public.signet_vapid(),
  public.signet_push_sub(text, text, text, integer, text), public.signet_push_unsub(text, text), public.signet_push_take(), public.signet_push_gone(text),
  public.signet_config_get(), public.signet_config_set(text, text) from public, anon, authenticated;
grant execute on function public.signet_share_put(text, jsonb), public.signet_share_get(text), public.signet_share_off(text), public.signet_vapid(),
  public.signet_push_sub(text, text, text, integer, text), public.signet_push_unsub(text, text) to anon, authenticated;
grant execute on function public.signet_push_take(), public.signet_push_gone(text), public.signet_config_get(), public.signet_config_set(text, text) to service_role;

-- on a lu aujourd'hui : pas de rappel ce jour-là
create or replace function public.signet_push_seen(k text, d date) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if d is null or d < current_date - 2 or d > current_date + 2 then return false; end if;
  update signet_push_subs set last_sent = greatest(coalesce(last_sent, d), d) where key_hash = signet_h(k);
  return true;
end $$;
revoke all on function public.signet_push_seen(text, date) from public, anon, authenticated;
grant execute on function public.signet_push_seen(text, date) to anon, authenticated;

-- planification (pg_cron + pg_net) : toutes les 15 minutes, la fonction Edge signet-remind envoie les rappels dus
-- select cron.schedule('signet-remind', '*/15 * * * *', $$ select net.http_post(url := 'https://<projet>.supabase.co/functions/v1/signet-remind',
--   headers := jsonb_build_object('Content-Type', 'application/json', 'x-signet-cron', (select v from public.signet_config where k = 'cron')), body := '{}'::jsonb) $$);
