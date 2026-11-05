-- Signet : serveur de sauvegarde en ligne et de club de lecture (Supabase / PostgreSQL).
-- Les tables ne sont lisibles qu'à travers les fonctions ci-dessous (RLS active, aucune politique).
-- Le compte est une clé secrète gardée sur l'appareil : le serveur n'en stocke qu'une empreinte SHA-256.

create table if not exists public.signet_libraries (
  key_hash text primary key,
  data jsonb not null default '{}'::jsonb,
  rev integer not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists public.signet_covers (
  key_hash text not null references public.signet_libraries(key_hash) on delete cascade,
  book_id bigint not null,
  img text not null,
  updated_at timestamptz not null default now(),
  primary key (key_hash, book_id)
);
create table if not exists public.signet_profiles (
  id uuid primary key default gen_random_uuid(),
  key_hash text not null unique,
  code text not null unique,
  name text not null,
  seal jsonb,
  snap jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.signet_friends (
  a uuid not null references public.signet_profiles(id) on delete cascade,
  b uuid not null references public.signet_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a, b)
);
create index if not exists signet_friends_b on public.signet_friends(b);
create table if not exists public.signet_challenges (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  kind text not null check (kind in ('books', 'pages')),
  target integer not null check (target > 0 and target < 1000000),
  starts date not null,
  ends date not null,
  owner uuid references public.signet_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.signet_members (
  challenge uuid not null references public.signet_challenges(id) on delete cascade,
  profile uuid not null references public.signet_profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (challenge, profile)
);
create index if not exists signet_members_profile on public.signet_members(profile);

alter table public.signet_libraries enable row level security;
alter table public.signet_covers enable row level security;
alter table public.signet_profiles enable row level security;
alter table public.signet_friends enable row level security;
alter table public.signet_challenges enable row level security;
alter table public.signet_members enable row level security;
revoke all on public.signet_libraries, public.signet_covers, public.signet_profiles, public.signet_friends, public.signet_challenges, public.signet_members from anon, authenticated;

create or replace function public.signet_h(k text) returns text
language plpgsql immutable set search_path = public, pg_temp as $$
begin
  if k is null or length(k) < 24 or length(k) > 80 then raise exception 'bad_key'; end if;
  return encode(sha256(convert_to(k, 'UTF8')), 'hex');
end $$;

create or replace function public.signet_code(n integer) returns text
language plpgsql volatile set search_path = public, pg_temp as $$
declare a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; s text := ''; i integer;
begin
  for i in 1..n loop s := s || substr(a, 1 + floor(random() * length(a))::integer, 1); end loop;
  return s;
end $$;

create or replace function public.signet_pull(k text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k); r record;
begin
  select data, rev into r from signet_libraries where key_hash = h;
  if not found then return jsonb_build_object('rev', 0, 'data', null, 'covers', '[]'::jsonb); end if;
  return jsonb_build_object('rev', r.rev, 'data', r.data,
    'covers', coalesce((select jsonb_agg(book_id) from signet_covers where key_hash = h), '[]'::jsonb));
end $$;

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

create or replace function public.signet_cover_put(k text, id bigint, img text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k);
begin
  if img is null or length(img) > 400000 or img not like 'data:image/%' then raise exception 'bad_cover'; end if;
  if not exists (select 1 from signet_libraries where key_hash = h) then raise exception 'no_library'; end if;
  if (select count(*) from signet_covers where key_hash = h) >= 3000 then raise exception 'too_many'; end if;
  insert into signet_covers(key_hash, book_id, img) values (h, id, img)
    on conflict (key_hash, book_id) do update set img = excluded.img, updated_at = now();
  return true;
end $$;

create or replace function public.signet_covers_get(k text, ids bigint[]) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k);
begin
  return coalesce((select jsonb_object_agg(book_id::text, img) from
    (select book_id, img from signet_covers where key_hash = h and book_id = any(ids) limit 40) s), '{}'::jsonb);
end $$;

create or replace function public.signet_forget(k text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k);
begin
  delete from signet_profiles where key_hash = h;
  delete from signet_libraries where key_hash = h;
  return true;
end $$;

create or replace function public.signet_profile_save(k text, name text, seal jsonb, snap jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare h text := signet_h(k); p record; c text; n text := btrim(coalesce(name, ''));
begin
  if length(n) < 1 or length(n) > 30 then raise exception 'bad_name'; end if;
  if snap is not null and octet_length(snap::text) > 300000 then raise exception 'bad_snap'; end if;
  select id, code into p from signet_profiles where key_hash = h;
  if found then
    update signet_profiles set name = n, seal = signet_profile_save.seal, snap = coalesce(signet_profile_save.snap, '{}'::jsonb), updated_at = now() where key_hash = h;
    return jsonb_build_object('id', p.id, 'code', p.code);
  end if;
  loop
    c := signet_code(6);
    exit when not exists (select 1 from signet_profiles where code = c);
  end loop;
  insert into signet_profiles(key_hash, code, name, seal, snap) values (h, c, n, signet_profile_save.seal, coalesce(signet_profile_save.snap, '{}'::jsonb)) returning id into p;
  return jsonb_build_object('id', p.id, 'code', c);
end $$;

create or replace function public.signet_friend_add(k text, code text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid; f record;
begin
  select id into me from signet_profiles where key_hash = signet_h(k);
  if me is null then return jsonb_build_object('ok', false, 'err', 'no_profile'); end if;
  select id, name into f from signet_profiles where signet_profiles.code = upper(btrim(signet_friend_add.code));
  if not found then return jsonb_build_object('ok', false, 'err', 'not_found'); end if;
  if f.id = me then return jsonb_build_object('ok', false, 'err', 'self'); end if;
  insert into signet_friends(a, b) values (me, f.id), (f.id, me) on conflict do nothing;
  return jsonb_build_object('ok', true, 'name', f.name);
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

create or replace function public.signet_challenge_create(k text, title text, kind text, target integer, starts date, ends date) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid; c text; cid uuid; tt text := btrim(coalesce(title, ''));
begin
  select id into me from signet_profiles where key_hash = signet_h(k);
  if me is null then raise exception 'no_profile'; end if;
  if length(tt) < 1 or length(tt) > 60 or ends < starts or ends - starts > 400 then raise exception 'bad_challenge'; end if;
  if (select count(*) from signet_challenges where owner = me and created_at > now() - interval '1 day') >= 20 then raise exception 'too_many'; end if;
  loop
    c := signet_code(6);
    exit when not exists (select 1 from signet_challenges where signet_challenges.code = c);
  end loop;
  insert into signet_challenges(code, title, kind, target, starts, ends, owner) values (c, tt, kind, target, starts, ends, me) returning id into cid;
  insert into signet_members(challenge, profile) values (cid, me);
  return jsonb_build_object('id', cid, 'code', c);
end $$;

create or replace function public.signet_challenge_join(k text, code text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid; ch record;
begin
  select id into me from signet_profiles where key_hash = signet_h(k);
  if me is null then return jsonb_build_object('ok', false, 'err', 'no_profile'); end if;
  select id, title into ch from signet_challenges where signet_challenges.code = upper(btrim(signet_challenge_join.code));
  if not found then return jsonb_build_object('ok', false, 'err', 'not_found'); end if;
  insert into signet_members(challenge, profile) values (ch.id, me) on conflict do nothing;
  return jsonb_build_object('ok', true, 'title', ch.title);
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

create or replace function public.signet_club(k text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me record;
begin
  select id, code, name into me from signet_profiles where key_hash = signet_h(k);
  if not found then return jsonb_build_object('me', null); end if;
  return jsonb_build_object(
    'me', jsonb_build_object('id', me.id, 'code', me.code, 'name', me.name),
    'friends', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'seal', p.seal, 'snap', p.snap, 'at', p.updated_at) order by p.updated_at desc)
        from signet_friends f join signet_profiles p on p.id = f.b where f.a = me.id), '[]'::jsonb),
    'challenges', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'title', c.title, 'kind', c.kind, 'target', c.target,
          'starts', c.starts, 'ends', c.ends, 'mine', c.owner = me.id,
          'members', (select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'seal', p.seal, 'snap', p.snap)) from signet_members m2 join signet_profiles p on p.id = m2.profile where m2.challenge = c.id))
        order by c.ends)
        from signet_members m join signet_challenges c on c.id = m.challenge where m.profile = me.id), '[]'::jsonb)
  );
end $$;

revoke all on function public.signet_h(text), public.signet_code(integer) from public, anon, authenticated;
revoke all on function public.signet_pull(text), public.signet_push(text, jsonb, integer), public.signet_cover_put(text, bigint, text),
  public.signet_covers_get(text, bigint[]), public.signet_forget(text), public.signet_profile_save(text, text, jsonb, jsonb),
  public.signet_friend_add(text, text), public.signet_friend_remove(text, uuid), public.signet_challenge_create(text, text, text, integer, date, date),
  public.signet_challenge_join(text, text), public.signet_challenge_leave(text, uuid), public.signet_club(text) from public;
grant execute on function public.signet_pull(text), public.signet_push(text, jsonb, integer), public.signet_cover_put(text, bigint, text),
  public.signet_covers_get(text, bigint[]), public.signet_forget(text), public.signet_profile_save(text, text, jsonb, jsonb),
  public.signet_friend_add(text, text), public.signet_friend_remove(text, uuid), public.signet_challenge_create(text, text, text, integer, date, date),
  public.signet_challenge_join(text, text), public.signet_challenge_leave(text, uuid), public.signet_club(text) to anon, authenticated;
