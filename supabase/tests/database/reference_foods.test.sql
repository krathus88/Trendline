-- CoFID basic foods: readable and searchable when signed in, closed to
-- anon, read-only for everyone, and copyable into a user's own foods.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(23);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local');

-- ---------------------------------------------------------------------------
-- Signed out: nothing
-- ---------------------------------------------------------------------------

set local role anon;

select throws_ok(
  $$select count(*) from public.reference_foods$$,
  '42501', null,
  'anon cannot read reference foods'
);
select throws_ok(
  $$select * from public.search_reference_foods('banana')$$,
  '42501', null,
  'anon cannot search reference foods'
);

-- ---------------------------------------------------------------------------
-- Signed in: read and search, never write
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'role', 'authenticated'
  )::text,
  true
);

select cmp_ok(
  (select count(*)::int from public.reference_foods), '>', 2000,
  'signed-in users can read the CoFID foods'
);

select throws_ok(
  $$insert into public.reference_foods
      (cofid_code, name, display_name, food_group, kcal_100g, protein_100g,
       carbs_100g, fat_100g)
    values ('99-999', 'Fake', 'Fake', 'FA', 1, 1, 1, 1)$$,
  '42501', null,
  'signed-in users cannot add reference foods'
);
select throws_ok(
  $$update public.reference_foods set kcal_100g = 1$$,
  '42501', null,
  'signed-in users cannot change reference foods'
);
select throws_ok(
  $$delete from public.reference_foods$$,
  '42501', null,
  'signed-in users cannot delete reference foods'
);

select ok(
  (select display_name ilike 'banana%'
   from public.search_reference_foods('banana') limit 1),
  'search finds bananas first'
);
select ok(
  exists (select 1 from public.search_reference_foods('bananna')
          where display_name ilike 'banana%'),
  'search tolerates a typo'
);
select ok(
  exists (select 1 from public.search_reference_foods('banan')
          where display_name ilike 'banana%'),
  'search finds a half-typed word'
);
select is(
  (select count(*)::int from public.search_reference_foods('chicken breast')
   where display_name not ilike '%chicken%'),
  0,
  'every result for a two-word search matches it'
);
select cmp_ok(
  (select count(*)::int from public.search_reference_foods('rice')), '<=', 30,
  'search returns at most 30 results'
);
select is(
  (select count(*)::int from public.search_reference_foods('a')),
  0,
  'a one-letter search returns nothing'
);
select lives_ok(
  $$select * from public.search_reference_foods($q$'); drop table public.foods; --$q$)$$,
  'search treats the query as data'
);

-- ---------------------------------------------------------------------------
-- Copies in the user's own foods
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.foods
      (name, kcal_100g, protein_100g, carbs_100g, fat_100g, source,
       reference_code)
    select display_name, kcal_100g, protein_100g, carbs_100g, fat_100g,
           'cofid', cofid_code
    from public.reference_foods
    order by cofid_code
    limit 1$$,
  'a basic food can be copied into the user''s foods'
);
select throws_ok(
  $$insert into public.foods
      (name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
    values ('Banana', 95, 1.2, 20.3, 0.3, 'cofid')$$,
  '23514', null,
  'a CoFID copy needs its code'
);
select throws_ok(
  $$insert into public.foods
      (name, kcal_100g, protein_100g, carbs_100g, fat_100g, source,
       reference_code)
    values ('Banana', 95, 1.2, 20.3, 0.3, 'manual', '13-001')$$,
  '23514', null,
  'only CoFID copies have a CoFID code'
);

-- Unknown fibre is stored as null, and the macro limit still holds.
select lives_ok(
  $$insert into public.foods
      (name, kcal_100g, protein_100g, carbs_100g, fat_100g, fibre_100g, source)
    values ('Label without fibre', 50, 3.5, 4.8, 1.7, null, 'manual')$$,
  'a food can have unknown fibre'
);
select throws_ok(
  $$insert into public.foods
      (name, kcal_100g, protein_100g, carbs_100g, fat_100g, fibre_100g, source)
    values ('Impossible', 900, 50, 50, 10, null, 'manual')$$,
  '23514', null,
  'the macro limit holds when fibre is unknown'
);
select lives_ok(
  $$insert into public.food_logs
      (eaten_on, slot, food_name, grams, kcal, protein_g, carbs_g, fat_g,
       fibre_g)
    values (current_date, 'lunch', 'Label without fibre', 100, 50, 3.5, 4.8,
            1.7, null)$$,
  'a log entry can have unknown fibre'
);

-- Every reference food fits the foods table's limits.
reset role;
select is(
  (select count(*)::int from public.reference_foods
   where kcal_100g > 900
      or protein_100g + carbs_100g + fat_100g + coalesce(fibre_100g, 0) > 105
      or (sugar_100g is not null and sugar_100g > carbs_100g + 0.5)),
  0,
  'every reference food can be copied into foods'
);
select is(
  (select array_agg(distinct fibre_source order by fibre_source)
   from public.reference_foods),
  array['aoac', 'nsp', 'usda', null]::text[],
  'fibre comes from CoFID AOAC, CoFID NSP or USDA, or is unknown'
);
select cmp_ok(
  (select count(*)::int from public.reference_foods where food_group like 'Q%'),
  '>', 20,
  'alcoholic drinks are included'
);
select ok(
  exists (select 1 from public.reference_foods
          where name = 'Cumin seeds' and nutrients_source = 'usda'
            and kcal_100g > 0),
  'spices CoFID has no energy figure for come from USDA'
);

select * from finish();
rollback;
