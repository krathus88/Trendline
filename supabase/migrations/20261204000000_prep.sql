-- Meal prep: the batch cooks a saved plan needs (prep_sessions) and the
-- portions each one is split into (prep_portions), with where they're kept,
-- when they must be eaten by and what became of them.
--
-- Same rules as every user table: user_id defaults to auth.uid() and
-- cascades on account deletion, RLS with own-row policies for
-- `authenticated`, nothing for `anon`, ranges checked here.

-- ---------------------------------------------------------------------------
-- prep_sessions
-- ---------------------------------------------------------------------------

create table public.prep_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Reserved for households (joint prep). Always null until then.
  household_id uuid,
  -- The plan it was made for. A batch already cooked outlives its plan.
  plan_id uuid references public.meal_plans (id) on delete set null,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  cook_on date not null,
  -- How many of the recipe's portions to cook (the recipe is scaled to it).
  portions numeric(5, 2) not null check (portions > 0 and portions <= 100),
  -- Set when the user marks it cooked, with the batch's measured weight.
  cooked_at timestamptz,
  cooked_weight_g numeric(7, 1)
    check (cooked_weight_g > 0 and cooked_weight_g < 50000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((cooked_at is null) = (cooked_weight_g is null))
);

create index prep_sessions_user_cook_idx on public.prep_sessions (user_id, cook_on);
create index prep_sessions_plan_idx on public.prep_sessions (plan_id);
create index prep_sessions_recipe_idx on public.prep_sessions (recipe_id);

-- ---------------------------------------------------------------------------
-- prep_portions
-- ---------------------------------------------------------------------------

create table public.prep_portions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  session_id uuid not null
    references public.prep_sessions (id) on delete cascade,
  -- Who eats it, which isn't always who cooked it once households exist.
  -- Until then it must be the owner (checked by the policies below).
  eater_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- The meal it's planned for; both null for a leftover kept for later.
  day date,
  slot text check (slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  -- Portions of the recipe (a share of the session's cooked weight).
  amount numeric(4, 2) not null check (amount > 0 and amount <= 10),
  use_by date not null,
  storage text not null default 'fridge'
    check (storage in ('fridge', 'freezer')),
  status text not null default 'planned'
    check (status in ('planned', 'eaten', 'leftover', 'discarded')),
  -- The log entry made when it was eaten.
  food_log_id uuid references public.food_logs (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((day is null) = (slot is null)),
  check (food_log_id is null or status = 'eaten')
);

create index prep_portions_session_idx on public.prep_portions (session_id);
create index prep_portions_eater_idx on public.prep_portions (eater_id);
create index prep_portions_log_idx on public.prep_portions (food_log_id);

create trigger prep_sessions_set_updated_at before update on public.prep_sessions
  for each row execute function private.set_updated_at();
create trigger prep_portions_set_updated_at before update on public.prep_portions
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access: authenticated users, own rows only. No anon access.
-- ---------------------------------------------------------------------------

revoke all on table public.prep_sessions, public.prep_portions from anon;
grant select, insert, update, delete on table
  public.prep_sessions, public.prep_portions
  to authenticated;

alter table public.prep_sessions enable row level security;
alter table public.prep_portions enable row level security;

-- A session may only belong to the user's own plan and recipe. The
-- subqueries run under RLS, so another user's rows are invisible and fail
-- the check.
create policy "own prep sessions: select" on public.prep_sessions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own prep sessions: insert" on public.prep_sessions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and household_id is null
    and (plan_id is null
         or exists (select 1 from public.meal_plans p where p.id = plan_id))
    and exists (select 1 from public.recipes r where r.id = recipe_id)
  );
create policy "own prep sessions: update" on public.prep_sessions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and household_id is null
    and (plan_id is null
         or exists (select 1 from public.meal_plans p where p.id = plan_id))
    and exists (select 1 from public.recipes r where r.id = recipe_id)
  );
create policy "own prep sessions: delete" on public.prep_sessions
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "own prep portions: select" on public.prep_portions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own prep portions: insert" on public.prep_portions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and eater_id = (select auth.uid())
    and exists (select 1 from public.prep_sessions s where s.id = session_id)
    and (food_log_id is null
         or exists (select 1 from public.food_logs l where l.id = food_log_id))
  );
create policy "own prep portions: update" on public.prep_portions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and eater_id = (select auth.uid())
    and exists (select 1 from public.prep_sessions s where s.id = session_id)
    and (food_log_id is null
         or exists (select 1 from public.food_logs l where l.id = food_log_id))
  );
