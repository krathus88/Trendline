-- Basic foods from CoFID (McCance and Widdowson's Composition of Foods
-- Integrated Dataset), the UK government's food composition data, published
-- under the Open Government Licence v3.0.
--
-- reference_foods is shared public reference data, not user data: it has no
-- owner and nothing about anyone in it. So unlike every other public table:
--   * RLS is on with a single select policy for `authenticated`;
--   * no app role can insert, update or delete; only migrations change it
--     (the rows come from the generated reference_foods_data migration);
--   * `anon` gets nothing.
-- Choosing a basic food copies it into the user's own foods (source
-- 'cofid'), so logs, recipes and rules only ever point at the user's foods.

create extension if not exists pg_trgm with schema extensions;

create table public.reference_foods (
  -- CoFID codes aren't unique on their own: the 2021 edition gives 13-669 to
  -- two different foods. Code and name together are.
  cofid_code text not null check (cofid_code ~ '^[0-9]{2}-[0-9]{3,4}$'),
  name text not null check (char_length(name) between 1 and 200),
  -- A friendlier name derived from CoFID's terse one, shown in the app.
  display_name text not null check (char_length(display_name) between 1 and 200),
  -- CoFID's food group code, e.g. 'FA' (fruit) or 'MAC' (beef).
  food_group text not null check (food_group ~ '^[A-Z]{1,4}$'),
  kcal_100g numeric(6, 1) not null check (kcal_100g between 0 and 900),
  protein_100g numeric(5, 1) not null check (protein_100g between 0 and 100),
  carbs_100g numeric(5, 1) not null check (carbs_100g between 0 and 100),
  fat_100g numeric(5, 1) not null check (fat_100g between 0 and 100),
  -- Null where no source has a figure (CoFID's "N": present, not measured).
  fibre_100g numeric(5, 1) check (fibre_100g between 0 and 100),
  -- Where the fibre figure comes from: CoFID's AOAC fibre ('aoac', what UK
  -- labels use), CoFID's NSP fibre scaled to AOAC ('nsp'), or USDA
  -- FoodData Central, matched by hand ('usda').
  fibre_source text check (fibre_source in ('aoac', 'nsp', 'usda')),
  sugar_100g numeric(5, 1) check (sugar_100g between 0 and 100),
  salt_100g numeric(5, 2) check (salt_100g between 0 and 100),
  -- Share of the food as bought that's edible (e.g. 0.66 for bananas in
  -- their skins). Values are per 100 g of the edible part.
  edible_proportion numeric(3, 2) check (edible_proportion > 0
                                         and edible_proportion <= 1),
  -- 'cofid', or 'usda' for the few foods CoFID gives no energy figure (most
  -- spices), whose values all come from USDA FoodData Central.
  nutrients_source text not null default 'cofid'
    check (nutrients_source in ('cofid', 'usda')),
  search_vector tsvector generated always as (
    to_tsvector('english'::regconfig, display_name || ' ' || name)
  ) stored,
  primary key (cofid_code, name),
  check ((fibre_100g is null) = (fibre_source is null)),
  -- The same limits as public.foods, so every row can be copied there.
  check (protein_100g + carbs_100g + fat_100g + coalesce(fibre_100g, 0) <= 105),
  check (sugar_100g is null or sugar_100g <= carbs_100g + 0.5)
);

create index reference_foods_search_idx
  on public.reference_foods using gin (search_vector);

revoke all on table public.reference_foods from public, anon, authenticated;
grant select on table public.reference_foods to authenticated;

alter table public.reference_foods enable row level security;

create policy "reference foods: read" on public.reference_foods
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Search: full-text, with a trigram fallback for typos and half-typed words
-- ---------------------------------------------------------------------------
-- Runs as the caller (security invoker), so RLS applies. The query is a
-- bound parameter used only through tsquery and similarity functions.

create function public.search_reference_foods(query text)
returns setof public.reference_foods
language sql
stable
security invoker
set search_path = ''
as $$
  with q as (
    select
      lower(left(btrim(query), 100)) as text,
      websearch_to_tsquery('english'::regconfig, left(btrim(query), 100)) as ts,
      -- The query's last word, usually the food itself ("chicken breast").
      plainto_tsquery(
        'english'::regconfig,
        regexp_replace(left(btrim(query), 100), '^.*\s', '')
      ) as noun
  ),
  matches as (
    select
      f.*,
      -- The name before the first comma, e.g. "White rice" in "White rice,
      -- basmati, raw".
      split_part(f.display_name, ',', 1) as head
    from public.reference_foods f
    cross join q
    where char_length(q.text) >= 2
      and (f.search_vector @@ q.ts
           or extensions.word_similarity(q.text, lower(f.display_name)) >= 0.5)
  )
  select
    m.cofid_code, m.name, m.display_name, m.food_group, m.kcal_100g,
    m.protein_100g, m.carbs_100g, m.fat_100g, m.fibre_100g, m.fibre_source,
    m.sugar_100g, m.salt_100g, m.edible_proportion, m.nutrients_source,
    m.search_vector
  from matches m
  cross join q
  order by
    -- Foods that are the thing searched for come first: for "banana",
    -- "Bananas, flesh only" before "Banana bread".
    case
      when to_tsvector('english'::regconfig, m.head) @@ q.ts
           and to_tsvector(
                 'english'::regconfig, regexp_replace(m.head, '^.*\s', '')
               ) @@ q.noun
        then 0
      when to_tsvector('english'::regconfig, m.head) @@ q.ts then 1
      else 2
    end,
    ts_rank(m.search_vector, q.ts) desc,
    extensions.word_similarity(q.text, lower(m.display_name)) desc,
    char_length(m.display_name),
    m.display_name
  limit 30;
$$;

revoke execute on function public.search_reference_foods(text)
  from public, anon;
grant execute on function public.search_reference_foods(text) to authenticated;

-- ---------------------------------------------------------------------------
-- foods: allow copies of basic foods
-- ---------------------------------------------------------------------------

alter table public.foods drop constraint foods_source_check;
alter table public.foods
  add constraint foods_source_check
  check (source in ('off', 'manual', 'cofid'));

-- The CoFID code a copied basic food came from, so choosing it again reuses
-- the saved copy. Set exactly when the source is 'cofid'.
alter table public.foods
  add column reference_code text
    check (reference_code ~ '^[0-9]{2}-[0-9]{3,4}$'),
  add constraint foods_reference_code_source_check
    check ((source = 'cofid') = (reference_code is not null));

-- ---------------------------------------------------------------------------
-- Unknown fibre
-- ---------------------------------------------------------------------------
-- Fibre is optional on UK labels and missing from some basic foods. Null
-- means "not known", which the app shows as such, rather than a 0 that
-- would understate the day's fibre.

alter table public.foods
  alter column fibre_100g drop not null,
  alter column fibre_100g drop default;

-- The macro sum must still hold when fibre is unknown (a null sum would
-- pass the check).
alter table public.foods drop constraint foods_check;
alter table public.foods
  add constraint foods_macro_sum_check
  check (protein_100g + carbs_100g + fat_100g + coalesce(fibre_100g, 0) <= 105);

alter table public.food_logs
  alter column fibre_g drop not null,
  alter column fibre_g drop default;
