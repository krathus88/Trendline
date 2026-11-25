-- Whether the week planner plans a snack each day (from its no-cook snack
-- dishes). On by default; off for people who don't snack. The profiles RLS
-- policies already cover the new column.

alter table public.profiles
  add column plan_snacks boolean not null default true;
