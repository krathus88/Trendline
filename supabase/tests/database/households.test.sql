-- Households: joining only by invite, members see what's shared and nothing
-- personal, outsiders see nothing, and leaving (or deleting the account)
-- removes access at once while the shared things stay with the household.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(61);

-- A owns the household, B joins, C is an outsider. D..H fill it up.
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@test.local'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@test.local'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'd@test.local'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'e@test.local'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'f@test.local'),
  ('99999999-9999-9999-9999-999999999999', 'g@test.local'),
  ('88888888-8888-8888-8888-888888888888', 'h@test.local');

create function pg_temp.act_as(uid uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text,
    true
  );
$$;

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

-- Invite codes made for the test (as the table owner), by who they're for.
create temp table codes (for_whom text primary key, code text not null);
grant select on codes to authenticated;

create function pg_temp.invite(for_whom text) returns void
language sql as $$
  with i as (
    insert into public.household_invites (household_id, user_id)
    select h.id, m.user_id
    from public.households h
    join public.household_members m
      on m.household_id = h.id and m.role = 'owner'
    returning code
  )
  insert into codes select for_whom, i.code from i;
$$;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- Creating
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('a1111111-1111-1111-1111-111111111111', 'Rice', 350, 7, 78, 1, 'manual'),
  ('a2222222-2222-2222-2222-222222222222', 'Chicken', 110, 24, 0, 1.5, 'manual');
select public.save_recipe(
  null, 'Chicken rice', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 300},
    {"food_id": "a2222222-2222-2222-2222-222222222222", "raw_grams": 600}]'
);

select ok(
  public.create_household(' Flat 2 ', ' Alex ') is not null,
  'A can create a household'
);
select is(
  (select h.name || '/' || m.display_name || '/' || m.role
   from public.households h join public.household_members m
     on m.household_id = h.id),
  'Flat 2/Alex/owner',
  'A is its owner, names trimmed'
);
select throws_ok(
  $$select public.create_household('Another', 'Alex')$$,
  'TLH01', null,
  'one household at a time'
);
select throws_ok(
  $$insert into public.households (name) values ('Direct')$$,
  '42501', null,
  'households are only created through create_household'
);

select lives_ok(
  $$insert into public.household_invites (household_id)
    select id from public.households$$,
  'the owner can make an invite'
);
select ok(
  (select code ~ '^[A-HJ-NP-Z2-9]{10}$'
          and expires_at between now() + interval '47 hours'
                             and now() + interval '49 hours'
   from public.household_invites),
  'an invite is a random 10-character code valid for 2 days'
);
select throws_ok(
  $$insert into public.household_invites (household_id, code)
    select id, 'AAAAAAAAAA' from public.households$$,
  '42501', null,
  'nobody picks their own code'
);

-- ---------------------------------------------------------------------------
-- Outsiders see nothing; joining needs a valid code
-- ---------------------------------------------------------------------------

select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
select is((select count(*)::int from public.households), 0,
  'an outsider sees no households');
select is((select count(*)::int from public.household_members), 0,
  'an outsider sees no members');
select is((select count(*)::int from public.household_invites), 0,
  'an outsider sees no invites');
select throws_ok(
  $$insert into public.household_members (household_id, display_name)
    select gen_random_uuid(), 'Sneaky'$$,
  '42501', null,
  'nobody adds themselves to a household directly'
);
select throws_ok(
  $$select public.join_household('ZZZZZZZZZZ', 'Cat')$$,
  'TLH02', null,
  'a wrong code joins nothing'
);

reset role;
update public.household_invites set expires_at = now() - interval '1 minute';
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
set local role authenticated;
select throws_ok(
  format('select public.join_household(%L, %L)',
         (select code from public.household_invites), 'Bea'),
  'TLH02', null,
  'an expired code joins nothing'
);

reset role;
select pg_temp.invite('B');
set local role authenticated;

