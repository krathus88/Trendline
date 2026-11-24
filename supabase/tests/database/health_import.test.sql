-- Health Connect import: upserts don't duplicate, deleted readings stay
-- deleted, manual deletes leave no trace, and dismissals are private.
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

-- The statement the app's upsert turns into.
create function pg_temp.import(record_id text, kg numeric) returns void
language sql as $$
  insert into public.weigh_ins (measured_at, weight_kg, source, external_id)
  values (now(), kg, 'health_connect', record_id)
  on conflict (user_id, source, external_id) do nothing;
$$;

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- ---------------------------------------------------------------------------
-- Upserts
-- ---------------------------------------------------------------------------

select lives_ok($$select pg_temp.import('hc-1', 90)$$, 'A imports a reading');
select lives_ok(
  $$select pg_temp.import('hc-1', 90)$$,
  'importing the same reading again is not an error'
);
select is(
  (select count(*)::int from public.weigh_ins where external_id = 'hc-1'),
  1,
  'the reading is stored once'
);

select lives_ok(
  $$insert into public.weigh_ins (measured_at, weight_kg) values
      (now(), 91), (now(), 91.5)$$,
  'manual weigh-ins without an external ID never conflict'
);

-- ---------------------------------------------------------------------------
-- Deleted imports stay deleted
-- ---------------------------------------------------------------------------

delete from public.weigh_ins where external_id = 'hc-1';

select is(
  (select count(*)::int from public.weigh_in_dismissals
   where external_id = 'hc-1'),
  1,
  'deleting an imported reading remembers its ID'
);

select pg_temp.import('hc-1', 90);
select is(
  (select count(*)::int from public.weigh_ins where external_id = 'hc-1'),
  0,
  'a deleted reading is not imported again'
);

select pg_temp.import('hc-2', 89);
select is(
  (select count(*)::int from public.weigh_ins where external_id = 'hc-2'),
  1,
  'other readings still import'
);

delete from public.weigh_ins where source = 'manual';
select is(
  (select count(*)::int from public.weigh_in_dismissals),
  1,
  'deleting manual weigh-ins records nothing'
);

-- ---------------------------------------------------------------------------
-- Dismissals are private
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select is(
  (select count(*)::int from public.weigh_in_dismissals),
  0,
  'B cannot see A''s dismissals'
);
select throws_ok(
  $$insert into public.weigh_in_dismissals (user_id, source, external_id)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'health_connect', 'hc-2')$$,
  '42501',
  null,
  'B cannot block A''s readings'
);

select pg_temp.import('hc-1', 70);
select is(
  (select count(*)::int from public.weigh_ins where external_id = 'hc-1'),
  1,
  'A''s dismissal does not affect B''s import of the same ID'
);

reset role;
select is(
  (select count(*)::int from public.weigh_in_dismissals
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     and external_id = 'hc-1'),
  1,
  'A still has exactly one dismissal'
);

-- ---------------------------------------------------------------------------
-- Account deletion
-- ---------------------------------------------------------------------------

select lives_ok(
  $$delete from auth.users
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'deleting an account with imported readings and dismissals works'
);

select * from finish();
rollback;
