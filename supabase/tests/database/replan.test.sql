-- Re-planning amounts: within each item's range, never a cooked batch's
-- boxed portion, prep kept in step, and only the user's own items.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(11);

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
select public.save_recipe(
  null, 'Stew', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 600}]'
);
select public.save_recipe(
  null, 'Curry', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "11111111-1111-1111-1111-111111111111", "raw_grams": 500}]'
);

-- Stew at dinner Monday and Tuesday, Curry at lunch Monday and Tuesday,
-- and a fixed snack.
select public.save_meal_plan(
  '2026-12-07', 2000, 140, 200, 65, 30, '[]',
  jsonb_build_array(
    jsonb_build_object('day', '2026-12-07', 'slot', 'dinner',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1, 'amount_min', 0.5, 'amount_max', 1.75, 'batch', 0),
    jsonb_build_object('day', '2026-12-08', 'slot', 'dinner',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1, 'amount_min', 0.5, 'amount_max', 1.75, 'batch', 0),
    jsonb_build_object('day', '2026-12-07', 'slot', 'lunch',
      'recipe_id', (select id from public.recipes where name = 'Curry'),
      'amount', 1, 'amount_min', 0.5, 'amount_max', 1.75, 'batch', 1),
    jsonb_build_object('day', '2026-12-08', 'slot', 'lunch',
      'recipe_id', (select id from public.recipes where name = 'Curry'),
      'amount', 1, 'amount_min', 0.5, 'amount_max', 1.75, 'batch', 1),
    jsonb_build_object('day', '2026-12-07', 'slot', 'snack',
      'food_id', '11111111-1111-1111-1111-111111111111', 'amount', 100)
  )
);

create function pg_temp.item(slot text) returns uuid
language sql as $$
  select id from public.plan_items
  where day = '2026-12-07' and plan_items.slot = item.slot;
$$;

-- The curry is cooked; the stew isn't yet.
update public.prep_sessions set cooked_at = now(), cooked_weight_g = 1200
where recipe_id = (select id from public.recipes where name = 'Curry');

select lives_ok(
  format(
    $$select public.replan_plan_items('[{"id": "%s", "amount": 0.75}]')$$,
    pg_temp.item('dinner')
  ),
  'a planned dish can be refitted within its range'
);
select is(
  (select amount from public.plan_items where id = pg_temp.item('dinner')),
  0.75::numeric,
  'the item has its new amount'
);
select is(
  (select p.amount from public.prep_portions p
   where p.day = '2026-12-07' and p.slot = 'dinner'),
  0.75::numeric,
  'its portion of a batch not yet cooked follows'
);
select is(
  (select s.portions from public.prep_sessions s
   where s.recipe_id = (select id from public.recipes where name = 'Stew')),
  1.75::numeric,
  'and the batch is rescaled to cook just that'
);

select throws_ok(
  format(
    $$select public.replan_plan_items('[{"id": "%s", "amount": 2}]')$$,
    pg_temp.item('dinner')
  ),
  '22023', null,
  'not beyond the item''s range'
);
select throws_ok(
  format(
    $$select public.replan_plan_items('[{"id": "%s", "amount": 150}]')$$,
    pg_temp.item('snack')
  ),
  '22023', null,
  'a fixed item can''t change'
);
select throws_ok(
  format(
    $$select public.replan_plan_items('[{"id": "%s", "amount": 0.5}]')$$,
    pg_temp.item('lunch')
  ),
  '22023', null,
  'a portion of a cooked batch is boxed and can''t change'
);
select lives_ok(
  format(
    $$select public.replan_plan_items(
        '[{"id": "%s", "amount": 1}, {"id": "%s", "amount": 1}]')$$,
    pg_temp.item('lunch'), pg_temp.item('dinner')
  ),
  'sending a cooked portion''s amount unchanged is fine'
);
select throws_ok(
  $$select public.replan_plan_items('{"id": 1}')$$,
  '22023', null,
  'amounts must be a list'
);

select set_config('test.item', pg_temp.item('dinner')::text, true);
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select throws_ok(
  format(
    $$select public.replan_plan_items('[{"id": "%s", "amount": 1}]')$$,
    current_setting('test.item')
  ),
  '22023', null,
  'B cannot change A''s plan'
);

reset role;
set local role anon;
select throws_ok(
  $$select public.replan_plan_items('[]')$$,
  '42501', null,
  'anon cannot re-plan'
);

select * from finish();
rollback;
