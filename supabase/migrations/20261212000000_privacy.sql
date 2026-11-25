-- Privacy: recorded consent, data export and account deletion.
--
-- Weight, body composition, food intake and the health screening answers
-- are UK GDPR special category data, processed on the user's explicit
-- consent. The app asks for it before onboarding and again whenever the
-- privacy policy changes, and records each agreement here, so the consent
-- can be shown later. Withdrawing consent means deleting the account,
-- which the app offers alongside a full export of the user's data.

-- ---------------------------------------------------------------------------
-- consents: one row per agreement to a version of the privacy policy
-- ---------------------------------------------------------------------------

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  policy_version int not null check (policy_version between 1 and 1000),
  -- Set by the database, never by the app, so the record shows when the
  -- agreement really reached the server.
  consented_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index consents_user_idx on public.consents (user_id, policy_version);

create trigger consents_set_updated_at before update on public.consents
  for each row execute function private.set_updated_at();

-- The app sends only the policy version; everything else is a default.
revoke all on table public.consents from anon, authenticated;
grant select, delete on table public.consents to authenticated;
grant insert (policy_version) on table public.consents to authenticated;

alter table public.consents enable row level security;

create policy "own consents: select" on public.consents
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own consents: insert" on public.consents
  for insert to authenticated with check (user_id = (select auth.uid()));
-- A record of what was agreed to, and when, is never rewritten.
create policy "consents: never changed" on public.consents
  for update to authenticated using (false);
create policy "own consents: delete" on public.consents
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- export_my_data: everything stored about the caller, as one JSON document
-- ---------------------------------------------------------------------------
-- Security invoker: it reads through the caller's own policies, and every
-- query also filters on the caller, so rows shared with them by a household
-- but added by someone else are left out (they're the other person's).
-- Household rows the caller is part of (their servings in a household
-- week, their portions of a household batch) are included.
--
-- Every public table except the shared reference data is a key here; the
-- privacy test fails if a new table is left out.

create function public.export_my_data()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'format', 1,
    'exported_at', now(),
    'user_id', me,
    'profiles', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.profiles t where t.user_id = me),
    'consents', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.consents t where t.user_id = me),
    'goals', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.goals t where t.user_id = me),
    'weigh_ins', (select coalesce(jsonb_agg(to_jsonb(t) order by t.measured_at), '[]')
      from public.weigh_ins t where t.user_id = me),
    'weigh_in_dismissals', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.weigh_in_dismissals t where t.user_id = me),
    'energy_estimates', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.energy_estimates t where t.user_id = me),
    'day_logs', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.day_logs t where t.user_id = me),
    'food_logs', (select coalesce(jsonb_agg(to_jsonb(t) order by t.eaten_at), '[]')
      from public.food_logs t where t.user_id = me),
    'foods', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.foods t where t.user_id = me),
    'recipes', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.recipes t where t.user_id = me),
    'recipe_ingredients', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.recipe_ingredients t where t.user_id = me),
    'food_preferences', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.food_preferences t where t.user_id = me),
    'day_schedules', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.day_schedules t where t.user_id = me),
    'meal_rules', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.meal_rules t where t.user_id = me),
    'meal_plans', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.meal_plans t where t.user_id = me),
    'plan_items', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.plan_items t where t.user_id = me or t.eater_id = me),
    'prep_sessions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.prep_sessions t where t.user_id = me),
    'prep_portions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.prep_portions t where t.user_id = me or t.eater_id = me),
    'households', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.households t
      where exists (select 1 from public.household_members m
                    where m.household_id = t.id and m.user_id = me)),
    'household_members', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.household_members t where t.user_id = me),
    'household_invites', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.household_invites t where t.user_id = me),
    'shares', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.shares t where t.user_id = me or t.viewer_id = me),
    'share_invites', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.share_invites t where t.user_id = me),
    'shared_targets', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]')
      from public.shared_targets t where t.user_id = me)
  );
end;
$$;

revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

-- ---------------------------------------------------------------------------
-- delete_my_account: deletes the caller's account and everything in it
-- ---------------------------------------------------------------------------
-- Security definer, because only the database owner can delete from
-- auth.users. It deletes the caller and nobody else. Every user table
-- cascades from auth.users, and the before-delete trigger hands the
-- caller's shared household rows on first. The caller's Discord ID is also
-- taken off the invite list, so nothing about them is left; signing in
-- again needs a new invite.

create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  delete from private.allowed_users a
  where a.discord_id in (
    select i.provider_id from auth.identities i
    where i.user_id = me and i.provider = 'discord'
  );

  delete from auth.users u where u.id = me;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
