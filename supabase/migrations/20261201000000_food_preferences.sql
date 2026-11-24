-- Likes, dislikes and nevers for basic foods and cuisines, used by the
-- planner when it makes dishes. The app never asks why (an allergy would be
-- health data, and it doesn't need to know).
--
-- Same rules as every user table: user_id defaults to auth.uid() and
-- cascades on account deletion, RLS with own-row policies for
-- `authenticated`, nothing for `anon`, values checked here. Personal: never
-- household-owned (no household_id).

create table public.food_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Exactly one target: a cuisine, or a basic food by CoFID code and name.
  cuisine text check (cuisine in ('british', 'indian', 'italian', 'mexican',
                                  'chinese', 'mediterranean')),
  cofid_code text check (cofid_code ~ '^[0-9]{2}-[0-9]{3,4}$'),
  cofid_name text check (char_length(cofid_name) between 1 and 200),
  preference text not null check (preference in ('like', 'dislike', 'never')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((cofid_code is null) = (cofid_name is null)),
  check ((cuisine is null) <> (cofid_code is null))
);

create unique index food_preferences_user_cuisine_idx
  on public.food_preferences (user_id, cuisine)
  where cuisine is not null;
create unique index food_preferences_user_food_idx
  on public.food_preferences (user_id, cofid_code, cofid_name)
  where cofid_code is not null;

create trigger food_preferences_set_updated_at
  before update on public.food_preferences
  for each row execute function private.set_updated_at();

revoke all on table public.food_preferences from anon;
grant select, insert, update, delete on table public.food_preferences
  to authenticated;

alter table public.food_preferences enable row level security;

create policy "own food preferences: select" on public.food_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own food preferences: insert" on public.food_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own food preferences: update" on public.food_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own food preferences: delete" on public.food_preferences
  for delete to authenticated using (user_id = (select auth.uid()));
