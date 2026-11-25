-- Households: a small group that shares recipes and the foods in them.
-- Shared plans and joint prep build on this later; until then meal plans,
-- plan items, prep and meal rules stay personal.
--
-- * A user is in at most one household at a time, of up to 6 people.
-- * Joining needs an invite code from the household's owner: 10 random
--   characters, single use, valid for 2 days.
-- * Leaving (or being removed) takes effect at once: every shared row is
--   read through private.is_household_member(), which only sees current
--   members. What the leaver added stays with the household (it passes to
--   the owner, or the next member if the owner left). The last one out
--   takes the household and everything shared in it with them.
-- * Personal health data (weigh-ins, goals, estimates, food logs, day logs)
--   has no household_id and never becomes shared here.
--
-- Shared rows keep `user_id` as "added by" and set `household_id`. Every
-- member can read, change and delete them. A recipe's ingredients are
-- always foods of the same owner: the user's own for a personal recipe,
-- the same household's for a shared one. save_recipe copies foods across
-- as needed, so sharing a recipe (or copying a shared one back) is just
-- saving it with the other owner.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null
    references public.households (id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  -- What the others see. Members choose it; it isn't taken from the sign-in
  -- account, so nothing about the Discord account is shown.
  display_name text not null
    check (char_length(btrim(display_name)) between 1 and 40),
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (household_id, user_id),
  -- One household at a time.
  unique (user_id)
);

create unique index household_members_one_owner_idx
  on public.household_members (household_id) where role = 'owner';

-- Invite codes: 10 characters from a 32-letter alphabet (no 0/O, 1/I), so
-- 50 random bits from pgcrypto. 256 is a multiple of 32, so every letter is
-- equally likely.
create function private.new_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', get_byte(b.bytes, i) % 32 + 1, 1),
    '' order by i
  )
  from (select extensions.gen_random_bytes(10) as bytes) as b,
       generate_series(0, 9) as i;
