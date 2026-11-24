-- Meal prep: sessions and portions laid out from a saved plan's batches,
-- cooked sessions kept on re-saving, and everything private.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@test.local');

create function pg_temp.act_as(uid uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text,
    true
  );
$$;

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('11111111-1111-1111-1111-111111111111', 'Chicken', 106, 24, 0, 1.5,
   'manual');
-- Keeps 3 days in the fridge.
select public.save_recipe(
  null, 'Stew', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 600}]'
);

-- Stew at dinner Monday to Wednesday (batch 0), Stew again at lunch on
-- Friday and Saturday (batch 1), and a snack that isn't prepped.
create function pg_temp.items() returns jsonb
language sql as $$
  select jsonb_build_array(
    jsonb_build_object('day', '2026-12-07', 'slot', 'dinner',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1.25, 'batch', 0),
    jsonb_build_object('day', '2026-12-08', 'slot', 'dinner',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1, 'batch', 0),
    jsonb_build_object('day', '2026-12-09', 'slot', 'dinner',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 0.75, 'batch', 0),
    jsonb_build_object('day', '2026-12-11', 'slot', 'lunch',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1, 'batch', 1),
    jsonb_build_object('day', '2026-12-12', 'slot', 'lunch',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1, 'batch', 1),
    jsonb_build_object('day', '2026-12-07', 'slot', 'snack',
      'food_id', '11111111-1111-1111-1111-111111111111', 'amount', 100)
  );
$$;

select lives_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 2000, 140, 200, 65, 30, '[]', pg_temp.items())$$,
  'saving a plan lays out its prep'
);
select is(
  (select count(*)::int from public.prep_sessions), 2,
  'one session per batch'
);
select is(
  (select portions from public.prep_sessions where cook_on = '2026-12-07'),
  3.00::numeric,
  'scaled to the portions the batch eats, cooked on its first day'
);
select is(
  (select count(*)::int from public.prep_portions), 5,
  'one portion per planned serving; foods aren''t prepped'
);
select is(
  (select array_agg(use_by order by day) from public.prep_portions p
   join public.prep_sessions s on s.id = p.session_id
   where s.cook_on = '2026-12-07'),
  array['2026-12-10', '2026-12-10', '2026-12-10']::date[],
  'eaten by the cook day + the recipe''s fridge days'
);
select ok(
  (select bool_and(storage = 'fridge' and status = 'planned'
                   and eater_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
   from public.prep_portions),
  'in the fridge, planned, for the user'
);

-- Cook the first batch, then save the plan again.
select lives_ok(
  $$update public.prep_sessions
    set cooked_at = now(), cooked_weight_g = 1450
    where cook_on = '2026-12-07'$$,
  'a session can be marked cooked with its weight'
);
select throws_ok(
  $$update public.prep_sessions set cooked_weight_g = 900
    where cook_on = '2026-12-11'$$,
  '23514', null,
  'a weight needs the session marked cooked'
);
select lives_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 2000, 140, 200, 65, 30, '[]', pg_temp.items())$$,
  'the plan can be saved again'
);
select is(
  (select count(*)::int from public.prep_sessions), 2,
  'the cooked batch isn''t laid out twice'
);
select is(
  (select count(*)::int from public.prep_portions), 5,
  'nor are its portions'
);
select is(
  (select cooked_weight_g from public.prep_sessions
   where cook_on = '2026-12-07'),
  1450.0::numeric,
  'the cooked batch is kept as it was'
);

select lives_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 2000, 140, 200, 65, 30, '[]', '[]')$$,
  'an empty plan can be saved'
);
select is(
  (select count(*)::int from public.prep_sessions), 1,
  'sessions not yet cooked go with the plan; cooked ones stay'
);

-- Portions change as they're eaten, frozen or thrown away.
select lives_ok(
  $$update public.prep_portions
    set storage = 'freezer', status = 'leftover', day = null, slot = null,
        use_by = '2027-03-07'
    where day = '2026-12-09'$$,
  'a portion can go in the freezer as a leftover'
);
select throws_ok(
  $$update public.prep_portions set day = null where day = '2026-12-08'$$,
  '23514', null,
  'a planned meal needs both its day and its slot'
);
select throws_ok(
  $$update public.prep_portions
    set eater_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    where day = '2026-12-08'$$,
  '42501', null,
  'portions are eaten by their owner until households exist'
);

-- ---------------------------------------------------------------------------
-- Another user
-- ---------------------------------------------------------------------------

select set_config(
  'test.stew', (select id::text from public.recipes where name = 'Stew'), true
);
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(
  (select count(*)::int from public.prep_sessions)
    + (select count(*)::int from public.prep_portions),
  0,
  'B sees none of A''s prep'
);
select throws_ok(
  $$insert into public.prep_sessions (recipe_id, cook_on, portions)
    values (current_setting('test.stew')::uuid, '2026-12-07', 2)$$,
  '42501', null,
  'B cannot prep A''s recipe'
);

reset role;
set local role anon;
select throws_ok(
  $$select count(*) from public.prep_portions$$,
  '42501', null,
  'anon cannot read prep'
);

select * from finish();
rollback;
