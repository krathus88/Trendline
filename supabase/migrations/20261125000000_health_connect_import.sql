-- Health Connect import: lets the app upsert readings by their Health Connect
-- record ID, and remembers readings the user deleted so a later sync doesn't
-- bring them back.

-- ---------------------------------------------------------------------------
-- Upsert target
-- ---------------------------------------------------------------------------

-- The API's upsert (`on conflict (user_id, source, external_id) do nothing`)
-- can't use a partial unique index, so replace it with a plain constraint.
-- Manual weigh-ins have no external_id, and nulls never conflict, so any
-- number of them can still exist.
drop index public.weigh_ins_user_external_idx;

alter table public.weigh_ins
  add constraint weigh_ins_user_external_key
  unique (user_id, source, external_id);

-- ---------------------------------------------------------------------------
-- weigh_in_dismissals: imported readings the user deleted
-- ---------------------------------------------------------------------------

-- Holds only the source record's ID, no health values, so deleting a reading
-- really removes its data.
create table public.weigh_in_dismissals (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  source text not null check (source in ('health_connect')),
  external_id text not null check (char_length(external_id) <= 200),
  created_at timestamptz not null default now(),
  primary key (user_id, source, external_id)
);

revoke all on table public.weigh_in_dismissals from anon;
grant select, insert, update, delete on table public.weigh_in_dismissals
  to authenticated;

alter table public.weigh_in_dismissals enable row level security;

create policy "own dismissals: select" on public.weigh_in_dismissals
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own dismissals: insert" on public.weigh_in_dismissals
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own dismissals: update" on public.weigh_in_dismissals
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "own dismissals: delete" on public.weigh_in_dismissals
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- When a user deletes an imported reading, remember its ID. Only for the
-- user's own deletes: when an account is deleted, its rows go by cascade
-- with no signed-in user, and nothing should be recorded.
create function private.remember_dismissed_weigh_in()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.external_id is not null and old.user_id = auth.uid() then
    insert into public.weigh_in_dismissals (user_id, source, external_id)
    values (old.user_id, old.source, old.external_id)
    on conflict do nothing;
  end if;
  return old;
end;
$$;

create trigger weigh_ins_remember_dismissed after delete on public.weigh_ins
  for each row execute function private.remember_dismissed_weigh_in();

-- Silently skip re-imports of readings the user deleted.
create function private.skip_dismissed_weigh_in()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.external_id is not null and exists (
    select 1 from public.weigh_in_dismissals d
    where d.user_id = new.user_id
      and d.source = new.source
      and d.external_id = new.external_id
  ) then
    return null;
  end if;
  return new;
end;
$$;

create trigger weigh_ins_skip_dismissed before insert on public.weigh_ins
  for each row execute function private.skip_dismissed_weigh_in();

revoke all on function private.remember_dismissed_weigh_in() from public;
revoke all on function private.skip_dismissed_weigh_in() from public;