$$;

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null
    references public.households (id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  code text not null unique default private.new_invite_code()
    check (code ~ '^[A-HJ-NP-Z2-9]{10}$'),
  expires_at timestamptz not null default now() + interval '2 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index household_invites_household_idx
  on public.household_invites (household_id);

create trigger households_set_updated_at before update on public.households
  for each row execute function private.set_updated_at();
create trigger household_members_set_updated_at
  before update on public.household_members
  for each row execute function private.set_updated_at();
create trigger household_invites_set_updated_at
  before update on public.household_invites
  for each row execute function private.set_updated_at();

-- The reserved household_id columns now point at households. Meal plans and
-- prep sessions still refuse a household in their policies.
alter table public.foods
  add constraint foods_household_id_fkey foreign key (household_id)
    references public.households (id) on delete cascade;
alter table public.recipes
  add constraint recipes_household_id_fkey foreign key (household_id)
    references public.households (id) on delete cascade;
alter table public.meal_plans
  add constraint meal_plans_household_id_fkey foreign key (household_id)
    references public.households (id) on delete cascade;
alter table public.prep_sessions
  add constraint prep_sessions_household_id_fkey foreign key (household_id)
    references public.households (id) on delete cascade;

create index foods_household_idx on public.foods (household_id)
  where household_id is not null;
create index recipes_household_idx on public.recipes (household_id)
  where household_id is not null;

-- A barcode is unique among one user's own foods, and among one household's.
drop index public.foods_user_barcode_idx;
create unique index foods_user_barcode_idx
  on public.foods (user_id, barcode)
  where barcode is not null and household_id is null;
create unique index foods_household_barcode_idx
  on public.foods (household_id, barcode)
  where barcode is not null and household_id is not null;

-- ---------------------------------------------------------------------------
-- Helpers for the policies
-- ---------------------------------------------------------------------------
-- Security definer so a policy on household_members can ask about
-- household_members without recursing into its own policy. Each answers
-- only about the caller.

grant usage on schema private to authenticated;

create function private.is_household_member(household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = household and m.user_id = (select auth.uid())
  );
$$;

create function private.is_household_owner(household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = household
      and m.user_id = (select auth.uid())
      and m.role = 'owner'
  );
$$;

revoke execute on function private.new_invite_code() from public, anon;
revoke execute on function private.is_household_member(uuid) from public, anon;
revoke execute on function private.is_household_owner(uuid) from public, anon;
-- Policies run as the caller, so the caller needs these. A column default
-- (the invite code) also runs as the caller.
grant execute on function private.new_invite_code() to authenticated;
grant execute on function private.is_household_member(uuid) to authenticated;
grant execute on function private.is_household_owner(uuid) to authenticated;

-- Who added a row and which household it belongs to can't be changed by the
-- app: sharing makes a copy, and only leaving hands rows on (as the owner of
-- the functions below, not an app role).
create function private.keep_row_owner()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated')
     and (new.user_id is distinct from old.user_id
          or to_jsonb(new) ->> 'household_id'
             is distinct from to_jsonb(old) ->> 'household_id') then
    raise exception 'A row''s owner can''t be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function private.keep_row_owner() from public, anon, authenticated;

create trigger foods_keep_owner before update on public.foods
  for each row execute function private.keep_row_owner();
create trigger recipes_keep_owner before update on public.recipes
  for each row execute function private.keep_row_owner();
create trigger recipe_ingredients_keep_owner
  before update on public.recipe_ingredients
  for each row execute function private.keep_row_owner();

-- ---------------------------------------------------------------------------
-- Access to the household tables
-- ---------------------------------------------------------------------------
-- Creating and joining go through the functions below (a joiner isn't a
-- member yet, so no policy could let them in). Policies that must exist
-- but have no direct use are `false`.

revoke all on table
  public.households, public.household_members, public.household_invites
  from anon, authenticated;

grant select on table public.households to authenticated;
grant update (name) on table public.households to authenticated;

grant select, delete on table public.household_members to authenticated;
grant update (display_name) on table public.household_members to authenticated;

grant select, delete on table public.household_invites to authenticated;
-- Only the household: the code, inviter and expiry come from the defaults.
grant insert (household_id) on table public.household_invites to authenticated;

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;

create policy "households: members read" on public.households
  for select to authenticated using (private.is_household_member(id));
create policy "households: created by create_household" on public.households
  for insert to authenticated with check (false);
create policy "households: owner renames" on public.households
  for update to authenticated
  using (private.is_household_owner(id))
  with check (private.is_household_owner(id));
create policy "households: dissolved when the last member leaves"
  on public.households
  for delete to authenticated using (false);

create policy "household members: members read" on public.household_members
  for select to authenticated using (private.is_household_member(household_id));
create policy "household members: added by create or join"
  on public.household_members
  for insert to authenticated with check (false);
create policy "household members: own display name"
  on public.household_members
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
-- Leave, or (the owner) remove someone.
create policy "household members: leave or remove" on public.household_members
  for delete to authenticated
  using (user_id = (select auth.uid())
         or private.is_household_owner(household_id));

create policy "household invites: members read" on public.household_invites
  for select to authenticated using (private.is_household_member(household_id));
create policy "household invites: owner invites" on public.household_invites
  for insert to authenticated
  with check (user_id = (select auth.uid())
              and private.is_household_owner(household_id));
create policy "household invites: never changed" on public.household_invites
  for update to authenticated using (false);
create policy "household invites: members withdraw" on public.household_invites
  for delete to authenticated using (private.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- create_household, join_household
-- ---------------------------------------------------------------------------
-- Security definer: they add the caller (and only the caller) to a
-- household. Errors: TLH01 already in a household, TLH02 no such invite (or
-- expired), TLH03 household full. All values are bound parameters.

create function public.create_household(name text, display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  created uuid;
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if exists (select 1 from public.household_members m where m.user_id = me) then
    raise exception 'Already in a household' using errcode = 'TLH01';
  end if;
  insert into public.households (name)
  values (btrim(create_household.name))
  returning id into created;
  insert into public.household_members (household_id, user_id, role, display_name)
  values (created, me, 'owner', btrim(create_household.display_name));
  return created;
end;
$$;

create function public.join_household(code text, display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  household uuid;
  invite uuid;
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if exists (select 1 from public.household_members m where m.user_id = me) then
    raise exception 'Already in a household' using errcode = 'TLH01';
  end if;

  select i.id, i.household_id into invite, household
  from public.household_invites i
  where i.code = upper(btrim(join_household.code)) and i.expires_at > now()
  for update;
  if invite is null then
    raise exception 'No such invite' using errcode = 'TLH02';
  end if;

  -- Serialise joins to one household so the size check holds.
  perform 1 from public.households h where h.id = household for update;
  if (select count(*) from public.household_members m
      where m.household_id = household) >= 6 then
    raise exception 'Household full' using errcode = 'TLH03';
  end if;

  insert into public.household_members (household_id, user_id, role, display_name)
  values (household, me, 'member', btrim(join_household.display_name));
  -- Single use.
  delete from public.household_invites i where i.id = invite;
  return household;
end;
$$;

revoke execute on function public.create_household(text, text) from public, anon;
revoke execute on function public.join_household(text, text) from public, anon;
grant execute on function public.create_household(text, text) to authenticated;
grant execute on function public.join_household(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Leaving
-- ---------------------------------------------------------------------------
-- After a member's row is deleted (leaving, removal, or account deletion):
-- * nobody left: the household and everything shared in it is deleted;
-- * otherwise what they added passes to the owner (or, if the owner left,
--   to the longest-standing member, who becomes the owner), and their
--   open invites are withdrawn.

create function private.after_member_left()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  heir uuid;
begin
  -- Already going (the household itself is being deleted).
  if not exists (select 1 from public.households h where h.id = old.household_id) then
    return null;
  end if;

  select m.user_id into heir
  from public.household_members m
  where m.household_id = old.household_id
  order by (m.role = 'owner') desc, m.joined_at, m.user_id
  limit 1;

  if heir is null then
    -- Recipes before foods: their ingredients hold on to the foods.
    delete from public.recipes r where r.household_id = old.household_id;
    delete from public.foods f where f.household_id = old.household_id;
    delete from public.households h where h.id = old.household_id;
    return null;
  end if;

  update public.household_members m set role = 'owner'
  where m.household_id = old.household_id and m.user_id = heir
    and m.role <> 'owner';

  update public.foods f set user_id = heir
  where f.household_id = old.household_id and f.user_id = old.user_id;
  update public.recipes r set user_id = heir
  where r.household_id = old.household_id and r.user_id = old.user_id;
  update public.recipe_ingredients i set user_id = heir
  from public.recipes r
  where r.id = i.recipe_id and r.household_id = old.household_id
    and i.user_id = old.user_id;
  delete from public.household_invites i
  where i.household_id = old.household_id and i.user_id = old.user_id;
  return null;
end;
$$;

revoke execute on function private.after_member_left() from public, anon, authenticated;

create trigger household_members_after_leave
  after delete on public.household_members
  for each row execute function private.after_member_left();

-- Deleting an account leaves its household first, so what the user shared
-- is handed on before the account's own rows cascade away (otherwise a
-- shared food they added, still used in someone else's shared recipe,
-- would block the deletion).
create function private.leave_household_before_account_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.household_members m where m.user_id = old.id;
  return old;
end;
$$;

revoke execute on function private.leave_household_before_account_deleted()
  from public, anon, authenticated;

create trigger leave_household_before_delete
  before delete on auth.users
  for each row execute function private.leave_household_before_account_deleted();

-- ---------------------------------------------------------------------------
-- foods and recipes: own, or shared with the caller's household
-- ---------------------------------------------------------------------------

drop policy "own foods: select" on public.foods;
drop policy "own foods: insert" on public.foods;
drop policy "own foods: update" on public.foods;
drop policy "own foods: delete" on public.foods;

create policy "own or household foods: select" on public.foods
  for select to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));
create policy "own or household foods: insert" on public.foods
  for insert to authenticated
  with check (user_id = (select auth.uid())
              and (household_id is null
                   or private.is_household_member(household_id)));
create policy "own or household foods: update" on public.foods
  for update to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id))
  with check ((household_id is null and user_id = (select auth.uid()))
              or private.is_household_member(household_id));
