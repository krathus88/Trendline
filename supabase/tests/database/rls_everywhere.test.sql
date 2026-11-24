-- Every table in `public` holds user data, so it must have RLS enabled and
-- policies for select, insert, update and delete. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(3);

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
