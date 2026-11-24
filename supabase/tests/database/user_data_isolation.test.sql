-- Cross-user isolation: user B can't read, change, delete or impersonate
-- anything of user A's. Also checks the range constraints and that deleting
-- an account removes its data. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

-- Two users. Inserted directly, so the sign-up hook doesn't apply.
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@test.local');

-- Act as a signed-in user for the rest of the transaction (until changed).
create function pg_temp.act_as(uid uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text,
    true
  );
$$;

-- Runs a statement and returns how many rows it changed.
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

-- ---------------------------------------------------------------------------
-- User A creates one of everything
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

select lives_ok(
  $$insert into public.profiles
      (sex, birth_year, height_cm, activity_level, disclaimer_accepted_at)
    values ('male', 1990, 180, 'light', now())$$,
  'A can create a profile'
);
select lives_ok(
  $$insert into public.weigh_ins (id, measured_at, weight_kg)
    values ('11111111-1111-1111-1111-111111111111', now(), 90)$$,
  'A can add a weigh-in'
);
select lives_ok(
  $$insert into public.foods
      (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
    values ('22222222-2222-2222-2222-222222222222', 'Oats', 379, 13, 60, 7,
            'manual')$$,
  'A can save a food'
);
select lives_ok(
  $$insert into public.food_logs
      (eaten_on, slot, food_id, food_name, grams, kcal, protein_g, carbs_g,
       fat_g)
    values (current_date, 'breakfast', '22222222-2222-2222-2222-222222222222',
            'Oats', 50, 189.5, 6.5, 30, 3.5)$$,
  'A can log their own food'
);

select is(
  (select count(*)::int from public.weigh_ins), 1, 'A sees their weigh-in'
);

-- ---------------------------------------------------------------------------
-- User B sees and touches none of it
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select is((select count(*)::int from public.profiles), 0,
  'B sees no profiles of A');
select is((select count(*)::int from public.weigh_ins), 0,
  'B sees no weigh-ins of A');
select is((select count(*)::int from public.foods), 0,
  'B sees no foods of A');
select is((select count(*)::int from public.food_logs), 0,
  'B sees no food logs of A');

select is(
  pg_temp.rows_affected($$
    update public.weigh_ins set weight_kg = 50
    where id = '11111111-1111-1111-1111-111111111111'$$),
  0,
  'B cannot update A''s weigh-in'
);
select is(
  pg_temp.rows_affected($$
    delete from public.foods
    where id = '22222222-2222-2222-2222-222222222222'$$),
  0,
  'B cannot delete A''s food'
);
select is(
  pg_temp.rows_affected('update public.profiles set height_cm = 150'),
  0,
  'B cannot update A''s profile'
);

select throws_ok(
  $$insert into public.weigh_ins (user_id, measured_at, weight_kg)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now(), 70)$$,
  '42501', null,
  'B cannot insert a weigh-in as A'
);
select throws_ok(
  $$insert into public.food_logs
      (eaten_on, slot, food_id, food_name, grams, kcal, protein_g, carbs_g,
       fat_g)
    values (current_date, 'lunch', '22222222-2222-2222-2222-222222222222',
            'Oats', 50, 189.5, 6.5, 30, 3.5)$$,
  '42501', null,
  'B cannot log a food that belongs to A'
);
select throws_ok(
  $$insert into public.foods
      (household_id, name, kcal_100g, protein_100g, carbs_100g, fat_100g,
       source)
    values (gen_random_uuid(), 'Rice', 130, 2.7, 28, 0.3, 'manual')$$,
  '42501', null,
  'households are not enabled yet: household_id must stay null'
);

select lives_ok(
  $$insert into public.weigh_ins (id, measured_at, weight_kg)
    values ('33333333-3333-3333-3333-333333333333', now(), 70)$$,
  'B can add their own weigh-in'
);
select throws_ok(
  $$update public.weigh_ins
    set user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null,
  'B cannot hand a row over to A'
);

-- ---------------------------------------------------------------------------
-- Database-level validation
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.weigh_ins (measured_at, weight_kg) values (now(), 500)$$,
  '23514', null,
  'weight above 400 kg is rejected'
);
select throws_ok(
  $$insert into public.weigh_ins (measured_at, weight_kg, body_fat_pct)
    values (now(), 80, 90)$$,
  '23514', null,
  'body fat above 75% is rejected'
);
select throws_ok(
  $$insert into public.foods
      (name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
    values ('Impossible', 500, 60, 60, 10, 'manual')$$,
  '23514', null,
  'more than 100 g of macros per 100 g is rejected'
);
select throws_ok(
  $$insert into public.foods
      (name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
    values ('Negative', 100, -1, 10, 1, 'manual')$$,
  '23514', null,
  'negative macros are rejected'
);
select throws_ok(
  $$insert into public.food_logs
      (eaten_on, slot, food_name, grams, kcal, protein_g, carbs_g, fat_g)
    values (current_date, 'brunch', 'X', 10, 1, 0, 0, 0)$$,
  '23514', null,
  'unknown meal slots are rejected'
);
select throws_ok(
  $$insert into public.weigh_ins (measured_at, weight_kg, source)
    values (now(), 80, 'health_connect')$$,
  '23514', null,
  'imported weigh-ins need their source record ID'
);

-- ---------------------------------------------------------------------------
-- Signed-out (anon) users get nothing
-- ---------------------------------------------------------------------------

reset role;
set local role anon;
select throws_ok(
  'select * from public.weigh_ins', '42501', null,
  'anon cannot read weigh-ins'
);
select throws_ok(
  'select * from public.profiles', '42501', null,
  'anon cannot read profiles'
);

-- ---------------------------------------------------------------------------
-- Deleting an account removes its data
-- ---------------------------------------------------------------------------

reset role;
delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select is(
  (select count(*)::int
   from public.weigh_ins
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'deleting A removes A''s weigh-ins'
);
select is(
  (select count(*)::int from public.food_logs
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
  + (select count(*)::int from public.foods
     where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
  + (select count(*)::int from public.profiles
     where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'deleting A removes A''s foods, logs and profile'
);

select * from finish();
rollback;