create policy "own or household foods: delete" on public.foods
  for delete to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));

drop policy "own recipes: select" on public.recipes;
drop policy "own recipes: insert" on public.recipes;
drop policy "own recipes: update" on public.recipes;
drop policy "own recipes: delete" on public.recipes;

create policy "own or household recipes: select" on public.recipes
  for select to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));
create policy "own or household recipes: insert" on public.recipes
  for insert to authenticated
  with check (user_id = (select auth.uid())
              and (household_id is null
                   or private.is_household_member(household_id)));
create policy "own or household recipes: update" on public.recipes
  for update to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id))
  with check ((household_id is null and user_id = (select auth.uid()))
              or private.is_household_member(household_id));
create policy "own or household recipes: delete" on public.recipes
  for delete to authenticated
  using ((household_id is null and user_id = (select auth.uid()))
         or private.is_household_member(household_id));

-- Ingredients go with their recipe: visible, changeable and removable by
-- whoever can see the recipe. The food must have the recipe's owner (the
-- user's own for a personal recipe, the same household's for a shared one).
-- The subqueries run under RLS.
drop policy "own recipe ingredients: select" on public.recipe_ingredients;
drop policy "own recipe ingredients: insert" on public.recipe_ingredients;
drop policy "own recipe ingredients: update" on public.recipe_ingredients;
drop policy "own recipe ingredients: delete" on public.recipe_ingredients;

