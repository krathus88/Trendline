-- Read-only sharing: a user lets chosen people see their weight trend,
-- their daily targets or their meal plans. Viewers can't change anything.
--
-- * Nothing is shared by default. The owner makes a single-use code naming
--   what it shares; whoever accepts it becomes a viewer of exactly that.
--   Each type can then be switched on or off per viewer at any time.
-- * Either side can end a share; access stops at once, because viewers
--   never read the owner's tables directly. They call the shared_*
--   functions below, which check the share on every call and return only
--   the columns the view needs (a weigh-in's date and weight, never body
--   fat, lean mass or where it came from).
-- * Targets are worked out in the app, so the owner's app publishes just
--   the numbers to shared_targets while a share includes them. The row is
--   deleted when no share does.

-- ---------------------------------------------------------------------------
-- shares
-- ---------------------------------------------------------------------------

create table public.shares (
  id uuid primary key default gen_random_uuid(),
  -- The owner: whose data is shared.
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  viewer_id uuid not null references auth.users (id) on delete cascade,
  -- The names each side chose to show the other, nothing from the
  -- sign-in account.
  owner_name text not null
    check (char_length(btrim(owner_name)) between 1 and 40),
  viewer_name text not null
    check (char_length(btrim(viewer_name)) between 1 and 40),
  share_weight boolean not null default false,
  share_targets boolean not null default false,
  share_plans boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, viewer_id),
  check (user_id <> viewer_id)
);

create index shares_viewer_idx on public.shares (viewer_id);

create table public.share_invites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  code text not null unique default private.new_invite_code()
    check (code ~ '^[A-HJ-NP-Z2-9]{10}$'),
  owner_name text not null
    check (char_length(btrim(owner_name)) between 1 and 40),
  share_weight boolean not null default false,
  share_targets boolean not null default false,
  share_plans boolean not null default false,
  expires_at timestamptz not null default now() + interval '2 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- An invite must share something.
  check (share_weight or share_targets or share_plans)
);

create index share_invites_user_idx on public.share_invites (user_id);

