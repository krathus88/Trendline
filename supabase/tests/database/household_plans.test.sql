-- Household weeks and joint prep: members plan shared dishes together
-- under everyone's combined preferences, each changes only their own
-- servings (which planning again keeps), any member can cook, each eats
-- their own portions, outsiders see nothing, and leaving removes the
-- leaver's servings to come.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(40);

-- A owns the household, B is a member, C is an outsider.
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@test.local'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@test.local');

create function pg_temp.act_as(uid uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text,
    true
  );
$$;

create function pg_temp.rows_affected(statement text) returns int
language plpgsql as $$
declare
  n int;
begin
  execute statement;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- The household week's items for two dinners of the shared recipe, one
-- serving each for A and B, as save_household_plan takes them.
create function pg_temp.dinners(recipe uuid) returns jsonb
language sql as $$
  select jsonb_agg(jsonb_build_object(
    'day', d, 'slot', 'dinner', 'recipe_id', recipe, 'eater_id', e,
    'amount', 1, 'amount_min', 0.5, 'amount_max', 1.75, 'batch', 0))
  from unnest(array['2026-12-07', '2026-12-08']::date[]) as d,
       unnest(array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[]) as e;
$$;

create temp table ids (name text primary key, id uuid not null);
grant select, insert on ids to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- Setting up: a household with a shared recipe
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select public.create_household('Flat 2', 'Alex');
insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('a1111111-1111-1111-1111-111111111111', 'Lentils', 350, 24, 50, 1.5,
   'manual');
insert into ids select 'mine', public.save_recipe(
  null, 'My dal', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 400}]'
);
insert into ids select 'dal', public.save_recipe(
  null, 'Dal', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 400}]',
  household_id => (select id from public.households)
);
reset role;
insert into public.household_members (household_id, user_id, display_name)
select id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bea'
from public.households;
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Planning the household week
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.save_household_plan(
      '2026-12-07', '[]', pg_temp.dinners((select id from ids
                                           where name = 'dal')))$$,
  'A saves the household week'
);
select is(
  (select format('%s %s', household_id is not null, kcal_target is null)
   from public.meal_plans),
  't t',
  'it belongs to the household and carries nobody''s targets'
);
select is(
  (select array_agg(portions::text) from public.prep_sessions
   where household_id is not null),
  array['4.00'],
  'one batch is laid out for both eaters'
);
select is(
  (select count(*)::int from public.prep_portions
   where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  2,
  'with a portion for each of B''s servings'
);
select lives_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 2000, 150, 200, 60, 30, '[]',
      jsonb_build_array(jsonb_build_object(
        'day', '2026-12-07', 'slot', 'lunch',
        'recipe_id', (select id from ids where name = 'mine'),
        'amount', 1, 'batch', 0)))$$,
  'A''s own plan for the same week is separate'
);
select is((select count(*)::int from public.meal_plans), 2,
  'A sees both weeks');
select throws_ok(
  $$select public.skip_plan_item((
      select i.id from public.plan_items i
      join public.meal_plans p on p.id = i.plan_id
      where p.household_id is not null
        and i.eater_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      limit 1))$$,
  '22023', null,
  'a household serving can''t be skipped from one''s own day'
);

