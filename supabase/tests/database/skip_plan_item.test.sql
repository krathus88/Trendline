-- Skipping a planned meal: only the user's own personal items, and prep
-- follows (a cooked portion becomes a leftover; a batch not yet cooked
-- shrinks, or goes when nothing's left of it).
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

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
-- and a snack that isn't from a batch.
select public.save_meal_plan(
  '2026-12-07', 2000, 140, 200, 65, 30, '[]',
  jsonb_build_array(
    jsonb_build_object('day', '2026-12-07', 'slot', 'dinner',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1, 'amount_min', 0.5, 'amount_max', 1.75, 'batch', 0),
    jsonb_build_object('day', '2026-12-08', 'slot', 'dinner',
      'recipe_id', (select id from public.recipes where name = 'Stew'),
      'amount', 1.25, 'amount_min', 0.5, 'amount_max', 1.75, 'batch', 0),
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

create function pg_temp.item(day date, slot text) returns uuid
language sql as $$
  select id from public.plan_items
  where plan_items.day = item.day and plan_items.slot = item.slot;
$$;

create function pg_temp.stew() returns public.prep_sessions
language sql as $$
  select * from public.prep_sessions
  where recipe_id = (select id from public.recipes where name = 'Stew');
$$;

-- The curry is cooked; the stew isn't yet.
update public.prep_sessions set cooked_at = now(), cooked_weight_g = 1200
where recipe_id = (select id from public.recipes where name = 'Curry');

-- B can't skip A's meal (it's invisible to them, so not theirs).
select set_config(
  'test.item', pg_temp.item('2026-12-07', 'dinner')::text, true
);
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select throws_ok(
  format($$select public.skip_plan_item('%s')$$, current_setting('test.item')),
  '22023', null,
  'B cannot skip A''s planned meal'
);
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select isnt(
  pg_temp.item('2026-12-07', 'dinner'), null,
  'and it''s still there'
);

-- A batch not yet cooked shrinks to what's still planned.
select lives_ok(
  format(
    $$select public.skip_plan_item('%s')$$,
    pg_temp.item('2026-12-07', 'dinner')
  ),
  'A skips Monday''s dinner'
);
select is(
  pg_temp.item('2026-12-07', 'dinner'), null,
  'the planned meal is gone'
);
select is(
  (select count(*)::int from public.prep_portions
   where session_id = (pg_temp.stew()).id),
  1,
  'so is its portion of the batch not yet cooked'
);
select is(
  (pg_temp.stew()).portions, 1.25::numeric,
  'and the batch cooks only Tuesday''s portion'
);

-- With nothing left planned from it, the batch goes.
select public.skip_plan_item(pg_temp.item('2026-12-08', 'dinner'));
select is(
  (select count(*)::int from public.prep_sessions
   where recipe_id = (select id from public.recipes where name = 'Stew')),
  0,
  'a batch with nothing left to eat is dropped'
);

-- A cooked portion is kept as a leftover.
select public.skip_plan_item(pg_temp.item('2026-12-07', 'lunch'));
select is(
  (select format('%s %s %s', status, day is null, slot is null)
   from public.prep_portions p
   join public.prep_sessions s on s.id = p.session_id
   where s.recipe_id = (select id from public.recipes where name = 'Curry')
   order by p.status
   limit 1),
  'leftover t t',
  'a cooked portion becomes a leftover with no meal'
);
select is(
  (select portions from public.prep_sessions
   where recipe_id = (select id from public.recipes where name = 'Curry')),
  2::numeric,
  'and the cooked batch keeps its size'
);

-- A planned food, from no batch.
select lives_ok(
  format(
    $$select public.skip_plan_item('%s')$$,
    pg_temp.item('2026-12-07', 'snack')
  ),
  'a planned food can be skipped'
);
select is(
  (select count(*)::int from public.plan_items), 1,
  'only Tuesday''s curry is left'
);

select throws_ok(
  $$select public.skip_plan_item('00000000-0000-0000-0000-000000000000')$$,
  '22023', null,
  'an unknown item is refused'
);

reset role;
set local role anon;
select throws_ok(
  $$select public.skip_plan_item('00000000-0000-0000-0000-000000000000')$$,
  '42501', null,
  'anon cannot skip meals'
);

select * from finish();
rollback;
