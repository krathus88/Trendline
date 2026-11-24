-- Goals can gain as well as lose. The pace stays a positive amount; the
-- direction says which way.

alter table public.goals
  add column direction text not null default 'lose'
    check (direction in ('lose', 'gain'));

-- Gaining faster than 0.5% of body weight a week is mostly fat, so a percent
-- pace can't ask for more. (A kg pace above it may be stored: the app caps
-- it and shows the capped pace, as it does for losing.)
alter table public.goals
  add constraint goals_gain_pace_cap check (
    direction = 'lose' or pace_mode <> 'pct' or pace_value is null
    or pace_value <= 0.5
  );
