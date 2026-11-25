-- Household planning for everyone, and re-planning without losing anyone's
-- portions.
--
-- 1. Every member's food likes, dislikes and nevers count when the
--    household's shared meals are chosen. Members never read each other's
--    food_preferences rows: household_food_preferences() returns only the
--    household's combined counts per food or cuisine, with no user IDs.
--
-- 2. A serving's amount is either fitted by its eater (to their own day,
--    on their own device) or an estimate someone else's planning set
--    (plan_items.estimated). Planning the household week again keeps each
--    serving whose dish, day and meal haven't changed, with its amount and
--    flag, whatever the app sends; new or changed servings are estimates
--    until their eater fits them through replan_plan_items.
--
-- 3. Only a serving's eater may update it. Before, the update policy let
--    any member change any serving of the household's week directly.

-- ---------------------------------------------------------------------------
-- 1. The household's combined food preferences
-- ---------------------------------------------------------------------------
-- One row per food or cuisine anyone in the caller's household has a
-- preference about: how many members like it, dislike it or never want it,
-- and how many members there are. Nothing about who. Empty outside a
-- household.

create function public.household_food_preferences()
returns table (
  cuisine text,
  cofid_code text,
  cofid_name text,
  likes int,
  dislikes int,
  nevers int,
  members int
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.cuisine, p.cofid_code, p.cofid_name,
         (count(*) filter (where p.preference = 'like'))::int,
         (count(*) filter (where p.preference = 'dislike'))::int,
         (count(*) filter (where p.preference = 'never'))::int,
         (select count(*)::int from public.household_members x
          where x.household_id = me.household_id)
  from public.household_members me
  join public.household_members m on m.household_id = me.household_id
  join public.food_preferences p on p.user_id = m.user_id
  where me.user_id = (select auth.uid())
  group by me.household_id, p.cuisine, p.cofid_code, p.cofid_name;
$$;

revoke execute on function public.household_food_preferences()
  from public, anon;
grant execute on function public.household_food_preferences()
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Fitted or estimated servings
-- ---------------------------------------------------------------------------

alter table public.plan_items
  add column estimated boolean not null default false;

-- save_household_plan: as before, but keeps every unchanged serving (same
-- eater, day, meal and recipe) with its amount and flag. Others are saved
-- as estimates, within their range.

create or replace function public.save_household_plan(
  week_start date,
  notes jsonb,
  items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  household uuid;
  saved_id uuid;
  before jsonb;
begin
  select m.household_id into household
  from public.household_members m
  where m.user_id = (select auth.uid());
  if household is null then
    raise exception 'Not in a household' using errcode = 'TLH04';
  end if;

  if jsonb_typeof(save_household_plan.items) is distinct from 'array'
     or jsonb_array_length(save_household_plan.items) > 500 then
    raise exception 'Bad plan items' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_household_plan.items) as t(item)
    where (item ->> 'day')::date not between save_household_plan.week_start
                                         and save_household_plan.week_start + 6
  ) then
    raise exception 'Plan items must fall in the plan''s week'
      using errcode = '22023';
  end if;

  insert into public.meal_plans as p (household_id, week_start, notes)
  values (household, save_household_plan.week_start, save_household_plan.notes)
  on conflict (household_id, week_start) where household_id is not null
    do update set notes = excluded.notes
  returning p.id into saved_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'eater_id', i.eater_id, 'day', i.day, 'slot', i.slot,
           'recipe_id', i.recipe_id, 'amount', i.amount,
           'estimated', i.estimated)), '[]')
  into before
  from public.plan_items i
  where i.plan_id = saved_id;

  delete from public.plan_items i where i.plan_id = saved_id;

  insert into public.plan_items
    (plan_id, eater_id, day, slot, recipe_id, amount, amount_min, amount_max,
     batch, estimated)
  select saved_id, n.eater_id, n.day, n.slot, n.recipe_id,
         case when o.amount is null then n.amount
              else greatest(coalesce(n.amount_min, o.amount),
                            least(coalesce(n.amount_max, o.amount), o.amount))
         end,
         n.amount_min, n.amount_max, n.batch,
         coalesce(o.estimated, true)
  from jsonb_to_recordset(save_household_plan.items)
         as n(day date, slot text, recipe_id uuid, eater_id uuid,
              amount numeric, amount_min numeric, amount_max numeric,
              batch smallint)
  left join lateral (
    select o.amount, o.estimated
    from jsonb_to_recordset(before)
           as o(eater_id uuid, day date, slot text, recipe_id uuid,
                amount numeric, estimated boolean)
    where o.eater_id = n.eater_id
      and o.day = n.day
      and o.slot = n.slot
      and o.recipe_id = n.recipe_id
    limit 1
  ) as o on true;

  delete from public.prep_sessions s
  where s.plan_id = saved_id and s.cooked_at is null;

  insert into public.prep_sessions
    (household_id, plan_id, recipe_id, cook_on, portions)
  select household, saved_id, b.recipe_id, b.cook_on, sum(b.amount)
  from (
    select i.recipe_id, i.amount,
           min(i.day) over (partition by i.recipe_id, i.batch) as cook_on
    from public.plan_items i
    where i.plan_id = saved_id and i.batch is not null
  ) as b
  where not exists (
    select 1 from public.prep_sessions s
    where s.plan_id = saved_id
      and s.recipe_id = b.recipe_id
      and s.cook_on = b.cook_on
  )
  group by b.recipe_id, b.cook_on;

  insert into public.prep_portions
    (session_id, eater_id, day, slot, amount, use_by, storage, status)
  select s.id, b.eater_id, b.day, b.slot, b.amount,
         s.cook_on + r.fridge_days, 'fridge', 'planned'
  from (
    select i.recipe_id, i.eater_id, i.day, i.slot, i.amount,
           min(i.day) over (partition by i.recipe_id, i.batch) as cook_on
    from public.plan_items i
    where i.plan_id = saved_id and i.batch is not null
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

-- replan_plan_items: as before; an amount the eater sets is fitted.

create or replace function public.replan_plan_items(amounts jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if jsonb_typeof(amounts) is distinct from 'array'
     or jsonb_array_length(amounts) > 50 then
    raise exception 'Bad amounts' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(amounts) as t(a)
    left join public.plan_items i on i.id = (a ->> 'id')::uuid
    where i.id is null
       or i.eater_id <> (select auth.uid())
       or (a ->> 'amount')::numeric is null
       or (a ->> 'amount')::numeric
            not between coalesce(i.amount_min, i.amount)
                    and coalesce(i.amount_max, i.amount)
  ) then
    raise exception 'Each amount must be for one of your plan items, '
                    'within its range'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(amounts) as t(a)
    join public.plan_items i on i.id = (a ->> 'id')::uuid
    join public.prep_sessions s
      on s.plan_id = i.plan_id
     and s.recipe_id = i.recipe_id
     and s.cooked_at is not null
    join public.prep_portions p
      on p.session_id = s.id
     and p.eater_id = i.eater_id
     and p.day = i.day
     and p.slot = i.slot
     and p.status = 'planned'
    where (a ->> 'amount')::numeric <> i.amount
  ) then
    raise exception 'That meal''s batch is already cooked and portioned'
      using errcode = '22023';
  end if;

  update public.plan_items i
  set amount = (a ->> 'amount')::numeric,
      estimated = false
  from jsonb_array_elements(amounts) as t(a)
  where i.id = (a ->> 'id')::uuid;

  update public.prep_portions p
  set amount = i.amount
  from public.plan_items i, public.prep_sessions s
  where i.id in (
          select (a ->> 'id')::uuid from jsonb_array_elements(amounts) as t(a)
        )
    and s.plan_id = i.plan_id
    and s.recipe_id = i.recipe_id
    and s.cooked_at is null
    and p.session_id = s.id
    and p.eater_id = i.eater_id
    and p.day = i.day
    and p.slot = i.slot
    and p.status = 'planned';

  update public.prep_sessions s
  set portions = totals.portions
  from (
    select p.session_id, sum(p.amount) as portions
    from public.prep_portions p
    where p.status <> 'discarded'
    group by p.session_id
  ) as totals
  where totals.session_id = s.id
    and s.cooked_at is null
    and s.plan_id in (
      select i.plan_id from public.plan_items i
      where i.id in (
        select (a ->> 'id')::uuid from jsonb_array_elements(amounts) as t(a)
      )
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Only the eater updates a serving
-- ---------------------------------------------------------------------------
-- Personal plans' items are always the user's own. A household week is
-- replaced whole by save_household_plan (delete and insert), so members
-- never need to update each other's servings.

drop policy "plan items: update" on public.plan_items;
create policy "plan items: update" on public.plan_items
  for update to authenticated
  using (eater_id = (select auth.uid())
         and exists (select 1 from public.meal_plans p where p.id = plan_id))
  with check (eater_id = (select auth.uid())
              and private.plan_item_allowed(plan_id, eater_id, food_id,
                                            recipe_id, meal_rule_id));
