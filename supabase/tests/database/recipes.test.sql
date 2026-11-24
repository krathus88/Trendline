-- Recipes: saved atomically, private to their owner, built only from the
-- owner's foods, and loggable without rewriting history.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(19);

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
  ('11111111-1111-1111-1111-111111111111', 'Rice', 350, 7, 78, 1, 'manual'),
  ('22222222-2222-2222-2222-222222222222', 'Chicken', 110, 24, 0, 1.5, 'manual');

-- ---------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------

select ok(
  (select public.save_recipe(
     null, ' Chicken rice ', 4::smallint, null, 3::smallint, true, null,
     '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 300},
       {"food_id": "22222222-2222-2222-2222-222222222222", "raw_grams": 600}]'
   )) is not null,
  'A can save a recipe with its ingredients'
);
select is(
  (select array_agg(i.raw_grams::int order by i.position)
   from public.recipe_ingredients i
   join public.recipes r on r.id = i.recipe_id
   where r.name = 'Chicken rice'),
  array[300, 600],
  'ingredients are saved in order, and the name is trimmed'
);

select lives_ok(
  $$select public.save_recipe(
      (select id from public.recipes where name = 'Chicken rice'),
      'Chicken rice', 5::smallint, 1650, 4::smallint, false, 'Boil, grill.',
      '[{"food_id": "22222222-2222-2222-2222-222222222222", "raw_grams": 500}]')$$,
  'A can update a recipe'
);
select is(
  (select count(*)::int from public.recipe_ingredients),
  1,
  'an update replaces the ingredients'
);
select throws_ok(
  $$select public.save_recipe(
      null, 'Empty', 4::smallint, null, 3::smallint, true, null, '[]')$$,
  '22023', null,
  'a recipe needs at least one ingredient'
);
select throws_ok(
  $$select public.save_recipe(
      null, 'Bad', 0::smallint, null, 3::smallint, true, null,
      '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 1}]')$$,
  '23514', null,
  'portions must be at least 1'
);
select throws_ok(
  $$select public.save_recipe(
      null, 'Bad', 4::smallint, 0, 3::smallint, true, null,
      '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 1}]')$$,
  '23514', null,
  'a cooked weight must be more than 0'
);
select is(
  (select count(*)::int from public.recipes where name = 'Bad'),
  0,
  'a failed save leaves no half-saved recipe'
);

-- ---------------------------------------------------------------------------
-- Logging, and what deleting does
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.food_logs
      (eaten_on, slot, recipe_id, food_name, grams, kcal, protein_g, carbs_g,
       fat_g)
    values (current_date, 'dinner',
            (select id from public.recipes where name = 'Chicken rice'),
            'Chicken rice', 330, 330, 40, 30, 4)$$,
  'A can log a portion of their recipe'
);
select throws_ok(
  $$insert into public.food_logs
      (eaten_on, slot, food_id, recipe_id, food_name, grams, kcal, protein_g,
       carbs_g, fat_g)
    values (current_date, 'dinner', '22222222-2222-2222-2222-222222222222',
            (select id from public.recipes where name = 'Chicken rice'),
            'Both', 100, 100, 1, 1, 1)$$,
  '23514', null,
  'a log entry is a food or a recipe, not both'
);
select throws_ok(
  $$delete from public.foods where id = '22222222-2222-2222-2222-222222222222'$$,
  '23503', null,
  'a food used in a recipe cannot be deleted'
);

-- ---------------------------------------------------------------------------
-- Another user
-- ---------------------------------------------------------------------------

select set_config('test.a_recipe',
  (select id::text from public.recipes where name = 'Chicken rice'), true);
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('33333333-3333-3333-3333-333333333333', 'Oats', 379, 13, 60, 7, 'manual');

select is(
  (select count(*)::int from public.recipes), 0,
  'B sees none of A''s recipes'
);
select is(
  (select count(*)::int from public.recipe_ingredients), 0,
  'B sees none of A''s ingredients'
);
select throws_ok(
  $$select public.save_recipe(
      null, 'Stolen', 1::smallint, null, 3::smallint, true, null,
      '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 100}]')$$,
  '42501', null,
  'B cannot build a recipe from A''s food'
);
select throws_ok(
  format($$select public.save_recipe(
      %L::uuid, 'Changed', 1::smallint, null, 3::smallint, true, null,
      '[{"food_id": "33333333-3333-3333-3333-333333333333", "raw_grams": 100}]')$$,
    current_setting('test.a_recipe')),
  'P0002', null,
  'B cannot change A''s recipe'
);

select throws_ok(
  format($$insert into public.food_logs
      (eaten_on, slot, recipe_id, food_name, grams, kcal, protein_g, carbs_g,
       fat_g)
    values (current_date, 'dinner', %L, 'A''s dinner', 100, 100, 1, 1, 1)$$,
    current_setting('test.a_recipe')),
  '42501', null,
  'B cannot log A''s recipe'
);
select throws_ok(
  $$insert into public.recipes (name, household_id)
    values ('Shared', gen_random_uuid())$$,
  '42501', null,
  'households are not enabled yet: household_id must stay null'
);

-- ---------------------------------------------------------------------------
-- Deleting the recipe keeps history
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
delete from public.recipes where name = 'Chicken rice';
select is(
  (select recipe_id from public.food_logs where food_name = 'Chicken rice'),
  null,
  'deleting a recipe keeps the log entry, without the link'
);

reset role;
set local role anon;
select throws_ok(
  $$select count(*) from public.recipes$$,
  '42501', null,
  'anon cannot read recipes'
);

select * from finish();
rollback;
