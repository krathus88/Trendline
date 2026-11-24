-- Goals, completed days and energy estimates: private to their owner, and
-- the database refuses values outside the safety limits.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

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

-- ---------------------------------------------------------------------------
-- A creates one of each
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.goals (kind, target_weight_kg, pace_mode, pace_value)
    values ('target_and_pace', 85, 'pct', 0.75)$$,
  'A sets a goal'
);
select lives_ok(
  $$insert into public.day_logs (day) values (current_date - 1)$$,
  'A marks yesterday complete'
);
select lives_ok(
  $$insert into public.energy_estimates
      (computed_on, tdee_kcal, confidence, window_days, complete_share,
       observed_kcal)
    values (current_date, 2450, 0.25, 21, 0.9, 2510)$$,
  'A stores an estimate'
);
select throws_ok(
  $$insert into public.energy_estimates
      (computed_on, tdee_kcal, confidence, window_days, complete_share,
       observed_kcal)
    values (current_date, 2400, 0.5, 21, 0.9, 2400)$$,
  '23505',
  null,
  'only one estimate per day'
);

-- ---------------------------------------------------------------------------
-- Safety limits
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.goals (kind, pace_mode, pace_value, goal_date)
    values ('pace_and_date', 'pct', 1.5, current_date + 90)$$,
  '23514',
  null,
  'a percent pace above 1% a week is refused'
);
select throws_ok(
  $$insert into public.goals (kind, target_weight_kg)
    values ('target_and_pace', 85)$$,
  '23514',
  null,
  'a goal missing one of its two values is refused'
);
select throws_ok(
  $$insert into public.goals (kind, pace_mode, pace_value, goal_date)
    values ('pace_and_date', 'kg', -0.5, current_date + 90)$$,
  '23514',
  null,
  'a negative pace (a gain plan) is refused'
);
select throws_ok(
  $$insert into public.energy_estimates
      (computed_on, tdee_kcal, confidence, window_days, complete_share,
       observed_kcal)
    values (current_date - 7, 500, 0.25, 21, 0.9, 500)$$,
  '23514',
  null,
  'an impossible estimate is refused'
);
select throws_ok(
  $$insert into public.energy_estimates
      (computed_on, tdee_kcal, confidence, window_days, complete_share,
       observed_kcal)
    values (current_date - 7, 2400, 0.25, 21, 0.5, 2400)$$,
  '23514',
  null,
  'an estimate from a mostly unlogged window is refused'
);
select throws_ok(
  $$insert into public.day_logs (day) values (current_date + 10)$$,
  '23514',
  null,
  'a future day cannot be marked complete'
);
select lives_ok(
  $$insert into public.goals (kind) values ('maintain')$$,
  'maintenance needs no values'
);

-- ---------------------------------------------------------------------------
-- B sees and touches none of it
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select is(
  (select count(*)::int from public.goals)
  + (select count(*)::int from public.day_logs)
  + (select count(*)::int from public.energy_estimates),
  0,
  'B sees none of A''s goals, days or estimates'
);
select throws_ok(
  $$insert into public.day_logs (user_id, day)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 2)$$,
  '42501',
  null,
  'B cannot mark A''s days complete'
);
update public.goals set pace_value = 0;
delete from public.energy_estimates;

reset role;
select is(
  (select pace_value from public.goals
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     and kind = 'target_and_pace'),
  0.75::numeric,
  'B cannot change A''s goal'
);
select is(
  (select count(*)::int from public.energy_estimates),
  1,
  'B cannot delete A''s estimates'
);

-- ---------------------------------------------------------------------------
-- Signed out and account deletion
-- ---------------------------------------------------------------------------

set local role anon;
select throws_ok(
  $$select count(*) from public.goals$$,
  '42501',
  null,
  'signed-out users cannot read goals'
);

reset role;
delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select is(
  (select count(*)::int from public.goals)
  + (select count(*)::int from public.day_logs)
  + (select count(*)::int from public.energy_estimates),
  0,
  'deleting the account deletes its goals, days and estimates'
);

select * from finish();
rollback;
