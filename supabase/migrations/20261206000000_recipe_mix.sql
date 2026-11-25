-- Mixes: a food made up with others and eaten as one portion, for example a
-- coffee sachet made with milk. Entered from the Add food screen, which
-- saves the food and a one-portion recipe of it plus what it's made with.
-- Stored as a recipe so logs, meal rules and macro snapshots work as for any
-- recipe; origin 'mix' keeps it out of the planner's choice of dishes for
-- breakfast, lunch and dinner (it's still placed by meal rules).
--
-- No new table, so RLS is unchanged: the recipes policies already cover
-- these rows.

alter table public.recipes drop constraint recipes_origin_check;
alter table public.recipes add constraint recipes_origin_check
  check (origin in ('user', 'library', 'template', 'mix'));

-- Only library and template copies have a source; the user's own recipes
-- and mixes never do.
alter table public.recipes drop constraint recipes_check;
alter table public.recipes add constraint recipes_source_check
  check ((origin in ('library', 'template')) = (source_id is not null));
