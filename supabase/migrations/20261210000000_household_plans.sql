-- Household plans and joint prep.
--
-- A household week is a meal plan owned by the household (household_id
-- set, one per household per week). It holds only the shared dishes: one
-- plan item per eater per serving, each pointing at a household recipe,
-- with that eater's amount and the range it may be refitted within. Any
-- member can make or remake it.
--
-- Each member fits their own servings when they plan their own week, on
-- their own device: their targets never leave it. Others see only the
-- portion sizes, which is what the household warning says. A member may
-- change only their own servings' amounts (replan_plan_items).
--
-- Saving a household week lays out household prep sessions: one per batch,
-- cooked once, with a portion per eater. Any member can mark a batch cooked
-- or move a portion to the freezer; each eats their own.
--
-- Personal plans, prep and everything else stay as they were: a personal
-- plan's items are eaten by the user and use only their own foods and
-- recipes.

-- ---------------------------------------------------------------------------
-- meal_plans: personal or household
-- ---------------------------------------------------------------------------

alter table public.meal_plans drop constraint meal_plans_user_id_week_start_key;
create unique index meal_plans_user_week_idx
  on public.meal_plans (user_id, week_start) where household_id is null;
create unique index meal_plans_household_week_idx
  on public.meal_plans (household_id, week_start) where household_id is not null;

-- A household week has no targets: each member's are their own.
alter table public.meal_plans
  alter column kcal_target drop not null,
  alter column protein_target_g drop not null,
  alter column carbs_target_g drop not null,
  alter column fat_target_g drop not null,
  alter column fibre_target_g drop not null,
  add constraint meal_plans_targets_check check (
    (household_id is null) = (kcal_target is not null)
    and (kcal_target is null) = (protein_target_g is null)
    and (kcal_target is null) = (carbs_target_g is null)
    and (kcal_target is null) = (fat_target_g is null)
    and (kcal_target is null) = (fibre_target_g is null)
  );

-- ---------------------------------------------------------------------------
-- plan_items: who eats each serving
-- ---------------------------------------------------------------------------

alter table public.plan_items
  add column eater_id uuid references auth.users (id) on delete cascade;
update public.plan_items set eater_id = user_id;
alter table public.plan_items
  alter column eater_id set not null,
  alter column eater_id set default auth.uid();

create index plan_items_eater_idx on public.plan_items (eater_id);

create trigger meal_plans_keep_owner before update on public.meal_plans
  for each row execute function private.keep_row_owner();
create trigger plan_items_keep_owner before update on public.plan_items
  for each row execute function private.keep_row_owner();
create trigger prep_sessions_keep_owner before update on public.prep_sessions
  for each row execute function private.keep_row_owner();
create trigger prep_portions_keep_owner before update on public.prep_portions
  for each row execute function private.keep_row_owner();

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
-- Own personal rows, or rows of the caller's household. Items and portions
-- go with their plan or session; the subqueries run under RLS.

drop policy "own meal plans: select" on public.meal_plans;
drop policy "own meal plans: insert" on public.meal_plans;
drop policy "own meal plans: update" on public.meal_plans;
drop policy "own meal plans: delete" on public.meal_plans;

create policy "own or household meal plans: select" on public.meal_plans
  for select to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));
create policy "own or household meal plans: insert" on public.meal_plans
  for insert to authenticated
  with check (user_id = (select auth.uid())
              and (household_id is null
                   or private.is_household_member(household_id)));
create policy "own or household meal plans: update" on public.meal_plans
  for update to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id))
  with check ((household_id is null and user_id = (select auth.uid()))
              or private.is_household_member(household_id));
create policy "own or household meal plans: delete" on public.meal_plans
  for delete to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));

drop policy "own plan items: select" on public.plan_items;
drop policy "own plan items: insert" on public.plan_items;
drop policy "own plan items: update" on public.plan_items;
drop policy "own plan items: delete" on public.plan_items;

-- What an item may hold, given its plan: in a personal plan, the user's
-- own foods, recipes and rules, eaten by the user; in a household week, a
-- recipe of that household, eaten by a member, with no rule.
create function private.plan_item_allowed(
  plan uuid, eater uuid, food uuid, recipe uuid, rule uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.meal_plans p
    where p.id = plan
      and (
        (p.household_id is null
         and eater = (select auth.uid())
         and (food is null
              or exists (select 1 from public.foods f
                         where f.id = food and f.household_id is null))
         and (recipe is null
              or exists (select 1 from public.recipes r
                         where r.id = recipe and r.household_id is null))
         and (rule is null
              or exists (select 1 from public.meal_rules m where m.id = rule)))
        or
        (p.household_id is not null
         and food is null and rule is null
         and exists (select 1 from public.recipes r
                     where r.id = recipe and r.household_id = p.household_id)
         and exists (select 1 from public.household_members m
                     where m.household_id = p.household_id
                       and m.user_id = eater))
      )
  );
$$;

revoke execute on function private.plan_item_allowed(uuid, uuid, uuid, uuid, uuid)
  from public, anon;
