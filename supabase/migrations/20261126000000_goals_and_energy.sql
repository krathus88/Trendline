-- Goals, completed days and adaptive energy estimates.

-- ---------------------------------------------------------------------------
-- goals: each change adds a row; the latest started_at is the active goal
-- ---------------------------------------------------------------------------

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Which two of target weight, pace and date the user fixed.
  kind text not null
    check (kind in ('target_and_pace', 'target_and_date', 'pace_and_date',
                    'maintain')),
  target_weight_kg numeric(5, 2) check (target_weight_kg between 25 and 400),
  pace_mode text not null default 'kg' check (pace_mode in ('kg', 'pct')),
  -- kg per week, or percent of body weight per week. A kg pace above 1% of
  -- body weight may be stored (the app caps it and shows the capped pace),
  -- but a percent pace can't exceed the 1% cap at all.
  pace_value numeric(4, 2) check (
    pace_value >= 0
    and ((pace_mode = 'kg' and pace_value <= 4)
         or (pace_mode = 'pct' and pace_value <= 1))
  ),
  goal_date date,
  started_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (case kind
    when 'target_and_pace' then
      target_weight_kg is not null and pace_value is not null
    when 'target_and_date' then
      target_weight_kg is not null and goal_date is not null
    when 'pace_and_date' then pace_value is not null and goal_date is not null
    else true
  end)
);

create index goals_user_started_idx on public.goals (user_id, started_at desc);

-- ---------------------------------------------------------------------------
-- day_logs: days the user marked as fully logged
-- ---------------------------------------------------------------------------

-- Only complete days feed the energy estimate: a partly logged day would
-- understate intake.
create table public.day_logs (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  day date not null,
  complete boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, day),
  -- A day can't be complete before it starts (allowing for time zones).
  check (day <= current_date + 1)
);

-- ---------------------------------------------------------------------------
-- energy_estimates: weekly adaptive updates
-- ---------------------------------------------------------------------------

create table public.energy_estimates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  computed_on date not null,
  tdee_kcal numeric(6, 1) not null check (tdee_kcal between 800 and 6000),
  confidence numeric(3, 2) not null check (confidence between 0 and 1),
  window_days smallint not null check (window_days between 14 and 21),
  complete_share numeric(3, 2) not null
    check (complete_share between 0.8 and 1),
  observed_kcal numeric(6, 1) not null
    check (observed_kcal between 800 and 6000),
  created_at timestamptz not null default now(),
  -- One update per day; a second device computing the same update is a
  -- no-op.
  unique (user_id, computed_on)
);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

create trigger goals_set_updated_at before update on public.goals
  for each row execute function private.set_updated_at();
create trigger day_logs_set_updated_at before update on public.day_logs
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access: authenticated users, own rows only. No anon access.
-- ---------------------------------------------------------------------------

revoke all on table
  public.goals, public.day_logs, public.energy_estimates
  from anon;

grant select, insert, update, delete on table
  public.goals, public.day_logs, public.energy_estimates
  to authenticated;

alter table public.goals enable row level security;
alter table public.day_logs enable row level security;
alter table public.energy_estimates enable row level security;

create policy "own goals: select" on public.goals
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own goals: insert" on public.goals
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own goals: update" on public.goals
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own goals: delete" on public.goals
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "own day logs: select" on public.day_logs
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own day logs: insert" on public.day_logs
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own day logs: update" on public.day_logs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own day logs: delete" on public.day_logs
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "own estimates: select" on public.energy_estimates
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own estimates: insert" on public.energy_estimates
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own estimates: update" on public.energy_estimates
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own estimates: delete" on public.energy_estimates
  for delete to authenticated using (user_id = (select auth.uid()));