-- The owner's current daily targets, published by their app while a share
-- includes targets.
create table public.shared_targets (
  user_id uuid primary key default auth.uid()
    references auth.users (id) on delete cascade,
  kcal numeric(6, 1) not null check (kcal between 800 and 6000),
  protein_g numeric(5, 1) not null check (protein_g between 0 and 500),
  carbs_g numeric(5, 1) not null check (carbs_g between 0 and 1000),
  fat_g numeric(5, 1) not null check (fat_g between 0 and 500),
  fibre_g numeric(5, 1) not null check (fibre_g between 0 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger shares_set_updated_at before update on public.shares
  for each row execute function private.set_updated_at();
create trigger share_invites_set_updated_at before update on public.share_invites
  for each row execute function private.set_updated_at();
create trigger shared_targets_set_updated_at before update on public.shared_targets
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
-- Shares are made only by accept_share (the viewer isn't known before).
-- The owner may switch types on and off; either side may delete. Unused
-- commands have `false` policies and no grants.

revoke all on table public.shares, public.share_invites, public.shared_targets
  from anon, authenticated;

grant select, delete on table public.shares to authenticated;
grant update (share_weight, share_targets, share_plans)
  on table public.shares to authenticated;

grant select, delete on table public.share_invites to authenticated;
grant insert (owner_name, share_weight, share_targets, share_plans)
  on table public.share_invites to authenticated;

grant select, insert, update, delete on table public.shared_targets
  to authenticated;

alter table public.shares enable row level security;
alter table public.share_invites enable row level security;
alter table public.shared_targets enable row level security;

create policy "shares: owner and viewer read" on public.shares
  for select to authenticated
  using (user_id = (select auth.uid()) or viewer_id = (select auth.uid()));
create policy "shares: made by accept_share" on public.shares
  for insert to authenticated with check (false);
create policy "shares: owner chooses what" on public.shares
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "shares: either side ends" on public.shares
  for delete to authenticated
  using (user_id = (select auth.uid()) or viewer_id = (select auth.uid()));

create policy "own share invites: select" on public.share_invites
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own share invites: insert" on public.share_invites
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "share invites: never changed" on public.share_invites
  for update to authenticated using (false);
create policy "own share invites: delete" on public.share_invites
  for delete to authenticated using (user_id = (select auth.uid()));

-- Viewers read it through shared_targets_of(), not this table.
create policy "own shared targets: select" on public.shared_targets
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own shared targets: insert" on public.shared_targets
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own shared targets: update" on public.shared_targets
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own shared targets: delete" on public.shared_targets
  for delete to authenticated using (user_id = (select auth.uid()));

-- When no share includes targets any more (switched off, or the share
-- ended), the published numbers are deleted.
create function private.drop_unshared_targets()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.shares s
    where s.user_id = old.user_id and s.share_targets
  ) then
    delete from public.shared_targets t where t.user_id = old.user_id;
  end if;
  return null;
end;
$$;

revoke execute on function private.drop_unshared_targets()
  from public, anon, authenticated;

create trigger shares_drop_unshared_targets
  after update of share_targets or delete on public.shares
  for each row execute function private.drop_unshared_targets();

-- ---------------------------------------------------------------------------
-- accept_share
-- ---------------------------------------------------------------------------
-- Security definer: turns a valid code into a share with the caller as the
-- viewer of what the code names. Errors: TLS01 your own code, TLS02 no
-- such invite (or expired). Accepting again from the same person updates
-- what's shared to the new code's choice.

create function public.accept_share(code text, viewer_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  invite public.share_invites;
  saved uuid;
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  select * into invite
  from public.share_invites i
  where i.code = upper(btrim(accept_share.code)) and i.expires_at > now()
  for update;
  if invite.id is null then
    raise exception 'No such invite' using errcode = 'TLS02';
  end if;
  if invite.user_id = me then
    raise exception 'Your own invite' using errcode = 'TLS01';
  end if;

  insert into public.shares as s
    (user_id, viewer_id, owner_name, viewer_name, share_weight,
     share_targets, share_plans)
  values
    (invite.user_id, me, btrim(invite.owner_name),
     btrim(accept_share.viewer_name), invite.share_weight,
     invite.share_targets, invite.share_plans)
  on conflict on constraint shares_user_id_viewer_id_key do update
    set owner_name = excluded.owner_name,
        viewer_name = excluded.viewer_name,
        share_weight = excluded.share_weight,
        share_targets = excluded.share_targets,
        share_plans = excluded.share_plans
  returning s.id into saved;

  -- Single use.
  delete from public.share_invites i where i.id = invite.id;
  return saved;
end;
$$;

revoke execute on function public.accept_share(text, text) from public, anon;
grant execute on function public.accept_share(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- What a viewer can read
-- ---------------------------------------------------------------------------
-- Security definer, so they can read the owner's rows, but each checks the
-- caller is a viewer of that owner with that type switched on, and returns
-- only what the view needs. A missing or switched-off share returns
-- nothing (no error, so it doesn't reveal whether the owner exists).

create function private.can_view(owner uuid, kind text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.shares s
    where s.user_id = owner
      and s.viewer_id = (select auth.uid())
      and case kind
            when 'weight' then s.share_weight
            when 'targets' then s.share_targets
            when 'plans' then s.share_plans
            else false
          end
  );
$$;

revoke execute on function private.can_view(uuid, text) from public, anon, authenticated;

-- Weigh-ins since a day (at most 400 days back): when and how much only.
create function public.shared_weigh_ins(owner uuid, since date)
returns table (measured_at timestamptz, weight_kg numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select w.measured_at, w.weight_kg
  from public.weigh_ins w
  where private.can_view(owner, 'weight')
    and w.user_id = owner
    and w.measured_at >= greatest(since, current_date - 400)
  order by w.measured_at;
$$;

create function public.shared_targets_of(owner uuid)
returns table (
  kcal numeric, protein_g numeric, carbs_g numeric, fat_g numeric,
  fibre_g numeric, updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.kcal, t.protein_g, t.carbs_g, t.fat_g, t.fibre_g, t.updated_at
  from public.shared_targets t
  where private.can_view(owner, 'targets') and t.user_id = owner;
$$;

-- One week of the owner's own plan: each item's name, amount and what it
-- adds up to. Not the plan's targets (those are the targets type), rules or
-- notes.
create function public.shared_plan_items(owner uuid, week_start date)
returns table (
  day date, slot text, name text, amount numeric, is_recipe boolean,
  kcal numeric, protein_g numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select i.day, i.slot, coalesce(f.name, r.name), i.amount,
         i.recipe_id is not null,
         round(coalesce(f.kcal_100g * i.amount / 100,
                        rn.kcal / r.portions * i.amount), 1),
         round(coalesce(f.protein_100g * i.amount / 100,
                        rn.protein_g / r.portions * i.amount), 1)
  from public.meal_plans p
  join public.plan_items i on i.plan_id = p.id
  left join public.foods f on f.id = i.food_id
  left join public.recipes r on r.id = i.recipe_id
  left join lateral (
    select sum(g.kcal_100g * ri.raw_grams / 100) as kcal,
           sum(g.protein_100g * ri.raw_grams / 100) as protein_g
    from public.recipe_ingredients ri
    join public.foods g on g.id = ri.food_id
    where ri.recipe_id = r.id
  ) as rn on true
  where private.can_view(owner, 'plans')
    and p.user_id = owner
    and p.household_id is null
    and p.week_start = shared_plan_items.week_start
  order by i.day,
           array_position(array['breakfast', 'lunch', 'dinner', 'snack'], i.slot),
           i.recipe_id is null, coalesce(f.name, r.name);
$$;

revoke execute on function public.shared_weigh_ins(uuid, date) from public, anon;
revoke execute on function public.shared_targets_of(uuid) from public, anon;
revoke execute on function public.shared_plan_items(uuid, date) from public, anon;
grant execute on function public.shared_weigh_ins(uuid, date) to authenticated;
grant execute on function public.shared_targets_of(uuid) to authenticated;
grant execute on function public.shared_plan_items(uuid, date) to authenticated;