select throws_ok(
  $$select public.save_household_plan('2026-12-07', '[]',
      jsonb_build_array(jsonb_build_object(
        'day', '2026-12-07', 'slot', 'dinner',
        'recipe_id', (select id from ids where name = 'mine'),
        'eater_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'amount', 1)))$$,
  '42501', null,
  'a household week uses only the household''s recipes'
);
select throws_ok(
  $$select public.save_household_plan('2026-12-07', '[]',
      jsonb_build_array(jsonb_build_object(
        'day', '2026-12-07', 'slot', 'dinner',
        'recipe_id', (select id from ids where name = 'dal'),
        'eater_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'amount', 1)))$$,
  '42501', null,
  'servings are only for members'
);
select throws_ok(
  $$select public.save_meal_plan(
      '2026-12-14', 2000, 150, 200, 60, 30, '[]',
      jsonb_build_array(jsonb_build_object(
        'day', '2026-12-14', 'slot', 'dinner',
        'recipe_id', (select id from ids where name = 'dal'), 'amount', 1)))$$,
  '42501', null,
  'an own plan still can''t use a shared recipe'
);
select throws_ok(
  $$insert into public.meal_plans (household_id, week_start, kcal_target,
      protein_target_g, carbs_target_g, fat_target_g, fibre_target_g)
    select id, '2026-12-21', 2000, 150, 200, 60, 30 from public.households$$,
  '23514', null,
  'a household week can''t hold anyone''s targets'
);

-- ---------------------------------------------------------------------------
-- Members and outsiders
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(
  (select count(*)::int from public.meal_plans),
  1,
  'B sees the household week, not A''s own'
);
select is(
  (select count(*)::int from public.plan_items),
  4,
  'B sees everyone''s servings'
);
select is(
  (select count(*)::int from public.prep_portions),
  4,
  'and every portion of the batch'
);

select lives_ok(
  $$select public.replan_plan_items(jsonb_build_array(jsonb_build_object(
      'id', (select id from public.plan_items
             where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
               and day = '2026-12-07'),
      'amount', 1.5)))$$,
  'B fits their own serving'
);
select is(
  (select amount::text from public.prep_portions
   where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
     and day = '2026-12-07'),
  '1.50',
  'B''s portion follows'
);
select is(
  (select portions::text from public.prep_sessions),
  '4.50',
  'and the batch grows to match'
);
select throws_ok(
  $$select public.replan_plan_items(jsonb_build_array(jsonb_build_object(
      'id', (select id from public.plan_items
             where eater_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
               and day = '2026-12-07'),
      'amount', 0.5)))$$,
  '22023', null,
  'B can''t change A''s serving'
);
select is(
  pg_temp.rows_affected($$
    update public.plan_items set amount = 0.5
    where eater_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$),
  0,
  'nor by updating it directly'
);
select is(
  (select array_agg(format('%s %s', day, estimated) order by day)
   from public.plan_items
   where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  array['2026-12-07 f', '2026-12-08 t'],
  'the serving B fitted is no longer an estimate'
);

select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
select is(
  (select count(*)::int from public.meal_plans)
  + (select count(*)::int from public.plan_items)
  + (select count(*)::int from public.prep_sessions)
  + (select count(*)::int from public.prep_portions),
  0,
  'an outsider sees nothing'
);
select is(
  pg_temp.rows_affected(
    $$update public.prep_sessions set cooked_at = now(), cooked_weight_g = 1$$),
  0,
  'an outsider can''t cook the household''s batch'
);
select throws_ok(
  $$select public.save_household_plan('2026-12-07', '[]', '[]')$$,
  'TLH04', null,
  'only a member can plan a household week'
);

-- ---------------------------------------------------------------------------
-- Cooking and eating
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(
  pg_temp.rows_affected(
    $$update public.prep_sessions
      set cooked_at = now(), cooked_weight_g = 1800$$),
  1,
  'any member can mark the batch cooked'
);
select throws_ok(
  $$select public.replan_plan_items(jsonb_build_array(jsonb_build_object(
      'id', (select id from public.plan_items
             where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
               and day = '2026-12-08'),
      'amount', 1.25)))$$,
  '22023', null,
  'a cooked batch''s portions are boxed'
);

insert into public.food_logs
  (id, eaten_on, slot, recipe_id, food_name, grams, kcal, protein_g, carbs_g,
   fat_g)
select 'b9999999-9999-9999-9999-999999999999', '2026-12-07', 'dinner', id,
       'Dal', 600, 500, 30, 60, 5
from ids where name = 'dal';
select is(
  pg_temp.rows_affected($$
    update public.prep_portions
    set status = 'eaten', food_log_id = 'b9999999-9999-9999-9999-999999999999'
    where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      and day = '2026-12-07'$$),
  1,
  'B eats their own portion, linked to their log'
);
select throws_ok(
  $$update public.prep_portions
    set status = 'eaten', food_log_id = 'b9999999-9999-9999-9999-999999999999'
    where eater_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and day = '2026-12-07'$$,
  '42501', null,
  'B can''t eat A''s portion'
);
select is(
  pg_temp.rows_affected($$
    update public.prep_portions
    set storage = 'freezer', status = 'leftover', day = null, slot = null,
        use_by = '2027-03-01'
    where eater_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and day = '2026-12-08'$$),
  1,
  'B can put A''s portion in the freezer'
);
select throws_ok(
  $$update public.prep_portions
    set eater_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    where eater_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and day = '2026-12-07'$$,
  '42501', null,
  'a portion can''t go to an outsider'
);

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select lives_ok(
  $$select public.save_household_plan(
      '2026-12-07', '[]', pg_temp.dinners((select id from ids
                                           where name = 'dal')))$$,
  'the week can be planned again'
);
select is(
  (select array_agg(format('%s %s %s', day, amount, estimated) order by day)
   from public.plan_items
   where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  array['2026-12-07 1.50 f', '2026-12-08 1.00 t'],
  'planning again keeps B''s fitted serving, whatever A''s app sent'
);
select is(
  (select count(*)::int from public.prep_sessions
   where cooked_at is not null),
  1,
  'the cooked batch is kept'
);
select is(
  (select count(*)::int from public.prep_portions pp
   join public.prep_sessions s on s.id = pp.session_id
   where s.household_id is not null),
  4,
  'with its portions, and not laid out twice'
);

-- ---------------------------------------------------------------------------
-- Everyone's preferences, combined
-- ---------------------------------------------------------------------------

insert into public.food_preferences (cuisine, preference)
values ('italian', 'like'), ('indian', 'never');
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
insert into public.food_preferences (cuisine, preference)
values ('italian', 'dislike');
select is(
  (select array_agg(format('%s %s/%s/%s of %s', cuisine, likes, dislikes,
                           nevers, members) order by cuisine)
   from public.household_food_preferences()),
  array['indian 0/0/1 of 2', 'italian 1/1/0 of 2'],
  'members get the household''s counts, never whose they are'
);
select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
insert into public.food_preferences (cuisine, preference)
values ('mexican', 'never');
select is(
  (select count(*)::int from public.household_food_preferences()),
  0,
  'outside a household there''s nothing to combine'
);
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- ---------------------------------------------------------------------------
-- Leaving
-- ---------------------------------------------------------------------------

-- A week not yet cooked, then B leaves.
select public.save_household_plan(
  '2026-12-14', '[]',
  (select jsonb_agg(jsonb_set(jsonb_set(x, '{day}',
            to_jsonb(((x ->> 'day')::date + 7)::text)), '{batch}', '1'))
   from jsonb_array_elements(
     pg_temp.dinners((select id from ids where name = 'dal'))) as x)
);
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
delete from public.household_members
where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select is(
  (select count(*)::int from public.meal_plans)
  + (select count(*)::int from public.prep_sessions),
  0,
  'B loses access to the household''s weeks and batches at once'
);

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select is(
  (select count(*)::int from public.plan_items i
   join public.meal_plans p on p.id = i.plan_id
   where p.week_start = '2026-12-14'
     and i.eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  0,
  'B''s servings to come are removed'
);
select is(
  (select portions::text from public.prep_sessions
   where cook_on = '2026-12-14'),
  '2.00',
  'and the batch not yet cooked shrinks to A''s'
);
select is(
  (select count(*)::int from public.prep_portions
   where eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  2,
  'portions of the batch already cooked stay as they were'
);

delete from public.household_members
where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
reset role;
select is(
  (select count(*)::int from public.meal_plans where household_id is not null)
  + (select count(*)::int from public.prep_sessions
     where household_id is not null),
  0,
  'the last one out takes the household''s weeks and batches too'
);

select * from finish();
rollback;
