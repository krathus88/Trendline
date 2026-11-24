-- Tests for invite-only sign-in. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

insert into private.allowed_users (discord_id, note)
values ('123456789012345678', 'test user');

-- ---------------------------------------------------------------------------
-- Hook decisions
-- ---------------------------------------------------------------------------

select is(
  private.check_allowlist(jsonb_build_object('user', jsonb_build_object(
    'app_metadata', jsonb_build_object('provider', 'discord'),
    'user_metadata', jsonb_build_object('provider_id', '123456789012345678')
  ))),
  '{}'::jsonb,
  'allows a listed Discord ID in user_metadata.provider_id'
);

select is(
  private.check_allowlist(jsonb_build_object('user', jsonb_build_object(
    'app_metadata', jsonb_build_object('provider', 'discord'),
    'user_metadata', jsonb_build_object('sub', '123456789012345678')
  ))),
  '{}'::jsonb,
  'allows a listed Discord ID in user_metadata.sub'
);

select is(
  private.check_allowlist(jsonb_build_object('user', jsonb_build_object(
    'app_metadata', jsonb_build_object('provider', 'discord'),
    'user_metadata', '{}'::jsonb,
    'identities', jsonb_build_array(jsonb_build_object(
      'provider', 'discord',
      'provider_id', '123456789012345678'
    ))
  ))),
  '{}'::jsonb,
  'allows a listed Discord ID found only in identities'
);

select is(
  private.check_allowlist(jsonb_build_object('user', jsonb_build_object(
    'app_metadata', jsonb_build_object('provider', 'discord'),
    'user_metadata', jsonb_build_object('provider_id', '999999999999999999')
  ))) -> 'error' ->> 'message',
  'This Discord account is not on the invite list.',
  'rejects a Discord ID that is not listed'
);

select is(
  private.check_allowlist(jsonb_build_object('user', jsonb_build_object(
    'app_metadata', jsonb_build_object('provider', 'discord'),
    'user_metadata', '{}'::jsonb
  ))) -> 'error' ->> 'message',
  'This Discord account is not on the invite list.',
  'rejects a Discord sign-up with no ID (fails closed)'
);

select is(
  private.check_allowlist(jsonb_build_object('user', jsonb_build_object(
    'app_metadata', jsonb_build_object('provider', 'email'),
    'user_metadata', jsonb_build_object('provider_id', '123456789012345678')
  ))) -> 'error' ->> 'message',
  'Sign-in is only available with Discord.',
  'rejects other providers, even with a listed ID'
);

select is(
  private.check_allowlist('{}'::jsonb) -> 'error' ->> 'message',
  'Sign-in is only available with Discord.',
  'rejects an empty payload'
);

-- ---------------------------------------------------------------------------
-- Lock-down
-- ---------------------------------------------------------------------------

select ok(
  (select relrowsecurity from pg_class
   where oid = 'private.allowed_users'::regclass),
  'RLS is enabled on private.allowed_users'
);

select is(
  (select count(*)::int from pg_policies
   where schemaname = 'private'
     and ('anon' = any(roles) or 'authenticated' = any(roles)
          or 'public' = any(roles))),
  0,
  'no policies in private apply to app roles'
);

set local role anon;
select throws_ok(
  'select * from private.allowed_users',
  '42501',
  null,
  'anon cannot read the allowlist'
);
reset role;

set local role authenticated;
select throws_ok(
  'select * from private.allowed_users',
  '42501',
  null,
  'authenticated cannot read the allowlist'
);
select throws_ok(
  $$insert into private.allowed_users (discord_id) values ('111111111111111111')$$,
  '42501',
  null,
  'authenticated cannot add itself to the allowlist'
);
select throws_ok(
  $$select private.check_allowlist('{}'::jsonb)$$,
  '42501',
  null,
  'authenticated cannot call the hook function'
);
reset role;

-- The hook runs as supabase_auth_admin, which is subject to RLS (the tests
-- above run as the owner, which isn't). The test user can't switch to that
-- role, so check its permissions in the catalog instead.
select ok(
  has_function_privilege(
    'supabase_auth_admin', 'private.check_allowlist(jsonb)', 'EXECUTE'
  ),
  'supabase_auth_admin can run the hook'
);
select ok(
  has_table_privilege('supabase_auth_admin', 'private.allowed_users', 'SELECT'),
  'supabase_auth_admin can read the allowlist'
);
select ok(
  not has_table_privilege(
    'supabase_auth_admin', 'private.allowed_users', 'INSERT, UPDATE, DELETE'
  ),
  'supabase_auth_admin cannot change the allowlist'
);
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'private'
     and tablename = 'allowed_users'
     and cmd = 'SELECT'
     and roles = array['supabase_auth_admin']::name[]
     and qual = 'true'),
  1,
  'RLS lets supabase_auth_admin (and only it) read the allowlist'
);

select throws_ok(
  $$insert into private.allowed_users (discord_id) values ('not-an-id')$$,
  '23514',
  null,
  'rejects malformed Discord IDs'
);

select * from finish();
rollback;
