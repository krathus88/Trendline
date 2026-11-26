-- Read-only sharing: nothing is visible until shared, viewers see only the
-- types switched on (and only the columns the view needs), can't change
-- anything, and lose access the moment a share ends or a type goes off.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(40);

-- A shares, B views, C is an outsider.
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

create temp table codes (for_whom text primary key, code text not null);
grant select on codes to authenticated;

-- What B sees of A, as counts per type.
create function pg_temp.b_sees() returns text
language sql as $$
  select format('weight %s, targets %s, plans %s',
    (select count(*) from public.shared_weigh_ins(
       'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026-01-01')),
    (select count(*) from public.shared_targets_of(
       'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
    (select count(*) from public.shared_plan_items(
       'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026-12-07')));
$$;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- A's data
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

insert into public.weigh_ins (measured_at, weight_kg, body_fat_pct)
values ('2026-12-01 07:00+00', 90.4, 25), ('2026-12-02 07:00+00', 90.1, 24.8);
insert into public.shared_targets (kcal, protein_g, carbs_g, fat_g, fibre_g)
values (2100, 160, 220, 70, 30);
insert into public.foods
  (id, name, kcal_100g, protein_100g, carbs_100g, fat_100g, source)
values
  ('a1111111-1111-1111-1111-111111111111', 'Rice', 350, 7, 78, 1, 'manual'),
  ('a2222222-2222-2222-2222-222222222222', 'Yogurt', 60, 10, 4, 0, 'manual');
select public.save_recipe(
  null, 'Rice pot', 4::smallint, null, 3::smallint, true, null,
  '[{"food_id": "a1111111-1111-1111-1111-111111111111", "raw_grams": 400}]'
);
select public.save_meal_plan(
  '2026-12-07', 2100, 160, 220, 70, 30, '[]',
  jsonb_build_array(
    jsonb_build_object('day', '2026-12-07', 'slot', 'lunch',
      'recipe_id', (select id from public.recipes), 'amount', 1.5),
    jsonb_build_object('day', '2026-12-07', 'slot', 'breakfast',
      'food_id', 'a2222222-2222-2222-2222-222222222222', 'amount', 200))
);

-- ---------------------------------------------------------------------------
-- Nothing is shared by default
-- ---------------------------------------------------------------------------

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(pg_temp.b_sees(), 'weight 0, targets 0, plans 0',
  'nothing is visible before A shares');
select is((select count(*)::int from public.shared_targets), 0,
  'B can''t read A''s published targets directly');
select throws_ok(
  $$insert into public.shares (user_id, viewer_id, owner_name, viewer_name,
      share_weight)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'A', 'B', true)$$,
  '42501', null,
  'nobody makes a share to themselves directly'
);

-- ---------------------------------------------------------------------------
-- Inviting and accepting
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select throws_ok(
  $$insert into public.share_invites (owner_name) values ('Alex')$$,
  '23514', null,
  'an invite must share something'
);
select lives_ok(
  $$insert into public.share_invites (owner_name, share_weight, share_plans)
    values ('Alex', true, true)$$,
  'A makes an invite sharing weight and plans'
);
select throws_ok(
  $$insert into public.share_invites (owner_name, share_weight, code)
    values ('Alex', true, 'AAAAAAAAAA')$$,
  '42501', null,
  'nobody picks their own code'
);
reset role;
insert into codes select 'B', code from public.share_invites;
set local role authenticated;
select throws_ok(
  $$select public.accept_share((select code from codes), 'Me')$$,
  'TLS01', null,
  'A can''t accept their own invite'
);

select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
select is((select count(*)::int from public.share_invites), 0,
  'an outsider sees no invites');
select throws_ok(
  $$select public.accept_share('ZZZZZZZZZZ', 'Cat')$$,
  'TLS02', null,
  'a wrong code shares nothing'
);

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select lives_ok(
  $$select public.accept_share(lower((select code from codes)), ' Bea ')$$,
  'B accepts the code'
);
select is(
  (select owner_name || '/' || viewer_name || '/' || share_weight::text
          || share_targets::text || share_plans::text
   from public.shares),
  'Alex/Bea/truefalsetrue',
  'B is a viewer of what the code named'
);
select throws_ok(
  $$select public.accept_share((select code from codes), 'Bea')$$,
  'TLS02', null,
  'a code works once'
);

-- ---------------------------------------------------------------------------
-- What B sees
-- ---------------------------------------------------------------------------

select is(pg_temp.b_sees(), 'weight 2, targets 0, plans 2',
  'B sees the weight and plans, not the targets');
select is(
  (select array_agg(weight_kg::text order by measured_at)
   from public.shared_weigh_ins('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                                '2026-01-01')),
  array['90.40', '90.10'],
  'weigh-ins are when and how much'
);
select is(
  (select array_agg(name || ' ' || amount::text || ' ' || kcal::text
                    order by slot)
   from public.shared_plan_items('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                                 '2026-12-07')),
  -- Rice pot: 1,400 kcal for 4 portions, 1.5 portions = 525.
  array['Yogurt 200.00 120.0', 'Rice pot 1.50 525.0'],
  'plan items come with their names, amounts and kcal'
);
select is((select count(*)::int from public.weigh_ins), 0,
  'B still can''t read A''s weigh-ins table');
select is((select count(*)::int from public.meal_plans), 0,
  'B still can''t read A''s plans table');
select is((select count(*)::int from public.recipes), 0,
  'B still can''t read A''s recipes');

select is(
  pg_temp.rows_affected($$update public.shares set share_targets = true$$),
  0,
  'a viewer can''t widen a share'
);
select throws_ok(
  $$update public.shares set viewer_name = 'Mallory'$$,
  '42501', null,
  'names can''t be changed afterwards'
);

select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
select is(
  (select count(*)::int from public.shared_weigh_ins(
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026-01-01'))
  + (select count(*)::int from public.shared_plan_items(
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026-12-07'))
  + (select count(*)::int from public.shares),
  0,
  'an outsider sees nothing'
);

-- ---------------------------------------------------------------------------
-- The owner switches types
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select is(
  pg_temp.rows_affected(
    $$update public.shares set share_targets = true, share_plans = false$$),
  1,
  'A turns targets on and plans off'
);
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(pg_temp.b_sees(), 'weight 2, targets 1, plans 0',
  'B now sees targets and no plans');
select is(
  (select kcal::int from public.shared_targets_of(
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  2100,
  'the published targets'
);

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
update public.shares set share_targets = false;
select is((select count(*)::int from public.shared_targets), 0,
  'with no share including targets, the published numbers are deleted');
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(pg_temp.b_sees(), 'weight 2, targets 0, plans 0',
  'switching a type off stops it at once');

-- ---------------------------------------------------------------------------
-- Ending a share
-- ---------------------------------------------------------------------------

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into public.shared_targets (kcal, protein_g, carbs_g, fat_g, fibre_g)
values (2100, 160, 220, 70, 30);
update public.shares set share_targets = true;

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(
  pg_temp.rows_affected($$delete from public.shares$$),
  1,
  'a viewer can stop viewing'
);
select is(pg_temp.b_sees(), 'weight 0, targets 0, plans 0',
  'and sees nothing after');
select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select is((select count(*)::int from public.shared_targets), 0,
  'the last targets share ending deletes the published numbers');

-- Again, and this time A revokes.
reset role;
with i as (
  insert into public.share_invites (user_id, owner_name, share_weight)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Alex', true)
  returning code
)
insert into codes select 'B2', code from i;
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select public.accept_share((select code from codes where for_whom = 'B2'), 'Bea');
select is(pg_temp.b_sees(), 'weight 2, targets 0, plans 0',
  'B views again');

select pg_temp.act_as('cccccccc-cccc-cccc-cccc-cccccccccccc');
select is(
  pg_temp.rows_affected($$delete from public.shares$$),
  0,
  'an outsider can''t end someone else''s share'
);

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select is(
  pg_temp.rows_affected($$delete from public.shares$$),
  1,
  'the owner revokes'
);
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select is(pg_temp.b_sees(), 'weight 0, targets 0, plans 0',
  'revoking stops access at once');

-- ---------------------------------------------------------------------------
-- Deleting accounts
-- ---------------------------------------------------------------------------

reset role;
with i as (
  insert into public.share_invites (user_id, owner_name, share_plans)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Alex', true)
  returning code
)
insert into codes select 'B3', code from i;
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select public.accept_share((select code from codes where for_whom = 'B3'), 'Bea');
reset role;
delete from auth.users where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select is((select count(*)::int from public.shares), 0,
  'deleting the viewer''s account ends their shares');
delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select is(
  (select count(*)::int from public.share_invites)
  + (select count(*)::int from public.shared_targets),
  0,
  'deleting the owner''s account removes their invites and targets'
);

-- ---------------------------------------------------------------------------
-- Signed-out users, and what signed-in ones can run
-- ---------------------------------------------------------------------------

set local role anon;
select throws_ok(
  'select * from public.shares', '42501', null,
  'anon cannot read shares'
);
select throws_ok(
  $$select public.accept_share('ZZZZZZZZZZ', 'X')$$, '42501', null,
  'anon cannot accept a share'
);
select throws_ok(
  $$select * from public.shared_weigh_ins(gen_random_uuid(), '2026-01-01')$$,
  '42501', null,
  'anon cannot call the viewer functions'
);
reset role;

select ok(
  not has_function_privilege('authenticated', 'private.can_view(uuid, text)',
                             'EXECUTE'),
  'the share check runs only inside the viewer functions'
);
select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosecdef
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  array['accept_share', 'create_household', 'delete_my_account',
        'household_food_preferences', 'household_recipe_favourites',
        'join_household',
        'shared_plan_items', 'shared_targets_of', 'shared_weigh_ins'],
  'the only security definer functions signed-in users can call'
);

select * from finish();
rollback;