create policy "own prep portions: delete" on public.prep_portions
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- save_meal_plan: now also lays out the plan's prep
-- ---------------------------------------------------------------------------
-- Same plan saving as before, then, in the same transaction:
-- * The plan's prep sessions not yet cooked are replaced. Cooked ones are
--   kept with their portions (they're real food in the fridge).
-- * Each batch of a recipe (plan items sharing a batch number) becomes a
--   session cooked on the batch's first day, scaled to the portions the
--   plan eats. Batches of one recipe starting the same day are cooked
--   together. A batch whose recipe and day match a kept, cooked session
--   isn't added again.
-- * Each planned serving becomes a portion in the fridge, to be eaten by
--   the cook day + the recipe's fridge days.

create or replace function public.save_meal_plan(
  week_start date,
  kcal_target numeric,
  protein_target_g numeric,
  carbs_target_g numeric,
  fat_target_g numeric,
  fibre_target_g numeric,
  notes jsonb,
  -- [{"day": date, "slot": text, "food_id": uuid?, "recipe_id": uuid?,
  --   "amount": number, "amount_min": number?, "amount_max": number?,
  --   "locked": bool, "batch": int?, "meal_rule_id": uuid?}, ...]
  items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved_id uuid;
begin
  if jsonb_typeof(items) is distinct from 'array'
     or jsonb_array_length(items) > 500 then
    raise exception 'Bad plan items' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(items) as t(item)
    where (item ->> 'day')::date not between save_meal_plan.week_start
                                         and save_meal_plan.week_start + 6
  ) then
    raise exception 'Plan items must fall in the plan''s week'
      using errcode = '22023';
  end if;

  insert into public.meal_plans as p
    (week_start, kcal_target, protein_target_g, carbs_target_g,
     fat_target_g, fibre_target_g, notes)
  values
    (save_meal_plan.week_start, save_meal_plan.kcal_target,
     save_meal_plan.protein_target_g, save_meal_plan.carbs_target_g,
     save_meal_plan.fat_target_g, save_meal_plan.fibre_target_g,
     save_meal_plan.notes)
  -- Named by constraint: the parameter names shadow the column names.
  on conflict on constraint meal_plans_user_id_week_start_key do update
    set kcal_target = excluded.kcal_target,
        protein_target_g = excluded.protein_target_g,
        carbs_target_g = excluded.carbs_target_g,
        fat_target_g = excluded.fat_target_g,
        fibre_target_g = excluded.fibre_target_g,
        notes = excluded.notes
  returning p.id into saved_id;

  delete from public.plan_items i where i.plan_id = saved_id;

  insert into public.plan_items
    (plan_id, day, slot, food_id, recipe_id, amount, amount_min, amount_max,
     locked, batch, meal_rule_id)
  select saved_id,
         (item ->> 'day')::date,
         item ->> 'slot',
         (item ->> 'food_id')::uuid,
         (item ->> 'recipe_id')::uuid,
         (item ->> 'amount')::numeric,
         (item ->> 'amount_min')::numeric,
         (item ->> 'amount_max')::numeric,
         coalesce((item ->> 'locked')::boolean, false),
         (item ->> 'batch')::smallint,
         (item ->> 'meal_rule_id')::uuid
  from jsonb_array_elements(items) as t(item);

  -- Prep. Cascades remove the portions of the sessions deleted here.
  delete from public.prep_sessions s
  where s.plan_id = saved_id and s.cooked_at is null;

  insert into public.prep_sessions (plan_id, recipe_id, cook_on, portions)
  select saved_id, b.recipe_id, b.cook_on, sum(b.amount)
  from (
    select i.recipe_id, i.amount,
           min(i.day) over (partition by i.recipe_id, i.batch) as cook_on
    from public.plan_items i
    where i.plan_id = saved_id
      and i.recipe_id is not null
      and i.batch is not null
  ) as b
  where not exists (
    -- Only cooked sessions are left for this plan at this point.
    select 1 from public.prep_sessions s
    where s.plan_id = saved_id
      and s.recipe_id = b.recipe_id
      and s.cook_on = b.cook_on
  )
  group by b.recipe_id, b.cook_on;

  insert into public.prep_portions
    (session_id, day, slot, amount, use_by, storage, status)
  select s.id, b.day, b.slot, b.amount, s.cook_on + r.fridge_days,
         'fridge', 'planned'
  from (
    select i.recipe_id, i.day, i.slot, i.amount,
           min(i.day) over (partition by i.recipe_id, i.batch) as cook_on
    from public.plan_items i
    where i.plan_id = saved_id
      and i.recipe_id is not null
      and i.batch is not null
  ) as b
  join public.prep_sessions s
    on s.plan_id = saved_id
   and s.recipe_id = b.recipe_id
   and s.cook_on = b.cook_on
   and s.cooked_at is null
  join public.recipes r on r.id = b.recipe_id;

  return saved_id;
end;
$$;

-- create or replace keeps the existing grants; restated so this file reads
-- on its own.
revoke execute on function public.save_meal_plan(
  date, numeric, numeric, numeric, numeric, numeric, jsonb, jsonb
) from public, anon;
grant execute on function public.save_meal_plan(
  date, numeric, numeric, numeric, numeric, numeric, jsonb, jsonb
) to authenticated;
