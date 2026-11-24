-- Day schedules and meal rules: private, sane, and only about the user's
-- own foods and recipes. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

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

-- ---------------------------------------------------------------------------
-- Day schedules
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.day_schedules (weekday, wake_time, sleep_time)
    values (1, '07:00', '23:00')$$,
  'A can set a weekday'
);
select lives_ok(
  $$insert into public.day_schedules (weekday, wake_time, sleep_time)
    values (6, '15:00', '07:00')$$,
  'sleep can be after midnight (a night shift)'
);
select throws_ok(
  $$insert into public.day_schedules (weekday, wake_time, sleep_time)
    values (1, '08:00', '22:00')$$,
  '23505', null,
  'one schedule per weekday'
);
select throws_ok(
  $$insert into public.day_schedules (weekday, wake_time, sleep_time)
    values (2, '07:00', '12:00')$$,
  '23514', null,
  'awake under 8 hours is rejected'
);
select throws_ok(
  $$insert into public.day_schedules (weekday, wake_time, sleep_time)
    values (3, '05:00', '03:00')$$,
  '23514', null,
  'awake over 20 hours is rejected'
);
select throws_ok(
  $$insert into public.day_schedules (weekday, wake_time, sleep_time)
    values (8, '07:00', '23:00')$$,
  '23514', null,
  'weekdays run 1 to 7'
);

-- ---------------------------------------------------------------------------
-- Meal rules
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.meal_rules
      (food_id, slot, frequency, amount_min, amount_max)
    values ('11111111-1111-1111-1111-111111111111', 'breakfast', 'daily',
            250, 250)$$,
  'A can have a daily fixed-portion rule'
);
select lives_ok(
  $$insert into public.meal_rules
      (food_id, frequency, times_per_week, amount_min, amount_max)
    values ('11111111-1111-1111-1111-111111111111', 'max_per_week', 10,
            100, 300)$$,
  'any-meal rules can count up to 28 a week'
);
select throws_ok(
  $$insert into public.meal_rules
      (food_id, slot, frequency, times_per_week, amount_min, amount_max)
    values ('11111111-1111-1111-1111-111111111111', 'lunch', 'min_per_week',
            8, 100, 100)$$,
  '23514', null,
  'one meal can only happen 7 times a week'
);
select throws_ok(
  $$insert into public.meal_rules
      (food_id, frequency, amount_min, amount_max)
    values ('11111111-1111-1111-1111-111111111111', 'min_per_week', 100, 100)$$,
  '23514', null,
  'a weekly rule needs its count'
);
select throws_ok(
  $$insert into public.meal_rules
      (food_id, frequency, amount_min, amount_max)
    values ('11111111-1111-1111-1111-111111111111', 'daily', 300, 100)$$,
  '23514', null,
  'the smallest amount cannot be more than the largest'
);
select throws_ok(
  $$insert into public.meal_rules (frequency, amount_min, amount_max)
    values ('daily', 100, 100)$$,
  '23514', null,
  'a rule needs a food or a recipe'
);

-- ---------------------------------------------------------------------------
-- Another user
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select is(
  (select count(*)::int from public.day_schedules), 0,
  'B sees none of A''s schedules'
);
select is(
  (select count(*)::int from public.meal_rules), 0,
  'B sees none of A''s rules'
);
select throws_ok(
  $$insert into public.meal_rules
      (food_id, frequency, amount_min, amount_max)
    values ('11111111-1111-1111-1111-111111111111', 'daily', 100, 100)$$,
  '42501', null,
  'B cannot make a rule about A''s food'
);
select lives_ok(
  $$insert into public.day_schedules (weekday, wake_time, sleep_time)
    values (1, '06:00', '22:00')$$,
  'B has their own Monday'
);

-- Deleting the food deletes its rules.
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
delete from public.foods where id = '11111111-1111-1111-1111-111111111111';
select is(
  (select count(*)::int from public.meal_rules), 0,
  'deleting a food removes its rules'
);

reset role;
set local role anon;
select throws_ok(
  $$select count(*) from public.meal_rules$$,
  '42501', null,
  'anon cannot read meal rules'
);

select * from finish();
rollback;
