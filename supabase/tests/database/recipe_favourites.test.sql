-- Favourite recipes: only recipes the user can read, each member's own,
-- invisible to everyone else, gone with the recipe, and in the export.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(11);

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

create temp table ids (name text primary key, id uuid not null);
grant select, insert on ids to authenticated;

set local role authenticated;

-- A has a recipe of their own and one in a household with B. C has one.
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select public.create_household('Flat 2', 'Alex');
insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('a1111111-1111-1111-1111-111111111111', 'Lentils', 350, 24, 50, 1.5,
   'manual');
insert into ids select 'mine', public.save_recipe(
  null, 'My dal', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 400}]'
);
insert into ids select 'shared', public.save_recipe(
  null, 'Dal', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 400}]',
  household_id => (select id from public.households)
);
select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('c1111111-1111-1111-1111-111111111111', 'Rice', 350, 7, 78, 1,
   'manual');
insert into ids select 'theirs', public.save_recipe(
  null, 'Rice', 2::smallint, null, 3::smallint, true, null,
  '[{"food_id": "c1111111-1111-1111-1111-111111111111", "raw_grams": 200}]'
);
reset role;
insert into public.household_members (household_id, user_id, display_name)
select id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bea'
from public.households;
set local role authenticated;

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select lives_ok(
  $$insert into public.recipe_favourites (recipe_id)
    select id from ids where name in ('mine', 'shared')$$,
  'A stars their own recipe and the household''s'
);
select throws_ok(
  $$insert into public.recipe_favourites (recipe_id)
    select id from ids where name = 'theirs'$$,
  '42501', null,
  'but not a recipe they can''t read'
);
select throws_ok(
  $$insert into public.recipe_favourites (user_id, recipe_id)
    select 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', id from ids
    where name = 'shared'$$,
  '42501', null,
  'nor star one for someone else'
);
select throws_ok(
  $$insert into public.recipe_favourites (recipe_id)
    select id from ids where name = 'mine'$$,
  '23505', null,
  'a recipe is starred once'
);

-- B stars the household recipe for themselves, and sees only theirs.
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select lives_ok(
  $$insert into public.recipe_favourites (recipe_id)
    select id from ids where name = 'shared'$$,
  'B stars the household recipe for themselves'
);
select is(
  (select count(*)::int from public.recipe_favourites), 1,
  'B sees only their own favourites'
);
select is(
  (select count(*)::int from public.recipe_favourites
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 0,
  'never A''s'
);
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select is(
  jsonb_array_length(public.export_my_data() -> 'recipe_favourites'), 2,
  'A''s favourites are in their export'
);
select lives_ok(
  $$delete from public.recipe_favourites
    where recipe_id = (select id from ids where name = 'mine')$$,
  'A unstars a recipe'
);
select is(
  (select count(*)::int from public.recipe_favourites), 1,
  'and it''s gone'
);

-- Deleting a recipe takes every member's favourites of it with it.
delete from public.recipes where id = (select id from ids where name = 'shared');
reset role;
select is(
  (select count(*)::int from public.recipe_favourites), 0,
  'a deleted recipe''s favourites go with it, everyone''s'
);

select * from finish();
rollback;
