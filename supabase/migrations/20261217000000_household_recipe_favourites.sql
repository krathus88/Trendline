-- The household's combined favourite recipes, for planning its shared
-- meals.
--
-- Each member stars recipes for themselves, and members never read each
-- other's recipe_favourites rows. household_recipe_favourites() returns, for
-- each of the household's own recipes that any current member has starred,
-- how many members starred it and how many members there are: nothing about
-- who. A member's stars of their personal recipes, or of recipes from a
-- household they have left, never appear. Empty outside a household.

create function public.household_recipe_favourites()
returns table (
  recipe_id uuid,
  stars int,
  members int
)
language sql
stable
security definer
set search_path = ''
as $$
  select f.recipe_id,
         count(*)::int,
         (select count(*)::int from public.household_members x
          where x.household_id = me.household_id)
  from public.household_members me
  join public.household_members m on m.household_id = me.household_id
  join public.recipe_favourites f on f.user_id = m.user_id
  join public.recipes r on r.id = f.recipe_id
                       and r.household_id = me.household_id
  where me.user_id = (select auth.uid())
  group by me.household_id, f.recipe_id;
$$;

revoke execute on function public.household_recipe_favourites()
  from public, anon;
grant execute on function public.household_recipe_favourites()
  to authenticated;
