-- Change signals: a write tells the owner's topic (or the household's) the
-- table's name and nothing else, once per statement; each user can listen
-- only to their own topic and their household's; nobody sends from the app.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@test.local'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@test.local');

create function pg_temp.act_as(uid uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text,
    true
  );
$$;

-- Signals sent so far on [topic] about [tbl] (read as the database owner).
create function pg_temp.signals(topic text, tbl text) returns int
language sql security definer as $$
  select count(*)::int from realtime.messages m
  where m.topic = signals.topic and m.payload ->> 'table' = tbl;
$$;

-- What [uid] can read on [topic], as the Realtime server checks it when
-- they join a channel.
create function pg_temp.readable(uid uuid, topic text) returns int
language plpgsql as $$
declare
  n int;
begin
  perform pg_temp.act_as(uid);
  perform set_config('realtime.topic', topic, true);
  execute 'set local role authenticated';
  select count(*)::int into n from realtime.messages
  where realtime.messages.topic = readable.topic;
  execute 'reset role';
  return n;
end;
$$;

create temp table ids (name text primary key, id uuid not null);
grant select, insert on ids to authenticated;

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

insert into public.weigh_ins (measured_at, weight_kg, source)
values
  ('2026-11-20 07:00+00', 82, 'manual'),
  ('2026-11-21 07:00+00', 81.8, 'manual'),
  ('2026-11-22 07:00+00', 81.5, 'manual');
reset role;

select is(
  pg_temp.signals('user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'weigh_ins'),
  1,
  'three weigh-ins saved together send one signal, to their owner'
);
select is(
  (select array_agg(k order by k) from realtime.messages m,
     jsonb_object_keys(m.payload) as k
   where m.topic = 'user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  array['id', 'table'],
  'the signal says which table changed and nothing else'
);
select is(
  (select format('%s %s %s', event, private, extension) from realtime.messages
   where topic = 'user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' limit 1),
  'changed t broadcast',
  'on a private broadcast channel'
);

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
delete from public.weigh_ins where weight_kg = 82;
reset role;
select is(
  pg_temp.signals('user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'weigh_ins'),
  2,
  'deleting one sends one too'
);

-- A household recipe signals the household, not its adder's own topic.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select public.create_household('Flat 2', 'Alex');
insert into ids select 'household', id from public.households;
insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('a1111111-1111-1111-1111-111111111111', 'Lentils', 350, 24, 50, 1.5,
   'manual');
select public.save_recipe(
  null, 'Dal', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 400}]',
  household_id => (select id from ids where name = 'household')
);
reset role;
insert into public.household_members (household_id, user_id, display_name)
select id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bea' from ids
where name = 'household';

select is(
  pg_temp.signals(
    'household:' || (select id from ids where name = 'household'), 'recipes'),
  1,
  'a household recipe signals the household'
);
select is(
  pg_temp.signals('user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'recipes'),
  0,
  'not its adder''s own topic'
);

-- ---------------------------------------------------------------------------
-- Listening
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.readable('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                   'user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') > 0,
  'A hears their own topic'
);
select is(
  pg_temp.readable('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                   'user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'B never hears A''s, even in the same household'
);
select is(
  pg_temp.readable('cccccccc-cccc-cccc-cccc-cccccccccccc',
                   'user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'nor does anyone else'
);
select ok(
  pg_temp.readable('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                   'household:' || (select id from ids where name = 'household')) > 0,
  'B hears their household''s topic'
);
select is(
  pg_temp.readable('cccccccc-cccc-cccc-cccc-cccccccccccc',
                   'household:' || (select id from ids where name = 'household')),
  0,
  'someone outside it doesn''t'
);

-- ---------------------------------------------------------------------------
-- Nobody sends from the app
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
select throws_ok(
  $$insert into realtime.messages (payload, event, topic, private, extension)
    values ('{"table": "weigh_ins"}', 'changed',
            'user:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true, 'broadcast')$$,
  '42501', null,
  'the app can''t send a signal to anyone'
);
select throws_ok(
  $$select private.signal_changes()$$,
  '42501', null,
  'nor call the trigger function'
);
reset role;

-- A failing signal never fails the write: realtime.send only warns.
select lives_ok(
  $$select realtime.send('{"table": "x"}', 'changed', 'user:nobody', true)$$,
  'sending is best effort'
);

select * from finish();
rollback;