create policy "recipe ingredients: select" on public.recipe_ingredients
  for select to authenticated
  using (exists (select 1 from public.recipes r where r.id = recipe_id));
create policy "recipe ingredients: insert" on public.recipe_ingredients
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.recipes r
      join public.foods f on f.id = food_id
      where r.id = recipe_id
        and f.household_id is not distinct from r.household_id
    )
  );
create policy "recipe ingredients: update" on public.recipe_ingredients
  for update to authenticated
  using (exists (select 1 from public.recipes r where r.id = recipe_id))
  with check (
    exists (
      select 1 from public.recipes r
      join public.foods f on f.id = food_id
      where r.id = recipe_id
        and f.household_id is not distinct from r.household_id
    )
  );
create policy "recipe ingredients: delete" on public.recipe_ingredients
  for delete to authenticated
  using (exists (select 1 from public.recipes r where r.id = recipe_id));

-- Food log entries may now point at a shared food or recipe too (the
-- existing policies check it's visible). The entry itself stays personal,
-- with its own snapshot, so leaving the household changes nothing logged.

-- ---------------------------------------------------------------------------
-- Rules, plans and prep stay personal for now
-- ---------------------------------------------------------------------------
-- Their policies only checked the food or recipe was visible, which now
-- includes shared ones. Restrict them to the user's own until shared plans
-- exist.

drop policy "own meal rules: insert" on public.meal_rules;
drop policy "own meal rules: update" on public.meal_rules;
create policy "own meal rules: insert" on public.meal_rules
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f
                    where f.id = food_id and f.household_id is null))
    and (recipe_id is null
         or exists (select 1 from public.recipes r
                    where r.id = recipe_id and r.household_id is null))
  );
create policy "own meal rules: update" on public.meal_rules
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f
                    where f.id = food_id and f.household_id is null))
    and (recipe_id is null
         or exists (select 1 from public.recipes r
                    where r.id = recipe_id and r.household_id is null))
  );

