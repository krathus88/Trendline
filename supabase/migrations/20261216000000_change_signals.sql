-- Change signals between devices (M8 slice 5).
--
-- When a user's data changes, the database tells their other devices (and,
-- for household rows, the household's members) so the app can refetch,
-- instead of waiting for a pull to refresh. Through Supabase Realtime's
-- private broadcast channels, not "postgres_changes": those can't apply
-- row-level security to deletes, so every subscriber would learn the IDs of
-- other people's deleted rows.
--
-- What is sent: only the name of the table that changed, on a topic per
-- user ('user:<id>') or per household ('household:<id>'). No row data, no
-- IDs: the app reads the data itself, through its usual policies.
--
-- Who can listen: the policy below lets a signed-in user receive only their
-- own topic and their own household's. Nobody can send on these topics from
-- the app (there is no insert policy), only these triggers can.
--
-- One signal per statement and topic (statement-level triggers with
-- transition tables), so saving a whole week's plan sends one message, not
-- hundreds. realtime.send never fails the write it comes from: it catches
-- its own errors and only logs a warning.

create function private.signal_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  rows jsonb;
  topic text;
begin
  -- Only the transition tables this event has exist, so each is read in
  -- its own branch.
  if tg_op = 'INSERT' then
    select jsonb_agg(to_jsonb(r)) into rows from new_rows r;
  elsif tg_op = 'DELETE' then
    select jsonb_agg(to_jsonb(r)) into rows from old_rows r;
  else
    select jsonb_agg(j) into rows from (
      select to_jsonb(r) as j from new_rows r
      union all
      select to_jsonb(r) as j from old_rows r
    ) as both_sides;
  end if;

  for topic in
    select distinct t.topic
    from jsonb_array_elements(coalesce(rows, '[]')) as c(j)
    cross join lateral (values
      -- A household's row goes to the household; anyone else's to its
      -- owner and, where it has one, its eater.
      (case when c.j ->> 'household_id' is not null
            then 'household:' || (c.j ->> 'household_id') end),
      (case when c.j ->> 'household_id' is null
            then 'user:' || (c.j ->> 'user_id') end),
      ('user:' || (c.j ->> 'eater_id'))
    ) as t(topic)
    where t.topic is not null
  loop
    perform realtime.send(
      jsonb_build_object('table', tg_table_name),
      'changed',
      topic,
      true
    );
  end loop;
  return null;
end;
$$;

revoke execute on function private.signal_changes()
  from public, anon, authenticated;

-- A trigger with transition tables can't fire on several events, so each
-- table gets one per event.
do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'goals', 'weigh_ins', 'day_logs', 'food_logs', 'foods',
    'recipes', 'recipe_ingredients', 'recipe_favourites', 'food_preferences',
    'day_schedules', 'meal_rules', 'meal_plans', 'plan_items',
    'prep_sessions', 'prep_portions'
  ]
  loop
    execute format(
      'create trigger %I after insert on public.%I '
      'referencing new table as new_rows '
      'for each statement execute function private.signal_changes()',
      t || '_signal_insert', t);
    execute format(
      'create trigger %I after update on public.%I '
      'referencing old table as old_rows new table as new_rows '
      'for each statement execute function private.signal_changes()',
      t || '_signal_update', t);
    execute format(
      'create trigger %I after delete on public.%I '
      'referencing old table as old_rows '
      'for each statement execute function private.signal_changes()',
      t || '_signal_delete', t);
  end loop;
end;
$$;

-- Listening: own topic, and own household's.
create policy "change signals: own and household topics"
  on realtime.messages
  for select to authenticated
  using (
    extension = 'broadcast'
    and (
      realtime.topic() = 'user:' || (select auth.uid())::text
      or exists (
        select 1 from public.household_members m
        where m.user_id = (select auth.uid())
          and realtime.topic() = 'household:' || m.household_id::text
      )
    )
  );
