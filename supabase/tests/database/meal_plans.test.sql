-- Meal plans: one per week, saved whole, private, and only about the
-- user's own foods, recipes and rules. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

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
  ('11111111-1111-1111-1111-111111111111', 'Cappuccino', 40, 2, 4, 1.5,
   'manual');
select public.save_recipe(
  null, 'Stew', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 100}]'
);

create function pg_temp.items(recipe uuid) returns jsonb
language sql as $$
  select jsonb_build_array(
    jsonb_build_object('day', '2026-12-07', 'slot', 'breakfast',
      'food_id', '11111111-1111-1111-1111-111111111111', 'amount', 250),
    jsonb_build_object('day', '2026-12-07', 'slot', 'dinner',
      'recipe_id', recipe, 'amount', 1.25, 'amount_min', 0.5,
      'amount_max', 1.75, 'batch', 0),
    jsonb_build_object('day', '2026-12-08', 'slot', 'dinner',
      'recipe_id', recipe, 'amount', 1, 'locked', true, 'batch', 0)
  );
$$;

select ok(
  (select public.save_meal_plan(
     '2026-12-07', 2000, 140, 200, 65, 30, '["A note"]',
     pg_temp.items((select id from public.recipes where name = 'Stew'))
   )) is not null,
  'A can save a week''s plan'
);
select is(
  (select count(*)::int from public.plan_items), 3,
  'its items are saved'
);
select is(
  (select locked from public.plan_items where day = '2026-12-08'), true,
  'locks are kept'
);

select lives_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 1900, 140, 190, 60, 30, '[]',
      '[{"day": "2026-12-09", "slot": "snack",
         "food_id": "11111111-1111-1111-1111-111111111111", "amount": 100}]')$$,
  'saving the same week again replaces it'
);
select is(
  (select count(*)::int from public.meal_plans), 1,
  'still one plan for the week'
);
select is(
  (select count(*)::int from public.plan_items), 1,
  'with only the new items'
);

select throws_ok(
  $$select public.save_meal_plan(
      '2026-12-08', 2000, 140, 200, 65, 30, '[]', '[]')$$,
  '23514', null,
  'weeks start on a Monday'
);
select throws_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 2000, 140, 200, 65, 30, '[]',
      '[{"day": "2026-12-20", "slot": "snack",
         "food_id": "11111111-1111-1111-1111-111111111111", "amount": 100}]')$$,
  '22023', null,
  'items must fall in the plan''s week'
);
select throws_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 2000, 140, 200, 65, 30, '[]',
      jsonb_build_array(jsonb_build_object(
        'day', '2026-12-07', 'slot', 'dinner',
        'recipe_id', (select id from public.recipes where name = 'Stew'),
        'amount', 12)))$$,
  '23514', null,
  'a recipe is planned in portions (up to 10)'
);
select is(
  (select count(*)::int from public.plan_items), 1,
  'a failed save leaves the plan as it was'
);

-- ---------------------------------------------------------------------------
-- Another user
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(
  (select count(*)::int from public.meal_plans), 0,
  'B sees none of A''s plans'
);
select throws_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 2000, 140, 200, 65, 30, '[]',
      '[{"day": "2026-12-07", "slot": "snack",
         "food_id": "11111111-1111-1111-1111-111111111111", "amount": 100}]')$$,
  '42501', null,
  'B cannot plan A''s food'
);
select lives_ok(
  $$select public.save_meal_plan(
      '2026-12-07', 1800, 120, 180, 60, 30, '[]', '[]')$$,
  'B has their own plan for the same week'
);

reset role;
set local role anon;
select throws_ok(
  $$select count(*) from public.meal_plans$$,
  '42501', null,
  'anon cannot read meal plans'
);

select * from finish();
rollback;