drop policy "own plan items: insert" on public.plan_items;
drop policy "own plan items: update" on public.plan_items;
create policy "own plan items: insert" on public.plan_items
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.meal_plans p where p.id = plan_id)
    and (food_id is null
         or exists (select 1 from public.foods f
                    where f.id = food_id and f.household_id is null))
    and (recipe_id is null
         or exists (select 1 from public.recipes r
                    where r.id = recipe_id and r.household_id is null))
    and (meal_rule_id is null
         or exists (select 1 from public.meal_rules m where m.id = meal_rule_id))
  );
create policy "own plan items: update" on public.plan_items
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.meal_plans p where p.id = plan_id)
    and (food_id is null
         or exists (select 1 from public.foods f
                    where f.id = food_id and f.household_id is null))
    and (recipe_id is null
         or exists (select 1 from public.recipes r
                    where r.id = recipe_id and r.household_id is null))
    and (meal_rule_id is null
         or exists (select 1 from public.meal_rules m where m.id = meal_rule_id))
  );

drop policy "own prep sessions: insert" on public.prep_sessions;
drop policy "own prep sessions: update" on public.prep_sessions;
create policy "own prep sessions: insert" on public.prep_sessions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and household_id is null
    and (plan_id is null
         or exists (select 1 from public.meal_plans p where p.id = plan_id))
    and exists (select 1 from public.recipes r
                where r.id = recipe_id and r.household_id is null)
  );
create policy "own prep sessions: update" on public.prep_sessions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and household_id is null
    and (plan_id is null
         or exists (select 1 from public.meal_plans p where p.id = plan_id))
    and exists (select 1 from public.recipes r
                where r.id = recipe_id and r.household_id is null)
  );

-- ---------------------------------------------------------------------------
-- Copying foods between owners
-- ---------------------------------------------------------------------------
-- private.food_for(food, household): the given food if it already belongs
-- to the target owner (the household, or the caller's own foods when
-- household is null); else a matching copy the target already has (same
-- barcode; same basic food; or, for a manual food, same name, brand and
-- nutrition); else a new copy. Security invoker: the caller must be able
-- to see the food and write to the target, under RLS.