select lives_ok(
  format('select public.join_household(%L, %L)',
         lower((select code from codes where for_whom = 'B')), ' Bea '),
  'B joins with a valid code (any case)'
);
select is(
  (select array_agg(display_name || ':' || role order by display_name)
   from public.household_members),
  array['Alex:owner', 'Bea:member'],
  'B sees the members'
);
select is(
  (select count(*)::int from public.household_invites
   where code = (select code from codes where for_whom = 'B')),
  0,
  'an invite works once'
);
select throws_ok(
  $$select public.join_household('ZZZZZZZZZZ', 'Bea')$$,
  'TLH01', null,
  'a member can''t join another household'
);
select throws_ok(
  $$insert into public.household_invites (household_id)
    select id from public.households$$,
  '42501', null,
  'only the owner makes invites'
);
select throws_ok(
  $$update public.household_members set role = 'owner'$$,
  '42501', null,
  'a member can''t make themselves owner'
);
select is(
  pg_temp.rows_affected($$
    update public.household_members set display_name = 'Mallory'
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$),
  0,
  'a member can''t rename someone else'
);
select is(
  pg_temp.rows_affected($$update public.households set name = 'Mine'$$),
  0,
  'only the owner renames the household'
);
select is((select count(*)::int from public.foods), 0,
  'B sees none of A''s own foods');
select is((select count(*)::int from public.recipes), 0,
  'B sees none of A''s own recipes');

-- ---------------------------------------------------------------------------
-- Sharing a recipe
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select ok(
  public.save_recipe(
    null, 'Chicken rice', 4::smallint, null, 3::smallint, true, null,
    '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 300},
      {"food_id": "a2222222-2222-2222-2222-222222222222", "raw_grams": 600}]',
    household_id => (select id from public.households)
  ) is not null,
  'A shares a recipe with the household'
);
select is(
  (select count(*)::int from public.foods where household_id is not null),
  2,
  'its foods are copied into the household'
);
select is(
  (select count(*)::int from public.recipe_ingredients i
   join public.recipes r on r.id = i.recipe_id
   join public.foods f on f.id = i.food_id
   where r.household_id is not null and f.household_id = r.household_id),
  2,
  'the shared recipe uses the household''s copies'
);
select is(
  (select count(*)::int from public.recipes where household_id is null),
  1,
  'A''s own recipe is untouched'
);

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(
  (select count(*)::int from public.recipes r
   join public.recipe_ingredients i on i.recipe_id = r.id
   join public.foods f on f.id = i.food_id),
  2,
  'B sees the shared recipe, its ingredients and foods'
);

insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('b1111111-1111-1111-1111-111111111111', 'Peas', 80, 5, 10, 0.5, 'manual');

