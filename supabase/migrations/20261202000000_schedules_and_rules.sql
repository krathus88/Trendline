-- Day schedules (wake and sleep times per weekday, from which meal times
-- are worked out) and meal rules (mandatory and recurring items the
-- planner must respect).
--
-- Same rules as every user table: user_id defaults to auth.uid() and
-- cascades on account deletion, RLS with own-row policies for
-- `authenticated`, nothing for `anon`, ranges checked here.

-- ---------------------------------------------------------------------------
-- day_schedules: one row per weekday the user has set
-- ---------------------------------------------------------------------------
-- Weekdays the user hasn't set use the app's default (07:00 to 23:00).

create table public.day_schedules (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- ISO weekday: 1 = Monday ... 7 = Sunday.
  weekday smallint not null check (weekday between 1 and 7),
  wake_time time not null,
  -- May be after midnight (earlier than wake_time), for late nights and
  -- night shifts.
  sleep_time time not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, weekday),
  -- Awake for 8 to 20 hours, counting across midnight.
  check (
    (((extract(epoch from (sleep_time - wake_time)) / 60)::int + 1440) % 1440)
      between 480 and 1200
  )
);

-- ---------------------------------------------------------------------------
-- meal_rules
-- ---------------------------------------------------------------------------

create table public.meal_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Exactly one: one of the user's foods, or one of their recipes. Deleting
  -- the food or recipe deletes its rules.
  food_id uuid references public.foods (id) on delete cascade,
  recipe_id uuid references public.recipes (id) on delete cascade,
  -- Null: any meal.
  slot text check (slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  frequency text not null
    check (frequency in ('daily', 'min_per_week', 'max_per_week')),
  -- Times a week, for min_per_week and max_per_week. At most once per meal,
  -- so at most 7 for one meal and 28 for any meal.
  times_per_week smallint check (times_per_week between 1 and 28),
  -- The amount each time: grams of a food, or portions of a recipe. Equal
  -- for a fixed amount.
  amount_min numeric(6, 1) not null check (amount_min > 0 and amount_min < 5000),
  amount_max numeric(6, 1) not null check (amount_max > 0 and amount_max < 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((food_id is null) <> (recipe_id is null)),
  check (amount_min <= amount_max),
  -- Recipes are eaten in portions: up to 10 at a time.
  check (recipe_id is null or amount_max <= 10),
  check ((frequency = 'daily') = (times_per_week is null)),
  check (slot is null or times_per_week is null or times_per_week <= 7)
);

create index meal_rules_user_idx on public.meal_rules (user_id);
create index meal_rules_food_idx on public.meal_rules (food_id);
create index meal_rules_recipe_idx on public.meal_rules (recipe_id);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

create trigger day_schedules_set_updated_at
  before update on public.day_schedules
  for each row execute function private.set_updated_at();
create trigger meal_rules_set_updated_at
  before update on public.meal_rules
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access: authenticated users, own rows only. No anon access.
-- ---------------------------------------------------------------------------

revoke all on table public.day_schedules, public.meal_rules from anon;
grant select, insert, update, delete on table
  public.day_schedules, public.meal_rules
  to authenticated;

alter table public.day_schedules enable row level security;
alter table public.meal_rules enable row level security;

create policy "own day schedules: select" on public.day_schedules
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own day schedules: insert" on public.day_schedules
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own day schedules: update" on public.day_schedules
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own day schedules: delete" on public.day_schedules
  for delete to authenticated using (user_id = (select auth.uid()));

-- A rule may only point at the user's own food or recipe. The subqueries
-- run under RLS, so another user's rows are invisible and fail the check.
create policy "own meal rules: select" on public.meal_rules
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own meal rules: insert" on public.meal_rules
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
    and (recipe_id is null
         or exists (select 1 from public.recipes r where r.id = recipe_id))
  );
create policy "own meal rules: update" on public.meal_rules
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
    and (recipe_id is null
         or exists (select 1 from public.recipes r where r.id = recipe_id))
  );
create policy "own meal rules: delete" on public.meal_rules
  for delete to authenticated using (user_id = (select auth.uid()));
