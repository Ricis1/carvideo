-- CarVideo v12: bendras serveris pranešimams ir draugams (Supabase, PostgreSQL).
-- 1) supabase.com → New project. 2) SQL Editor → įklijuoti šį failą → Run.
-- 3) Project Settings → API: nukopijuoti URL ir „anon public“ raktą į CarVideo → Nustatymai → Serveris.

create extension if not exists postgis;

-- Vairuotojų pranešimai (policija, duobės, avarijos...). Jokių vardų – tik vieta, tipas, laikas.
create table if not exists alerts (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('police','pothole','crash','hazard','jam')),
  lat double precision not null,
  lon double precision not null,
  geo geography(point) generated always as (st_setsrid(st_makepoint(lon, lat), 4326)::geography) stored,
  country text,                       -- ISO kodas, kad būtų galima taikyti šalies taisykles
  created_at timestamptz not null default now(),
  confirmations int not null default 0,
  denials int not null default 0
);
create index if not exists alerts_geo on alerts using gist (geo);

-- Pranešimai 10 km spinduliu, ne senesni nei 1 val., neatmesti kitų vairuotojų.
create or replace function alerts_nearby(p_lat double precision, p_lon double precision, p_radius_m int default 10000)
returns setof alerts language sql stable as $$
  select * from alerts
  where created_at > now() - interval '1 hour'
    and denials < confirmations + 2
    and st_dwithin(geo, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, p_radius_m)
  order by created_at desc limit 200;
$$;

create or replace function alerts_vote(p_id uuid, p_still_there boolean)
returns void language sql as $$
  update alerts set
    confirmations = confirmations + case when p_still_there then 1 else 0 end,
    denials       = denials       + case when p_still_there then 0 else 1 end,
    created_at    = case when p_still_there then now() else created_at end   -- patvirtintas pranešimas gyvena ilgiau
  where id = p_id;
$$;

-- Draugai: gyva vieta tik kol dalinamasi kelione (kodas galioja iki atvykimo).
create table if not exists live_trips (
  code text primary key,              -- pvz. 'K7Q2XA', siunčiamas draugui nuoroda
  name text not null,                 -- rodomas vardas (vartotojas įveda pats)
  lat double precision, lon double precision, speed_kmh int,
  destination text, eta timestamptz,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '4 hours'
);

-- Saugumas (Row Level Security): anoniminiai naudotojai gali skaityti ir rašyti, bet ne trinti.
alter table alerts enable row level security;
alter table live_trips enable row level security;
create policy "skaityti pranešimus" on alerts for select using (true);
create policy "kurti pranešimus" on alerts for insert with check (true);
create policy "skaityti keliones" on live_trips for select using (expires_at > now());
create policy "kurti keliones" on live_trips for insert with check (true);
create policy "atnaujinti savo kelionę" on live_trips for update using (expires_at > now());

-- Senų įrašų valymas kas valandą (Database → Cron arba pg_cron):
-- select cron.schedule('valymas', '0 * * * *', $$ delete from alerts where created_at < now() - interval '2 hours'; delete from live_trips where expires_at < now(); $$);

-- ===== v14: kuro kainos iš vairuotojų (šalims be oficialių atvirų duomenų) =====
create table if not exists fuel_prices (
  id bigserial primary key,
  station_id text not null,
  name text,
  lat double precision not null,
  lon double precision not null,
  fuel text not null check (fuel in ('95','98','D','LPG','kWh')),
  price numeric(6,3) not null check (price > 0 and price < 100),
  created_at timestamptz not null default now()
);
create index if not exists fuel_prices_geo on fuel_prices using gist (geography(st_makepoint(lon, lat)));
alter table fuel_prices enable row level security;
create policy "skaityti kainas" on fuel_prices for select using (true);
create policy "pranešti kainą" on fuel_prices for insert with check (true);

-- Naujausia kiekvienos stotelės ir kuro rūšies kaina per paskutines 3 dienas.
create or replace function fuel_prices_nearby(lat double precision, lon double precision, radius_m int default 8000)
returns table (station_id text, name text, lat double precision, lon double precision, fuel text, price numeric, created_at timestamptz)
language sql stable as $$
  select distinct on (f.station_id, f.fuel) f.station_id, f.name, f.lat, f.lon, f.fuel, f.price, f.created_at
  from fuel_prices f
  where f.created_at > now() - interval '3 days'
    and st_dwithin(geography(st_makepoint(f.lon, f.lat)), geography(st_makepoint(fuel_prices_nearby.lon, fuel_prices_nearby.lat)), radius_m)
  order by f.station_id, f.fuel, f.created_at desc;
$$;