select lives_ok(
  $$select public.save_recipe(
      (select id from public.recipes where household_id is not null),
      'Chicken rice and peas', 4::smallint, null, 3::smallint, true, null,
      jsonb_build_array(
        jsonb_build_object('food_id', (select i.food_id
          from public.recipe_ingredients i order by i.position limit 1),
          'raw_grams', 300),
        jsonb_build_object(
          'food_id', 'b1111111-1111-1111-1111-111111111111', 'raw_grams', 200)))$$,
  'B edits the shared recipe, adding one of their own foods'
);
select is(
  (select array_agg(f.name order by i.position)
   from public.recipe_ingredients i join public.foods f on f.id = i.food_id
   where f.household_id is not null),
  array['Rice', 'Peas'],
  'B''s food is copied into the household for it'
);
select throws_ok(
  $$insert into public.recipe_ingredients (recipe_id, food_id, raw_grams)
    select id, 'b1111111-1111-1111-1111-111111111111', 10
    from public.recipes where household_id is not null$$,
  '42501', null,
  'a shared recipe can''t use a member''s own food directly'
);
select ok(
  public.save_recipe(
    null, 'My peas', 1::smallint, null, 3::smallint, true, null,
    '[{"food_id": "b1111111-1111-1111-1111-111111111111", "raw_grams": 80}]'
  ) is not null,
  'B has a recipe of their own'
);
select throws_ok(
  $$insert into public.recipe_ingredients (recipe_id, food_id, raw_grams)
    select (select id from public.recipes where name = 'My peas'),
           (select id from public.foods
            where household_id is not null and name = 'Rice'), 10$$,
  '42501', null,
  'an own recipe can''t use a shared food directly'
);
select throws_ok(
  $$update public.foods set household_id = null
    where household_id is not null and name = 'Rice'$$,
  '42501', null,
  'a shared food can''t be taken out of the household'
);
select throws_ok(
  $$update public.recipes set user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    where household_id is not null$$,
  '42501', null,
  'who added a shared recipe can''t be changed'
);
select lives_ok(
  $$select public.save_recipe(
      null, 'Chicken rice and peas', 4::smallint, null, 3::smallint, true,
      null,
      (select jsonb_agg(jsonb_build_object(
                'food_id', i.food_id, 'raw_grams', i.raw_grams)
              order by i.position)
       from public.recipe_ingredients i
       join public.recipes r on r.id = i.recipe_id
       where r.household_id is not null))$$,
  'B copies the shared recipe into their own recipes'
);
select is(
  (select array_agg(f.name order by i.position)
   from public.recipe_ingredients i
   join public.recipes r on r.id = i.recipe_id
   join public.foods f on f.id = i.food_id
   where r.household_id is null and r.name = 'Chicken rice and peas'
     and f.household_id is null),
  array['Rice', 'Peas'],
  'the copy uses B''s own foods (reusing B''s peas)'
);
select is(
  (select count(*)::int from public.foods
   where household_id is null and name = 'Peas'),
  1,
  'no duplicate of a food B already has'
);

-- Logs may use shared things; rules and plans stay personal for now.
select lives_ok(
  $$insert into public.food_logs
      (eaten_on, slot, recipe_id, food_name, grams, kcal, protein_g, carbs_g,
       fat_g)
    select current_date, 'dinner', id, name, 300, 500, 40, 50, 10
    from public.recipes where household_id is not null$$,
  'B can log a portion of a shared recipe'
);
select throws_ok(
  $$insert into public.meal_rules (recipe_id, frequency, amount_min, amount_max)
    select id, 'daily', 1, 1 from public.recipes where household_id is not null$$,
  '42501', null,
  'a meal rule can''t use a shared recipe yet'
);

-- ---------------------------------------------------------------------------
-- Leaving and removal
-- ---------------------------------------------------------------------------

select lives_ok(
  $$delete from public.household_members
    where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$$,
  'B leaves'
);
select is(
  (select count(*)::int from public.recipes where household_id is not null)
  + (select count(*)::int from public.foods where household_id is not null)
  + (select count(*)::int from public.households),
  0,
  'B loses access at once'
);
select is(
  (select count(*)::int from public.food_logs where recipe_id is not null),
  1,
  'B''s log entry stays, with its own snapshot'
);
select is(
  (select count(*)::int from public.recipes where household_id is null),
  2,
  'B keeps their own recipes'
);

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select is(
  (select array_agg(distinct user_id::text)
   from public.foods where household_id is not null),
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'],
  'what B added stays with the household, passed to the owner'
);

-- Fill the household: A plus five more is the limit.
reset role;
select pg_temp.invite(w) from unnest(array['C', 'D', 'E', 'F', 'G', 'H']) as w;
set local role authenticated;
select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
select public.join_household((select code from codes where for_whom = 'C'), 'Cat');
select pg_temp.act_as('dddddddd-dddd-dddd-dddd-dddddddddddd');
select public.join_household((select code from codes where for_whom = 'D'), 'Dan');
select pg_temp.act_as('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');
select public.join_household((select code from codes where for_whom = 'E'), 'Eve');
select pg_temp.act_as('ffffffff-ffff-ffff-ffff-ffffffffffff');
select public.join_household((select code from codes where for_whom = 'F'), 'Fay');
select pg_temp.act_as('99999999-9999-9999-9999-999999999999');
select is(
  (select count(*)::int from public.household_members),
  0,
  'G isn''t in yet'
);
select lives_ok(
  $$select public.join_household(
      (select code from codes where for_whom = 'G'), 'Gus')$$,
  'G joins as the sixth member'
);
select pg_temp.act_as('88888888-8888-8888-8888-888888888888');
select throws_ok(
  $$select public.join_household(
      (select code from codes where for_whom = 'H'), 'Hal')$$,
  'TLH03', null,
  'a household holds at most six'
);