grant execute on function private.plan_item_allowed(uuid, uuid, uuid, uuid, uuid)
  to authenticated;

create policy "plan items: select" on public.plan_items
  for select to authenticated
  using (exists (select 1 from public.meal_plans p where p.id = plan_id));
create policy "plan items: insert" on public.plan_items
  for insert to authenticated
  with check (user_id = (select auth.uid())
              and private.plan_item_allowed(plan_id, eater_id, food_id,
                                            recipe_id, meal_rule_id));
create policy "plan items: update" on public.plan_items
  for update to authenticated
  using (exists (select 1 from public.meal_plans p where p.id = plan_id))
  with check (private.plan_item_allowed(plan_id, eater_id, food_id,
                                        recipe_id, meal_rule_id));
create policy "plan items: delete" on public.plan_items
  for delete to authenticated
  using (exists (select 1 from public.meal_plans p where p.id = plan_id));

drop policy "own prep sessions: select" on public.prep_sessions;
drop policy "own prep sessions: insert" on public.prep_sessions;
drop policy "own prep sessions: update" on public.prep_sessions;
drop policy "own prep sessions: delete" on public.prep_sessions;

-- A session's plan and recipe have its owner: the user's own, or its
-- household's.
create function private.prep_session_allowed(
  household uuid, plan uuid, recipe uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select
    (household is null
     or private.is_household_member(household))
    and (plan is null
         or exists (select 1 from public.meal_plans p
                    where p.id = plan
                      and p.household_id is not distinct from household))
    and exists (select 1 from public.recipes r
                where r.id = recipe
                  and r.household_id is not distinct from household);
$$;

revoke execute on function private.prep_session_allowed(uuid, uuid, uuid)
  from public, anon;
grant execute on function private.prep_session_allowed(uuid, uuid, uuid)
  to authenticated;

create policy "own or household prep sessions: select" on public.prep_sessions
  for select to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));
create policy "own or household prep sessions: insert" on public.prep_sessions
  for insert to authenticated
  with check (user_id = (select auth.uid())
              and private.prep_session_allowed(household_id, plan_id,
                                               recipe_id));
create policy "own or household prep sessions: update" on public.prep_sessions
  for update to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id))
  with check (((household_id is null and user_id = (select auth.uid()))
               or private.is_household_member(household_id))
              and private.prep_session_allowed(household_id, plan_id,
                                               recipe_id));
create policy "own or household prep sessions: delete" on public.prep_sessions
  for delete to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));

drop policy "own prep portions: select" on public.prep_portions;
drop policy "own prep portions: insert" on public.prep_portions;
drop policy "own prep portions: update" on public.prep_portions;
drop policy "own prep portions: delete" on public.prep_portions;

-- A portion of a personal batch is eaten by the user; of a household
-- batch, by a member. The log entry, once eaten, must be one the caller
-- can see (their own).
create function private.prep_portion_allowed(session uuid, eater uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.prep_sessions s
    where s.id = session
      and ((s.household_id is null and eater = (select auth.uid()))
           or (s.household_id is not null
               and exists (select 1 from public.household_members m
                           where m.household_id = s.household_id
                             and m.user_id = eater)))
  );
$$;

revoke execute on function private.prep_portion_allowed(uuid, uuid)
  from public, anon;
grant execute on function private.prep_portion_allowed(uuid, uuid)
  to authenticated;

create policy "prep portions: select" on public.prep_portions
  for select to authenticated
  using (exists (select 1 from public.prep_sessions s where s.id = session_id));
create policy "prep portions: insert" on public.prep_portions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.prep_portion_allowed(session_id, eater_id)
    and (food_log_id is null
         or exists (select 1 from public.food_logs l where l.id = food_log_id))
  );
-- Any member may move a household portion (to the freezer, say); only the
-- eater can record eating it, since the log entry is theirs.
create policy "prep portions: update" on public.prep_portions
  for update to authenticated
  using (exists (select 1 from public.prep_sessions s where s.id = session_id))
  with check (
    private.prep_portion_allowed(session_id, eater_id)
    and (food_log_id is null
         or (eater_id = (select auth.uid())
             and exists (select 1 from public.food_logs l
                         where l.id = food_log_id)))
  );
create policy "prep portions: delete" on public.prep_portions
  for delete to authenticated
  using (exists (select 1 from public.prep_sessions s where s.id = session_id));

-- ---------------------------------------------------------------------------
-- save_meal_plan: the user's own plan (unchanged, but for the new unique
-- index on personal plans)
-- ---------------------------------------------------------------------------

create or replace function public.save_meal_plan(
  week_start date,
  kcal_target numeric,
  protein_target_g numeric,
  carbs_target_g numeric,
  fat_target_g numeric,
  fibre_target_g numeric,
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
     fat_target_g, fibre_target_g, notes)
  values
    (save_meal_plan.week_start, save_meal_plan.kcal_target,
     save_meal_plan.protein_target_g, save_meal_plan.carbs_target_g,
     save_meal_plan.fat_target_g, save_meal_plan.fibre_target_g,
     save_meal_plan.notes)
  on conflict (user_id, week_start) where household_id is null do update
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

