-- Core user data: profile, weigh-ins, saved foods and the food log.
--
-- Every table here holds one user's data:
--   * user_id defaults to auth.uid() and cascades on account deletion;
--   * RLS is on, with select/insert/update/delete policies on
--     user_id = auth.uid() for the `authenticated` role only;
--   * `anon` has no access at all;
--   * ranges are enforced with CHECK constraints, not just in the app.
-- Units are metric throughout (kg, g, kcal); the app converts for display.

-- ---------------------------------------------------------------------------
-- Shared trigger: keep updated_at current
-- ---------------------------------------------------------------------------

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.set_updated_at()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- profiles: one row per user
-- ---------------------------------------------------------------------------

create table public.profiles (
  user_id uuid primary key default auth.uid()
    references auth.users (id) on delete cascade,
  sex text not null check (sex in ('male', 'female')),
  birth_year int not null check (birth_year between 1900 and 2100),
  height_cm numeric(4, 1) not null check (height_cm between 100 and 250),
  activity_level text not null
    check (activity_level in ('sedentary', 'light', 'moderate', 'very')),
  weight_unit text not null default 'kg'
    check (weight_unit in ('kg', 'lb', 'st_lb')),
  use_lean_mass boolean not null default false,
  disclaimer_accepted_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- weigh_ins: scale readings
-- ---------------------------------------------------------------------------

create table public.weigh_ins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  measured_at timestamptz not null,
  weight_kg numeric(5, 2) not null check (weight_kg between 25 and 400),
  body_fat_pct numeric(4, 1) check (body_fat_pct between 2 and 75),
  lean_mass_kg numeric(5, 2) check (lean_mass_kg between 10 and 200),
  source text not null default 'manual'
    check (source in ('manual', 'health_connect')),
  -- The source system's record ID (Health Connect), for de-duplication.
  external_id text check (char_length(external_id) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (lean_mass_kg is null or lean_mass_kg < weight_kg),
  check (source = 'manual' or external_id is not null)
);

create index weigh_ins_user_measured_idx
  on public.weigh_ins (user_id, measured_at desc);

create unique index weigh_ins_user_external_idx
  on public.weigh_ins (user_id, source, external_id)
  where external_id is not null;

-- ---------------------------------------------------------------------------
-- foods: the user's saved products, per 100 g
-- ---------------------------------------------------------------------------

create table public.foods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Reserved for households (shared foods). Always null until then.
  household_id uuid,
  barcode text check (barcode ~ '^[0-9]{6,14}$'),
  name text not null check (char_length(name) between 1 and 200),
  brand text check (char_length(brand) between 1 and 200),
  kcal_100g numeric(6, 1) not null check (kcal_100g between 0 and 900),
  protein_100g numeric(5, 1) not null check (protein_100g between 0 and 100),
  carbs_100g numeric(5, 1) not null check (carbs_100g between 0 and 100),
  fat_100g numeric(5, 1) not null check (fat_100g between 0 and 100),
  fibre_100g numeric(5, 1) not null default 0
    check (fibre_100g between 0 and 100),
  sugar_100g numeric(5, 1) check (sugar_100g between 0 and 100),
  salt_100g numeric(5, 1) check (salt_100g between 0 and 100),
  serving_g numeric(6, 1) check (serving_g > 0 and serving_g <= 5000),
  source text not null check (source in ('off', 'manual')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- 100 g of food can't hold more than 100 g of macros (small tolerance for
  -- rounding on labels).
  check (protein_100g + carbs_100g + fat_100g + fibre_100g <= 105),
  check (sugar_100g is null or sugar_100g <= carbs_100g + 0.5)
);

create index foods_user_name_idx on public.foods (user_id, name);

create unique index foods_user_barcode_idx
  on public.foods (user_id, barcode)
  where barcode is not null;

-- ---------------------------------------------------------------------------
-- food_logs: what was eaten, with a nutrition snapshot
-- ---------------------------------------------------------------------------
-- The snapshot (name and nutrition at the time of logging) means editing or
-- deleting a saved food never rewrites history.

create table public.food_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- The user's local calendar day, so day totals don't depend on time zones.
  eaten_on date not null,
  eaten_at timestamptz not null default now(),
  slot text not null check (slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  food_id uuid references public.foods (id) on delete set null,
  food_name text not null check (char_length(food_name) between 1 and 200),
  food_brand text check (char_length(food_brand) between 1 and 200),
  grams numeric(6, 1) not null check (grams > 0 and grams < 5000),
  kcal numeric(7, 1) not null check (kcal between 0 and 20000),
  protein_g numeric(6, 1) not null check (protein_g between 0 and 5000),
  carbs_g numeric(6, 1) not null check (carbs_g between 0 and 5000),
  fat_g numeric(6, 1) not null check (fat_g between 0 and 5000),
  fibre_g numeric(6, 1) not null default 0 check (fibre_g between 0 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index food_logs_user_day_idx on public.food_logs (user_id, eaten_on);
create index food_logs_food_idx on public.food_logs (food_id);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger weigh_ins_set_updated_at before update on public.weigh_ins
  for each row execute function private.set_updated_at();
create trigger foods_set_updated_at before update on public.foods
  for each row execute function private.set_updated_at();
create trigger food_logs_set_updated_at before update on public.food_logs
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access: authenticated users, own rows only. No anon access.
-- ---------------------------------------------------------------------------

revoke all on table
  public.profiles, public.weigh_ins, public.foods, public.food_logs
  from anon;

grant select, insert, update, delete on table
  public.profiles, public.weigh_ins, public.foods, public.food_logs
  to authenticated;

alter table public.profiles enable row level security;
alter table public.weigh_ins enable row level security;
alter table public.foods enable row level security;
alter table public.food_logs enable row level security;

-- `(select auth.uid())` is evaluated once per query rather than per row.

create policy "own profile: select" on public.profiles
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own profile: insert" on public.profiles
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own profile: update" on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own profile: delete" on public.profiles
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "own weigh-ins: select" on public.weigh_ins
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own weigh-ins: insert" on public.weigh_ins
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own weigh-ins: update" on public.weigh_ins
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own weigh-ins: delete" on public.weigh_ins
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "own foods: select" on public.foods
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own foods: insert" on public.foods
  for insert to authenticated
  with check (user_id = (select auth.uid()) and household_id is null);
create policy "own foods: update" on public.foods
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and household_id is null);
create policy "own foods: delete" on public.foods
  for delete to authenticated using (user_id = (select auth.uid()));

-- A log entry may only point at one of the user's own foods. The subquery
-- runs under RLS, so another user's food is invisible and fails the check.
create policy "own food logs: select" on public.food_logs
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own food logs: insert" on public.food_logs
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
  );
create policy "own food logs: update" on public.food_logs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
  );
create policy "own food logs: delete" on public.food_logs
  for delete to authenticated using (user_id = (select auth.uid()));
