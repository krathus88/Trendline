-- Invite-only sign-in: only allowlisted Discord accounts can sign up.
--
-- Admin-only data lives in the `private` schema, which the Data API does not
-- expose. App roles (anon, authenticated) get no grants and no policies here.
-- Add a person from the Supabase SQL editor:
--   insert into private.allowed_users (discord_id, note) values ('123…', 'Name');

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- Allowlist
-- ---------------------------------------------------------------------------

create table private.allowed_users (
  discord_id text primary key
    check (discord_id ~ '^[0-9]{15,21}$'), -- Discord snowflake IDs
  note text check (char_length(note) <= 200),
  created_at timestamptz not null default now()
);

alter table private.allowed_users enable row level security;

revoke all on table private.allowed_users from public, anon, authenticated;
grant select on table private.allowed_users to supabase_auth_admin;

-- The Auth hook runs as supabase_auth_admin, which is subject to RLS.
-- This is the table's only policy; app roles have none.
create policy "auth hook can read allowlist"
  on private.allowed_users
  for select
  to supabase_auth_admin
  using (true);

-- ---------------------------------------------------------------------------
-- "Before user created" Auth hook
-- ---------------------------------------------------------------------------
-- Runs before Supabase creates a new user. Returns {} to allow, or an error
-- object to reject. Existing users signing in again don't trigger it.
--
-- Supabase doesn't document exactly where an OAuth provider's user ID sits in
-- the payload, so every known location is checked. If none holds a Discord
-- ID, the sign-up is rejected (fail closed).

create or replace function private.check_allowlist(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_provider text := event -> 'user' -> 'app_metadata' ->> 'provider';
  v_discord_id text;
begin
  if v_provider is distinct from 'discord' then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 403,
        'message', 'Sign-in is only available with Discord.'
      )
    );
  end if;

  v_discord_id := coalesce(
    event -> 'user' -> 'user_metadata' ->> 'provider_id',
    event -> 'user' -> 'user_metadata' ->> 'sub',
    (
      select identity ->> 'provider_id'
      from jsonb_array_elements(
        coalesce(event -> 'user' -> 'identities', '[]'::jsonb)
      ) as identity
      where identity ->> 'provider' = 'discord'
      limit 1
    ),
    (
      select identity -> 'identity_data' ->> 'sub'
      from jsonb_array_elements(
        coalesce(event -> 'user' -> 'identities', '[]'::jsonb)
      ) as identity
      where identity ->> 'provider' = 'discord'
      limit 1
    )
  );

  if v_discord_id is not null and exists (
    select 1 from private.allowed_users a where a.discord_id = v_discord_id
  ) then
    return '{}'::jsonb;
  end if;

  return jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 403,
      'message', 'This Discord account is not on the invite list.'
    )
  );
end;
$$;

revoke execute on function private.check_allowlist(jsonb)
  from public, anon, authenticated;
grant execute on function private.check_allowlist(jsonb)
  to supabase_auth_admin;