-- ---------------------------------------------------------------------------
-- save_household_plan: the household's shared dishes for a week
-- ---------------------------------------------------------------------------
-- Replaces the caller's household's week and lays out its prep the same
-- way as a personal plan, with each serving's portion for its eater.
-- Batches already cooked are kept with their portions. Security invoker:
-- every row is checked by the policies above. Errors: TLH04 not in a
-- household.
--
-- items: [{"day": date, "slot": text, "recipe_id": uuid, "eater_id": uuid,
--          "amount": number, "amount_min": number, "amount_max": number,
--          "batch": int?}, ...]

create function public.save_household_plan(
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

  delete from public.plan_items i where i.plan_id = saved_id;

  insert into public.plan_items
    (plan_id, eater_id, day, slot, recipe_id, amount, amount_min, amount_max,
     batch)
  select saved_id,
         (item ->> 'eater_id')::uuid,
         (item ->> 'day')::date,
         item ->> 'slot',
         (item ->> 'recipe_id')::uuid,
         (item ->> 'amount')::numeric,
         (item ->> 'amount_min')::numeric,
         (item ->> 'amount_max')::numeric,
         (item ->> 'batch')::smallint
  from jsonb_array_elements(save_household_plan.items) as t(item);

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

revoke execute on function public.save_household_plan(date, jsonb, jsonb)
  from public, anon;
grant execute on function public.save_household_plan(date, jsonb, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- replan_plan_items: also the caller's own servings in a household week
-- ---------------------------------------------------------------------------
-- As before, but an amount may be for any item the caller eats (their own
-- plan's, or their servings in the household's), never someone else's, and
-- prep portions follow by eater too.

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
  set amount = (a ->> 'amount')::numeric
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
-- Leaving: shared plans and prep follow the household
-- ---------------------------------------------------------------------------
-- As before, plus: the household's plans, items, batches and portions the
-- leaver saved pass to the heir; the leaver's servings still to come
-- (planned items, and planned portions of batches not yet cooked) are
-- removed, and those batches resized.

create or replace function private.after_member_left()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  heir uuid;
begin
  if not exists (select 1 from public.households h where h.id = old.household_id) then
    return null;
  end if;

  select m.user_id into heir
  from public.household_members m
  where m.household_id = old.household_id
  order by (m.role = 'owner') desc, m.joined_at, m.user_id
  limit 1;

  if heir is null then
    -- Plans and batches go with the household (cascade); recipes before
    -- foods, since their ingredients hold on to the foods.
    delete from public.prep_sessions s where s.household_id = old.household_id;
    delete from public.meal_plans p where p.household_id = old.household_id;
    delete from public.recipes r where r.household_id = old.household_id;
    delete from public.foods f where f.household_id = old.household_id;
    delete from public.households h where h.id = old.household_id;
    return null;
  end if;

  update public.household_members m set role = 'owner'
  where m.household_id = old.household_id and m.user_id = heir
    and m.role <> 'owner';

  update public.foods f set user_id = heir
  where f.household_id = old.household_id and f.user_id = old.user_id;
  update public.recipes r set user_id = heir
  where r.household_id = old.household_id and r.user_id = old.user_id;
  update public.recipe_ingredients i set user_id = heir
  from public.recipes r
  where r.id = i.recipe_id and r.household_id = old.household_id
    and i.user_id = old.user_id;
  delete from public.household_invites i
  where i.household_id = old.household_id and i.user_id = old.user_id;

  -- Their servings still to come.
  delete from public.plan_items i
  using public.meal_plans p
  where p.id = i.plan_id and p.household_id = old.household_id
    and i.eater_id = old.user_id;
  delete from public.prep_portions pp
  using public.prep_sessions s
  where s.id = pp.session_id and s.household_id = old.household_id
    and s.cooked_at is null and pp.eater_id = old.user_id;
  delete from public.prep_sessions s
  where s.household_id = old.household_id and s.cooked_at is null
    and not exists (select 1 from public.prep_portions pp
                    where pp.session_id = s.id);
  update public.prep_sessions s
  set portions = totals.portions
  from (
    select pp.session_id, sum(pp.amount) as portions
    from public.prep_portions pp
    where pp.status <> 'discarded'
    group by pp.session_id
  ) as totals
  where totals.session_id = s.id
    and s.household_id = old.household_id
    and s.cooked_at is null;

  -- What they saved stays with the household.
  update public.meal_plans p set user_id = heir
  where p.household_id = old.household_id and p.user_id = old.user_id;
  update public.plan_items i set user_id = heir
  from public.meal_plans p
  where p.id = i.plan_id and p.household_id = old.household_id
    and i.user_id = old.user_id;
  update public.prep_sessions s set user_id = heir
  where s.household_id = old.household_id and s.user_id = old.user_id;
  update public.prep_portions pp set user_id = heir
  from public.prep_sessions s
  where s.id = pp.session_id and s.household_id = old.household_id
    and pp.user_id = old.user_id;
  return null;
end;
$$;
