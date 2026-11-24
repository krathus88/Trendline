-- Meal plans: one per week (Monday to Sunday), with the targets it was
-- planned for and its items: dish servings and rule items, each pointing at
-- one of the user's own foods or recipes.
--
-- Same rules as every user table: user_id defaults to auth.uid() and
-- cascades on account deletion, RLS with own-row policies for
-- `authenticated`, nothing for `anon`, ranges checked here.

-- ---------------------------------------------------------------------------
-- recipes: dishes the planner copied in stay out of the Recipes list
-- ---------------------------------------------------------------------------
-- A dish made from a template is copied into the user's recipes when a
-- plan uses it (so plans, logs and prep only point at the user's own data),
-- but it only shows in their Recipes list once they choose to keep it.

alter table public.recipes
  add column listed boolean not null default true;

-- ---------------------------------------------------------------------------
-- meal_plans
-- ---------------------------------------------------------------------------

create table public.meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Reserved for households (shared plans). Always null until then.
  household_id uuid,
  week_start date not null check (extract(isodow from week_start) = 1),
  -- The day targets the plan was made for.
  kcal_target numeric(6, 1) not null check (kcal_target between 800 and 6000),
  protein_target_g numeric(5, 1) not null
    check (protein_target_g between 0 and 500),
  carbs_target_g numeric(5, 1) not null check (carbs_target_g between 0 and 1000),
  fat_target_g numeric(5, 1) not null check (fat_target_g between 0 and 500),
  fibre_target_g numeric(5, 1) not null check (fibre_target_g between 0 and 200),
  -- What the planner couldn't do, shown with the plan.
  notes jsonb not null default '[]'
    check (jsonb_typeof(notes) = 'array' and pg_column_size(notes) < 8000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, week_start)
);

-- ---------------------------------------------------------------------------
-- plan_items
-- ---------------------------------------------------------------------------

create table public.plan_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  plan_id uuid not null references public.meal_plans (id) on delete cascade,
  day date not null,
  slot text not null check (slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  -- Exactly one. Deleting the food or recipe removes it from plans.
  food_id uuid references public.foods (id) on delete cascade,
  recipe_id uuid references public.recipes (id) on delete cascade,
  -- Grams of a food, or portions of a recipe.
  amount numeric(6, 2) not null check (amount > 0 and amount < 5000),
  -- The range the planner may refit it within; null when fixed.
  amount_min numeric(6, 2) check (amount_min > 0),
  amount_max numeric(6, 2) check (amount_max < 5000),
  locked boolean not null default false,
  -- Servings of one dish cooked together share a batch number.
  batch smallint check (batch between 0 and 200),
  meal_rule_id uuid references public.meal_rules (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((food_id is null) <> (recipe_id is null)),
  check (recipe_id is null or amount <= 10),
  check ((amount_min is null) = (amount_max is null)),
  check (amount_min is null or amount_min <= amount_max)
);

create index plan_items_plan_idx on public.plan_items (plan_id, day);
create index plan_items_food_idx on public.plan_items (food_id);
create index plan_items_recipe_idx on public.plan_items (recipe_id);
create index plan_items_rule_idx on public.plan_items (meal_rule_id);

create trigger meal_plans_set_updated_at before update on public.meal_plans
  for each row execute function private.set_updated_at();
create trigger plan_items_set_updated_at before update on public.plan_items
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access: authenticated users, own rows only. No anon access.
-- ---------------------------------------------------------------------------

revoke all on table public.meal_plans, public.plan_items from anon;
grant select, insert, update, delete on table
  public.meal_plans, public.plan_items
  to authenticated;

alter table public.meal_plans enable row level security;
alter table public.plan_items enable row level security;

create policy "own meal plans: select" on public.meal_plans
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own meal plans: insert" on public.meal_plans
  for insert to authenticated
  with check (user_id = (select auth.uid()) and household_id is null);
create policy "own meal plans: update" on public.meal_plans
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and household_id is null);
create policy "own meal plans: delete" on public.meal_plans
  for delete to authenticated using (user_id = (select auth.uid()));

-- An item may only join the user's own plan and point at their own food,
-- recipe and rule. The subqueries run under RLS, so another user's rows
-- are invisible and fail the check.
create policy "own plan items: select" on public.plan_items
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own plan items: insert" on public.plan_items
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.meal_plans p where p.id = plan_id)
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
    and (recipe_id is null
         or exists (select 1 from public.recipes r where r.id = recipe_id))
    and (meal_rule_id is null
         or exists (select 1 from public.meal_rules m where m.id = meal_rule_id))
  );
create policy "own plan items: update" on public.plan_items
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.meal_plans p where p.id = plan_id)
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
    and (recipe_id is null
         or exists (select 1 from public.recipes r where r.id = recipe_id))
    and (meal_rule_id is null
         or exists (select 1 from public.meal_rules m where m.id = meal_rule_id))
  );
create policy "own plan items: delete" on public.plan_items
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- save_meal_plan: a week's plan and its items in one transaction
-- ---------------------------------------------------------------------------
-- Replaces the user's plan for that week (if any) and all its items, so a
-- failed save never leaves half a plan. Runs as the caller (security
-- invoker): every statement is subject to the RLS policies above. All
-- values are bound parameters.

create function public.save_meal_plan(
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

  return saved_id;
end;
$$;

revoke execute on function public.save_meal_plan(
  date, numeric, numeric, numeric, numeric, numeric, jsonb, jsonb
) from public, anon;
grant execute on function public.save_meal_plan(
  date, numeric, numeric, numeric, numeric, numeric, jsonb, jsonb
) to authenticated;