create function private.food_for(food uuid, household uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  f public.foods;
  match uuid;
begin
  select * into f from public.foods x where x.id = food;
  if f.id is null then
    -- Someone else's food is invisible: refused like any other RLS check.
    raise exception 'Food not found' using errcode = '42501';
  end if;
  if f.household_id is not distinct from household
     and (household is not null or f.user_id = (select auth.uid())) then
    return f.id;
  end if;

  select g.id into match
  from public.foods g
  where g.household_id is not distinct from household
    and (household is not null or g.user_id = (select auth.uid()))
    and (
      (f.barcode is not null and g.barcode = f.barcode)
      or (f.reference_code is not null
          and g.reference_code = f.reference_code and g.name = f.name)
      or (f.barcode is null and f.reference_code is null
          and g.barcode is null and g.reference_code is null
          and g.source = f.source
          and g.name = f.name and g.brand is not distinct from f.brand
          and g.kcal_100g = f.kcal_100g and g.protein_100g = f.protein_100g
          and g.carbs_100g = f.carbs_100g and g.fat_100g = f.fat_100g
          and g.fibre_100g is not distinct from f.fibre_100g)
    )
  order by g.created_at, g.id
  limit 1;
  if match is not null then
    return match;
  end if;

  insert into public.foods
    (household_id, barcode, name, brand, kcal_100g, protein_100g, carbs_100g,
     fat_100g, fibre_100g, sugar_100g, salt_100g, serving_g, source,
     reference_code)
  values
    (household, f.barcode, f.name, f.brand, f.kcal_100g, f.protein_100g,
     f.carbs_100g, f.fat_100g, f.fibre_100g, f.sugar_100g, f.salt_100g,
     f.serving_g, f.source, f.reference_code)
  returning id into match;
  return match;
end;
$$;

revoke execute on function private.food_for(uuid, uuid) from public, anon;
grant execute on function private.food_for(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- save_recipe: can create a shared recipe, and copies foods across
-- ---------------------------------------------------------------------------
-- As before, plus:
-- * household_id (used when creating): the household the new recipe is
--   shared with, or null for the user's own. Kept on updates.
-- * Each ingredient's food is swapped for the recipe owner's copy of it
--   (made if needed), so sharing a recipe is saving a copy with the
--   household, and copying a shared recipe back is saving it with no
--   household.

drop function public.save_recipe(
  uuid, text, smallint, numeric, smallint, boolean, text, jsonb, text, text,
  smallint, numeric
);

create function public.save_recipe(
  recipe_id uuid,
  name text,
  portions smallint,
  cooked_weight_g numeric,
  fridge_days smallint,
  freezable boolean,
  method text,
  -- [{"food_id": uuid, "raw_grams": number}, ...] in order
  ingredients jsonb,
  origin text default 'user',
  source_id text default null,
  source_version smallint default null,
  estimated_cooked_weight_g numeric default null,
  household_id uuid default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved_id uuid;
  owner_household uuid;
  owned jsonb;
begin
  if jsonb_typeof(ingredients) is distinct from 'array'
     or jsonb_array_length(ingredients) = 0 then
    raise exception 'A recipe needs at least one ingredient'
      using errcode = '22023';
  end if;
  if jsonb_array_length(ingredients) > 200 then
    raise exception 'Too many ingredients' using errcode = '22023';
  end if;

  if recipe_id is null then
    insert into public.recipes as r
      (household_id, name, portions, cooked_weight_g, fridge_days, freezable,
       method, origin, source_id, source_version, estimated_cooked_weight_g)
    values
      (save_recipe.household_id, btrim(save_recipe.name),
       save_recipe.portions, save_recipe.cooked_weight_g,
       save_recipe.fridge_days, save_recipe.freezable, save_recipe.method,
       save_recipe.origin, save_recipe.source_id, save_recipe.source_version,
       save_recipe.estimated_cooked_weight_g)
    returning r.id, r.household_id into saved_id, owner_household;
  else
    update public.recipes r
    set name = btrim(save_recipe.name),
        portions = save_recipe.portions,
        cooked_weight_g = save_recipe.cooked_weight_g,
        fridge_days = save_recipe.fridge_days,
        freezable = save_recipe.freezable,
        method = save_recipe.method
    where r.id = save_recipe.recipe_id
    returning r.id, r.household_id into saved_id, owner_household;
    if saved_id is null then
      raise exception 'Recipe not found' using errcode = 'P0002';
    end if;
    delete from public.recipe_ingredients i where i.recipe_id = saved_id;
  end if;

  -- Swap in the owner's foods first, in a statement of its own: copies made
  -- here must be visible to the ingredients' policy check below.
  select jsonb_agg(
           jsonb_build_object(
             'food_id', private.food_for((item ->> 'food_id')::uuid,
                                         owner_household),
             'raw_grams', item -> 'raw_grams')
           order by ordinality)
  into owned
  from jsonb_array_elements(ingredients) with ordinality as t(item, ordinality);

  insert into public.recipe_ingredients (recipe_id, food_id, raw_grams, position)
  select saved_id,
         (item ->> 'food_id')::uuid,
         (item ->> 'raw_grams')::numeric,
         (ordinality - 1)::smallint
  from jsonb_array_elements(owned) with ordinality as t(item, ordinality);

  return saved_id;
end;
$$;

revoke execute on function public.save_recipe(
  uuid, text, smallint, numeric, smallint, boolean, text, jsonb, text, text,
  smallint, numeric, uuid
) from public, anon;
grant execute on function public.save_recipe(
  uuid, text, smallint, numeric, smallint, boolean, text, jsonb, text, text,
  smallint, numeric, uuid
) to authenticated;
