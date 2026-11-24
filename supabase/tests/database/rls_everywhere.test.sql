-- Every table in `public` holds user data, so it must have RLS enabled and
-- policies for select, insert, update and delete. The one exception is
-- shared read-only reference data, listed here by name: it must still have
-- RLS on, and is checked to be read-only below and in reference_foods.test.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

-- Tables in `public` with RLS turned off.
select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind in ('r', 'p')
     and not c.relrowsecurity),
  null,
  'every public table has RLS enabled'
);

-- Tables in `public` missing a policy for at least one command. A policy
-- `for all` counts for every command.
select is(
  -- Note: the required command is named `required_cmd`, not `cmd`, because
  -- pg_policies has its own `cmd` column and would silently shadow it.
  (select array_agg(
     t.relname || ' (' || r.required_cmd || ')'
     order by t.relname, r.required_cmd
   )
   from (
     select c.relname::text as relname
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and c.relname not in ('reference_foods')
   ) t
   cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE'])
     as r(required_cmd)
   where not exists (
     select 1 from pg_policies p
     where p.schemaname = 'public'
       and p.tablename = t.relname
       and p.cmd in (r.required_cmd, 'ALL')
   )),
  null,
  'every public table has select, insert, update and delete policies'
);

-- The reference data exceptions: readable when signed in, never writable by
-- an app role, and no write policies.
select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('reference_foods')
     and (
       has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE')
       or has_table_privilege('authenticated', c.oid, 'INSERT, UPDATE, DELETE')
       or not has_table_privilege('authenticated', c.oid, 'SELECT')
       or exists (
         select 1 from pg_policies p
         where p.schemaname = 'public' and p.tablename = c.relname
           and p.cmd <> 'SELECT'
       )
     )),
  null,
  'reference tables are read-only for signed-in users and closed to anon'
);

-- Tables in `private` hold admin-only data (such as the allowlist) and must
-- never be reachable by app roles.
select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'private'
     and c.relkind in ('r', 'p')
     and (
       not c.relrowsecurity
       or has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE')
       or has_table_privilege(
         'authenticated', c.oid, 'SELECT, INSERT, UPDATE, DELETE'
       )
     )),
  null,
  'no private table is exposed to app roles or missing RLS'
);

select * from finish();
rollback;
