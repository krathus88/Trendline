-- Favourite recipes (M8 slice 2).
--
-- Each user stars the recipes they like best: their own, or their
-- household's, each member for themselves (so this table has no
-- household_id: a favourite is the member's, not the household's). The
-- planner offers favourites more often, as it does dishes with liked foods.
--
-- A favourite can only point at a recipe the user can read: the insert
-- policy checks the recipe through the recipes table's own policies. If the
-- recipe is deleted, its favourites go with it; if the user leaves the
-- household, their favourites of its recipes stay theirs but point at
-- nothing they can read, and the app ignores them.

create table public.recipe_favourites (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

create index recipe_favourites_recipe_idx
  on public.recipe_favourites (recipe_id);

revoke all on table public.recipe_favourites from anon;
grant select, insert, update, delete on table public.recipe_favourites
  to authenticated;

alter table public.recipe_favourites enable row level security;

create policy "own recipe favourites: select" on public.recipe_favourites
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own recipe favourites: insert" on public.recipe_favourites
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.recipes r where r.id = recipe_id)
  );
create policy "own recipe favourites: update" on public.recipe_favourites
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.recipes r where r.id = recipe_id)
  );
create policy "own recipe favourites: delete" on public.recipe_favourites
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- export_my_data: as before, with the caller's favourites
-- ---------------------------------------------------------------------------

create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'format', 1,
    'exported_at', now(),
    'user_id', me,
    'profiles', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.profiles t where t.user_id = me),
    'consents', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.consents t where t.user_id = me),
    'goals', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.goals t where t.user_id = me),
    'weigh_ins', (select coalesce(jsonb_agg(to_jsonb(t) order by t.measured_at), '[]')
      from public.weigh_ins t where t.user_id = me),
    'weigh_in_dismissals', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.weigh_in_dismissals t where t.user_id = me),
    'energy_estimates', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.energy_estimates t where t.user_id = me),
    'day_logs', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.day_logs t where t.user_id = me),
    'food_logs', (select coalesce(jsonb_agg(to_jsonb(t) order by t.eaten_at), '[]')
      from public.food_logs t where t.user_id = me),
    'foods', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.foods t where t.user_id = me),
    'recipes', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.recipes t where t.user_id = me),
    'recipe_ingredients', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.recipe_ingredients t where t.user_id = me),
    'recipe_favourites', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.recipe_favourites t where t.user_id = me),
    'food_preferences', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.food_preferences t where t.user_id = me),
    'day_schedules', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.day_schedules t where t.user_id = me),
    'meal_rules', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.meal_rules t where t.user_id = me),
    'meal_plans', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.meal_plans t where t.user_id = me),
    'plan_items', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.plan_items t where t.user_id = me or t.eater_id = me),
    'prep_sessions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.prep_sessions t where t.user_id = me),
    'prep_portions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.prep_portions t where t.user_id = me or t.eater_id = me),
    'households', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.households t
      where exists (select 1 from public.household_members m
                    where m.household_id = t.id and m.user_id = me)),
    'household_members', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.household_members t where t.user_id = me),
    'household_invites', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.household_invites t where t.user_id = me),
    'shares', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.shares t where t.user_id = me or t.viewer_id = me),
    'share_invites', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.share_invites t where t.user_id = me),
    'shared_targets', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.shared_targets t where t.user_id = me)
  );
end;
$$;
