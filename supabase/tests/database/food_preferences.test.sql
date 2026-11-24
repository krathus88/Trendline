-- Food preferences: private to their owner, one target each, one row per
-- target. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

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

select lives_ok(
  $$insert into public.food_preferences (cuisine, preference)
    values ('indian', 'like')$$,
  'A can like a cuisine'
);
select lives_ok(
  $$insert into public.food_preferences (cofid_code, cofid_name, preference)
    values ('13-888', 'Coriander leaves, fresh', 'never')$$,
  'A can never want a basic food'
);
select throws_ok(
  $$insert into public.food_preferences (cuisine, preference)
    values ('indian', 'dislike')$$,
  '23505', null,
  'one preference per cuisine'
);
select throws_ok(
  $$insert into public.food_preferences
      (cuisine, cofid_code, cofid_name, preference)
    values ('italian', '13-888', 'Coriander leaves, fresh', 'like')$$,
  '23514', null,
  'a preference has exactly one target'
);
select throws_ok(
  $$insert into public.food_preferences (preference) values ('like')$$,
  '23514', null,
  'a preference needs a target'
);
select throws_ok(
  $$insert into public.food_preferences (cuisine, preference)
    values ('martian', 'like')$$,
  '23514', null,
  'unknown cuisines are rejected'
);

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(
  (select count(*)::int from public.food_preferences), 0,
  'B sees none of A''s preferences'
);
select lives_ok(
  $$insert into public.food_preferences (cuisine, preference)
    values ('indian', 'never')$$,
  'B has their own preferences'
);

reset role;
set local role anon;
select throws_ok(
  $$select count(*) from public.food_preferences$$,
  '42501', null,
  'anon cannot read preferences'
);

select * from finish();
rollback;
