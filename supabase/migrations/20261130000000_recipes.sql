-- The user's recipes: ingredients in raw grams, a portion count and the
-- batch's cooked weight. Portions are eaten in cooked grams, so a recipe can
-- be logged by weight once its cooked weight is recorded. Before that it
-- has nutrition per portion (batch total / portions).
--
-- Same rules as every user table: user_id defaults to auth.uid() and
-- cascades on account deletion, RLS with own-row policies for
-- `authenticated`, nothing for `anon`, ranges checked here.

-- ---------------------------------------------------------------------------
-- recipes
-- ---------------------------------------------------------------------------

create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Reserved for households (shared recipes). Always null until then.
  household_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 200),
  -- Cooking steps, optional (planned for later phases).
  method text check (char_length(method) <= 10000),
  portions smallint not null default 4 check (portions between 1 and 50),
  -- The whole batch after cooking. Null until the user weighs it.
  cooked_weight_g numeric(7, 1)
    check (cooked_weight_g > 0 and cooked_weight_g <= 50000),
  -- How long it keeps in the fridge; after that, the freezer (if freezable).
  fridge_days smallint not null default 3 check (fridge_days between 0 and 7),
  freezable boolean not null default true,
  -- Where it came from: entered by the user, or copied from the app's
  -- recipe library or a dish template (which ship with the app). Library
  -- and template copies remember which one, and which version.
  origin text not null default 'user'
    check (origin in ('user', 'library', 'template')),
  source_id text check (source_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
                        and char_length(source_id) <= 80),
  source_version smallint check (source_version >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((origin = 'user') = (source_id is null)),
  check ((source_id is null) = (source_version is null))
);

create index recipes_user_name_idx on public.recipes (user_id, name);

-- ---------------------------------------------------------------------------
-- recipe_ingredients: raw grams of the user's own foods
-- ---------------------------------------------------------------------------

create table public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  -- A food used in a recipe can't be deleted until it's taken out of the
  -- recipe, so a recipe never silently loses an ingredient.
  food_id uuid not null references public.foods (id) on delete restrict,
  raw_grams numeric(6, 1) not null check (raw_grams > 0 and raw_grams < 5000),
  position smallint not null default 0 check (position between 0 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index recipe_ingredients_recipe_idx
  on public.recipe_ingredients (recipe_id, position);
create index recipe_ingredients_food_idx on public.recipe_ingredients (food_id);

-- ---------------------------------------------------------------------------
-- food_logs: a portion of a recipe can be logged
-- ---------------------------------------------------------------------------
-- The log keeps its own name and nutrition snapshot, as for foods, so
-- editing or deleting the recipe never rewrites history.

alter table public.food_logs
  add column recipe_id uuid references public.recipes (id) on delete set null,
  add constraint food_logs_one_source_check
    check (food_id is null or recipe_id is null);

create index food_logs_recipe_idx on public.food_logs (recipe_id);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

create trigger recipes_set_updated_at before update on public.recipes
  for each row execute function private.set_updated_at();
create trigger recipe_ingredients_set_updated_at
  before update on public.recipe_ingredients
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access: authenticated users, own rows only. No anon access.
-- ---------------------------------------------------------------------------

revoke all on table public.recipes, public.recipe_ingredients
  from anon;
grant select, insert, update, delete on table
  public.recipes, public.recipe_ingredients
  to authenticated;

alter table public.recipes enable row level security;
alter table public.recipe_ingredients enable row level security;

create policy "own recipes: select" on public.recipes
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own recipes: insert" on public.recipes
  for insert to authenticated
  with check (user_id = (select auth.uid()) and household_id is null);
create policy "own recipes: update" on public.recipes
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and household_id is null);
create policy "own recipes: delete" on public.recipes
  for delete to authenticated using (user_id = (select auth.uid()));

-- An ingredient may only join one of the user's own recipes and use one of
-- their own foods. The subqueries run under RLS, so another user's rows are
-- invisible and fail the check.
create policy "own recipe ingredients: select" on public.recipe_ingredients
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own recipe ingredients: insert" on public.recipe_ingredients
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.recipes r where r.id = recipe_id)
    and exists (select 1 from public.foods f where f.id = food_id)
  );
create policy "own recipe ingredients: update" on public.recipe_ingredients
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.recipes r where r.id = recipe_id)
    and exists (select 1 from public.foods f where f.id = food_id)
  );
create policy "own recipe ingredients: delete" on public.recipe_ingredients
  for delete to authenticated using (user_id = (select auth.uid()));

-- A log entry may point at the user's own food or recipe, never another's.
drop policy "own food logs: insert" on public.food_logs;
drop policy "own food logs: update" on public.food_logs;
create policy "own food logs: insert" on public.food_logs
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
    and (recipe_id is null
         or exists (select 1 from public.recipes r where r.id = recipe_id))
  );
create policy "own food logs: update" on public.food_logs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (food_id is null
         or exists (select 1 from public.foods f where f.id = food_id))
    and (recipe_id is null
         or exists (select 1 from public.recipes r where r.id = recipe_id))
  );

-- ---------------------------------------------------------------------------
-- save_recipe: a recipe and its ingredients in one transaction
-- ---------------------------------------------------------------------------
-- Creates the recipe (recipe_id null) or updates it, and replaces its
-- ingredients, so a failed save never leaves half a recipe. Origin and
-- source are set when the recipe is created and kept on updates (an edited
-- library copy still came from the library). Runs as the caller (security
-- invoker): every statement is subject to the RLS policies above. All
-- values are bound parameters.

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
  source_version smallint default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved_id uuid;
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
    insert into public.recipes
      (name, portions, cooked_weight_g, fridge_days, freezable, method,
       origin, source_id, source_version)
    values
      (btrim(save_recipe.name), save_recipe.portions,
       save_recipe.cooked_weight_g, save_recipe.fridge_days,
       save_recipe.freezable, save_recipe.method, save_recipe.origin,
       save_recipe.source_id, save_recipe.source_version)
    returning id into saved_id;
  else
    update public.recipes r
    set name = btrim(save_recipe.name),
        portions = save_recipe.portions,
        cooked_weight_g = save_recipe.cooked_weight_g,
        fridge_days = save_recipe.fridge_days,
        freezable = save_recipe.freezable,
        method = save_recipe.method
    where r.id = save_recipe.recipe_id
    returning r.id into saved_id;
    if saved_id is null then
      raise exception 'Recipe not found' using errcode = 'P0002';
    end if;
    delete from public.recipe_ingredients i where i.recipe_id = saved_id;
  end if;

  insert into public.recipe_ingredients (recipe_id, food_id, raw_grams, position)
  select saved_id,
         (item ->> 'food_id')::uuid,
         (item ->> 'raw_grams')::numeric,
         (ordinality - 1)::smallint
  from jsonb_array_elements(ingredients) with ordinality as t(item, ordinality);

  return saved_id;
end;
$$;

revoke execute on function public.save_recipe(
  uuid, text, smallint, numeric, smallint, boolean, text, jsonb, text, text,
  smallint
) from public, anon;
grant execute on function public.save_recipe(
  uuid, text, smallint, numeric, smallint, boolean, text, jsonb, text, text,
  smallint
) to authenticated;
