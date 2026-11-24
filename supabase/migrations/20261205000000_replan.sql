-- Re-planning the rest of a day: new amounts for some of a saved plan's
-- items, in one transaction, with the prep that depends on them kept in
-- step.

-- replan_plan_items: [{"id": uuid, "amount": number}, ...]
-- * Every item must be one of the caller's (RLS hides anyone else's) and
--   the new amount must be within the item's range (fixed items can't
--   change).
-- * A portion of a batch already cooked is boxed: its item can't change.
-- * Portions of batches not yet cooked follow their items, and those
--   sessions are rescaled to their portions.
-- Runs as the caller (security invoker), so every statement is subject to
-- RLS. All values are bound parameters.

create function public.replan_plan_items(amounts jsonb)
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

revoke execute on function public.replan_plan_items(jsonb) from public, anon;
grant execute on function public.replan_plan_items(jsonb) to authenticated;
