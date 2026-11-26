-- Skipping a planned meal.
--
-- On Today, the user can take one of their own planned items out of the
-- rest of the day (eating out, not hungry) before re-planning around it.
-- The item and its prep change together, in one transaction:
--   * a portion of a batch already cooked is kept for later, as a leftover
--     with no meal (Prep shows it and the next plan places it);
--   * a portion of a batch not yet cooked is taken out, and the batch is
--     rescaled to cook only what's still planned (or dropped if nothing
--     is).
-- Only the user's own personal plan items: a household week's dishes are
-- changed in the household's week. Security invoker, so the table
-- policies still apply to every row it touches. No new table.

create function public.skip_plan_item(item_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  item public.plan_items%rowtype;
  the_portion uuid;
  the_session uuid;
  is_cooked boolean;
begin
  select i.* into item
  from public.plan_items i
  join public.meal_plans p on p.id = i.plan_id
  where i.id = skip_plan_item.item_id
    and i.eater_id = (select auth.uid())
    and p.household_id is null;
  if not found then
    raise exception 'Not one of your own planned meals'
      using errcode = '22023';
  end if;

  -- The portion this item eats, if it's from a batch.
  select p.id, s.id, s.cooked_at is not null
    into the_portion, the_session, is_cooked
  from public.prep_portions p
  join public.prep_sessions s on s.id = p.session_id
  where s.plan_id = item.plan_id
    and s.recipe_id = item.recipe_id
    and p.eater_id = item.eater_id
    and p.day = item.day
    and p.slot = item.slot
    and p.status = 'planned'
  order by p.id
  limit 1;

  delete from public.plan_items i where i.id = item.id;

  if the_portion is null then
    return;
  end if;

  if is_cooked then
    update public.prep_portions p
    set day = null, slot = null, status = 'leftover'
    where p.id = the_portion;
    return;
  end if;

  delete from public.prep_portions p where p.id = the_portion;
  delete from public.prep_sessions s
  where s.id = the_session
    and not exists (
      select 1 from public.prep_portions p where p.session_id = s.id
    );
  update public.prep_sessions s
  set portions = (
    select sum(p.amount) from public.prep_portions p
    where p.session_id = s.id and p.status <> 'discarded'
  )
  where s.id = the_session
    and exists (
      select 1 from public.prep_portions p
      where p.session_id = s.id and p.status <> 'discarded'
    );
end;
$$;

revoke execute on function public.skip_plan_item(uuid) from public, anon;
grant execute on function public.skip_plan_item(uuid) to authenticated;
