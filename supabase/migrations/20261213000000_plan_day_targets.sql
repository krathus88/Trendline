-- Each day's targets on a personal week's plan.
--
-- A week is planned to each day's own targets: days after today take the
-- targets they would have if the trend follows the plan, so a goal date or
-- target weight reached inside the week turns the days after it into
-- maintenance. The five target columns stay as Monday's (or today's, for
-- the current week) and `day_targets` holds all seven, Monday first.
-- Null on plans saved before this, which used one day's targets for every
-- day. Household weeks have no targets at all, so none here either.
-- Exported with the rest of `meal_plans` (whole rows) by export_my_data().

alter table public.meal_plans
  add column day_targets jsonb,
  add constraint meal_plans_day_targets_check check (
    day_targets is null
    or (
      household_id is null
      and case
        when jsonb_typeof(day_targets) = 'array' then
          jsonb_array_length(day_targets) = 7
          and not jsonb_path_exists(
            day_targets,
            '$[*] ? (
               !(exists(@.kcal)) || @.kcal.type() != "number"
               || @.kcal < 800 || @.kcal > 6000
               || !(exists(@.protein_g)) || @.protein_g.type() != "number"
               || @.protein_g < 0 || @.protein_g > 500
               || !(exists(@.carbs_g)) || @.carbs_g.type() != "number"
               || @.carbs_g < 0 || @.carbs_g > 1000
               || !(exists(@.fat_g)) || @.fat_g.type() != "number"
               || @.fat_g < 0 || @.fat_g > 500
               || !(exists(@.fibre_g)) || @.fibre_g.type() != "number"
               || @.fibre_g < 0 || @.fibre_g > 200
             )'
          )
        else false
      end
    )
  );

-- ---------------------------------------------------------------------------
-- save_meal_plan: also saves each day's targets
-- ---------------------------------------------------------------------------
-- The new argument has a default, so callers that don't send it still
-- work (their plan gets no day targets). Dropped and recreated, as an
-- added argument makes a new function.
--
-- day_targets: [{"kcal": n, "protein_g": n, "carbs_g": n, "fat_g": n,
--                "fibre_g": n}, ...] seven of them, Monday first, or null.

drop function public.save_meal_plan(
  date, numeric, numeric, numeric, numeric, numeric, jsonb, jsonb
);

create function public.save_meal_plan(
  week_start date,
  kcal_target numeric,
  protein_target_g numeric,
  carbs_target_g numeric,
  fat_target_g numeric,
  fibre_target_g numeric,
  notes jsonb,
  items jsonb,
  day_targets jsonb default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  saved_id uuid;
begin
  if jsonb_typeof(save_meal_plan.items) is distinct from 'array'
     or jsonb_array_length(save_meal_plan.items) > 500 then
    raise exception 'Bad plan items' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_meal_plan.items) as t(item)
    where (item ->> 'day')::date not between save_meal_plan.week_start
                                         and save_meal_plan.week_start + 6
  ) then
    raise exception 'Plan items must fall in the plan''s week'
      using errcode = '22023';
  end if;

  insert into public.meal_plans as p
    (week_start, kcal_target, protein_target_g, carbs_target_g,
     fat_target_g, fibre_target_g, notes, day_targets)
  values
    (save_meal_plan.week_start, save_meal_plan.kcal_target,
     save_meal_plan.protein_target_g, save_meal_plan.carbs_target_g,
     save_meal_plan.fat_target_g, save_meal_plan.fibre_target_g,
     save_meal_plan.notes, save_meal_plan.day_targets)
  on conflict (user_id, week_start) where household_id is null do update
    set kcal_target = excluded.kcal_target,
        protein_target_g = excluded.protein_target_g,
        carbs_target_g = excluded.carbs_target_g,
        fat_target_g = excluded.fat_target_g,
        fibre_target_g = excluded.fibre_target_g,
        notes = excluded.notes,
        day_targets = excluded.day_targets
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
  from jsonb_array_elements(save_meal_plan.items) as t(item);

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

revoke execute on function public.save_meal_plan(
  date, numeric, numeric, numeric, numeric, numeric, jsonb, jsonb, jsonb
) from public, anon;
grant execute on function public.save_meal_plan(
  date, numeric, numeric, numeric, numeric, numeric, jsonb, jsonb, jsonb
) to authenticated;
