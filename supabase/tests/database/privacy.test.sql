-- Privacy: consent records, the data export and account deletion.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@test.local');

-- A signed in with Discord and is on the invite list, as is B.
insert into auth.identities (user_id, provider, provider_id, identity_data)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'discord', '111111111111111111',
   '{"sub": "111111111111111111"}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'discord', '222222222222222222',
   '{"sub": "222222222222222222"}');
insert into private.allowed_users (discord_id, note) values
  ('111111111111111111', 'A'),
  ('222222222222222222', 'B');

create function pg_temp.act_as(uid uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text,
    true
  );
$$;

-- How many rows in public tables still belong to a user, per table.
create function pg_temp.rows_of(uid uuid) returns text[]
language plpgsql as $$
declare
  t record;
  n int;
  found text[] := '{}';
begin
  for t in
    select distinct c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
    where c.table_schema = 'public'
      and tb.table_type = 'BASE TABLE'
      and c.column_name in ('user_id', 'eater_id', 'viewer_id')
  loop
    execute format('select count(*) from public.%I where %I = $1',
                   t.table_name, t.column_name)
      into n using uid;
    if n > 0 then
      found := found || (t.table_name || '.' || t.column_name);
    end if;
  end loop;
  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- Consents
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

select lives_ok(
  $$insert into public.consents (policy_version) values (1)$$,
  'A can record consent'
);
select throws_ok(
  $$insert into public.consents (policy_version, consented_at)
    values (1, '2020-01-01')$$,
  '42501', null,
  'the app cannot backdate a consent'
);
select throws_ok(
  $$update public.consents set policy_version = 2$$,
  '42501', null,
  'a consent record is never changed'
);
select throws_ok(
  $$insert into public.consents (policy_version) values (0)$$,
  '23514', null,
  'policy versions start at 1'
);

-- A's own data, to export and then delete.
insert into public.profiles
  (sex, birth_year, height_cm, activity_level, disclaimer_accepted_at)
values ('male', 1990, 180, 'light', now());
insert into public.weigh_ins (measured_at, weight_kg) values (now(), 90);

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
insert into public.consents (policy_version) values (1);
insert into public.weigh_ins (measured_at, weight_kg) values (now(), 70);

select is(
  (select count(*)::int from public.consents),
  1,
  'B sees only their own consent'
);

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Every public table except shared reference data is in the export.
select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind in ('r', 'p')
     and c.relname not in ('reference_foods')
     and not (public.export_my_data() ? c.relname::text)),
  null,
  'the export includes every table of user data'
);
select is(
  jsonb_array_length(public.export_my_data() -> 'weigh_ins'),
  1,
  'A''s export holds A''s weigh-in only'
);
select is(
  (public.export_my_data() -> 'weigh_ins' -> 0 ->> 'weight_kg')::numeric,
  90.00,
  'with its values'
);
select is(
  jsonb_array_length(public.export_my_data() -> 'consents'),
  1,
  'and A''s consent'
);
select is(
  public.export_my_data() ->> 'user_id',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'the export says whose it is'
);

select pg_temp.act_as(null);
select throws_ok(
  $$select public.export_my_data()$$,
  '42501', null,
  'there is no export without signing in'
);

reset role;
set local role anon;
select throws_ok(
  $$select public.export_my_data()$$,
  '42501', null,
  'anon cannot call the export'
);
select throws_ok(
  $$select public.delete_my_account()$$,
  '42501', null,
  'anon cannot delete an account'
);

-- ---------------------------------------------------------------------------
-- Deletion
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

select lives_ok(
  $$select public.delete_my_account()$$,
  'A can delete their account'
);

reset role;

select is(
  (select count(*)::int from auth.users
   where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'A''s account is gone'
);
select is(
  pg_temp.rows_of('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  '{}'::text[],
  'nothing of A''s is left in any table'
);
select is(
  (select array_agg(discord_id order by discord_id) from private.allowed_users),
  array['222222222222222222'],
  'A is taken off the invite list, B is not'
);
select is(
  pg_temp.rows_of('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  array['consents.user_id', 'weigh_ins.user_id'],
  'B''s data is untouched'
);

select * from finish();
rollback;