select pg_temp.act_as('dddddddd-dddd-dddd-dddd-dddddddddddd');
select is(
  pg_temp.rows_affected($$
    delete from public.household_members
    where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'$$),
  0,
  'a member can''t remove someone else'
);
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select is(
  pg_temp.rows_affected($$
    delete from public.household_members
    where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'$$),
  1,
  'the owner can remove a member'
);
select pg_temp.act_as('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');
select is((select count(*)::int from public.recipes), 0,
  'a removed member loses access at once');

-- ---------------------------------------------------------------------------
-- Deleting accounts
-- ---------------------------------------------------------------------------

-- C adds a food and a recipe using a food A shared, then C's account goes:
-- the household keeps both, handed to the owner.
select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
insert into public.foods
  (household_id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
select id, 'Lentils', 350, 24, 50, 1.5, 'manual' from public.households;
select public.save_recipe(
  null, 'Dal', 4::smallint, null, 3::smallint, true, null,
  (select jsonb_agg(jsonb_build_object('food_id', id, 'raw_grams', 100))
   from public.foods where name in ('Lentils', 'Rice')),
  household_id => (select id from public.households)
);

reset role;
delete from auth.users where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
select is(
  (select count(*)::int from public.recipes
   where name = 'Dal' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1,
  'deleting an account leaves its shared recipes with the household'
);

-- The owner's account goes: the longest-standing member takes over.
update public.household_members
set joined_at = now() - (case display_name when 'Dan' then 3 when 'Fay' then 2
                         else 1 end) * interval '1 hour'
where role = 'member';
delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select is(
  (select user_id::text || ':' || role from public.household_members
   where role = 'owner'),
  'dddddddd-dddd-dddd-dddd-dddddddddddd:owner',
  'when the owner goes, the longest-standing member owns the household'
);
select is(
  (select count(*)::int from public.recipes where household_id is not null
     and user_id <> 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
  0,
  'and everything shared passes to them'
);
select is(
  (select count(*)::int from public.recipes
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'the deleted owner''s own recipes are gone'
);

-- Everyone leaves: the household and what was shared in it go too.
set local role authenticated;
select pg_temp.act_as('ffffffff-ffff-ffff-ffff-ffffffffffff');
delete from public.household_members where user_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
select pg_temp.act_as('99999999-9999-9999-9999-999999999999');
delete from public.household_members where user_id = '99999999-9999-9999-9999-999999999999';
select pg_temp.act_as('dddddddd-dddd-dddd-dddd-dddddddddddd');
delete from public.household_members where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
reset role;
select is(
  (select count(*)::int from public.households)
  + (select count(*)::int from public.recipes where household_id is not null)
  + (select count(*)::int from public.foods where household_id is not null),
  0,
  'the last one out takes the household and its shared things with them'
);
select is(
  (select count(*)::int from public.food_logs where recipe_id is null),
  1,
  'log entries of a deleted shared recipe keep their snapshot'
);

-- ---------------------------------------------------------------------------
-- Signed-out users, and the private helpers
-- ---------------------------------------------------------------------------

set local role anon;
select throws_ok(
  'select * from public.households', '42501', null,
  'anon cannot read households'
);
select throws_ok(
  $$select public.join_household('ZZZZZZZZZZ', 'X')$$, '42501', null,
  'anon cannot join a household'
);
reset role;

select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and has_function_privilege('anon', p.oid, 'EXECUTE')),
  null,
  'anon can run no private function'
);
select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  array['food_for', 'is_household_member', 'is_household_owner',
        'new_invite_code'],
  'signed-in users can run only the helpers the policies need'
);

select * from finish();
rollback;
