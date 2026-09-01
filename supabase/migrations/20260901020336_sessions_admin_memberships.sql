-- Platform session persistence and the fixed first-version Admin membership model.
-- Raw session and CSRF tokens never cross this database boundary.

create table platform.platform_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null,
  csrf_hash text not null,
  expires_at timestamptz not null,
  last_seen_at timestamptz not null,
  revoked_at timestamptz,
  revoked_reason text,
  idempotency_record_id uuid unique references platform.idempotency_records(id) on delete restrict,
  ip_hash text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_sessions_token_hash_key unique (token_hash),
  constraint platform_sessions_token_hash_nonempty_check
    check (btrim(token_hash) <> ''),
  constraint platform_sessions_csrf_hash_nonempty_check
    check (btrim(csrf_hash) <> ''),
  constraint platform_sessions_expiry_check
    check (expires_at > created_at),
  constraint platform_sessions_last_seen_check
    check (last_seen_at >= created_at),
  constraint platform_sessions_revoked_reason_check
    check (revoked_reason is null or btrim(revoked_reason) <> '')
);

comment on table platform.platform_sessions is
  'Backend-owned Platform Sessions; only one-way token and CSRF hashes are persisted.';

comment on column platform.platform_sessions.token_hash is
  'Digest of the random API Host Cookie value; never a raw session token.';

comment on column platform.platform_sessions.csrf_hash is
  'Digest of the in-memory CSRF token; never a raw CSRF token.';

create table platform.admin_members (
  user_id uuid primary key references auth.users(id) on delete restrict,
  role text not null,
  status text not null default 'active',
  created_by uuid references auth.users(id) on delete set null,
  disabled_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint admin_members_role_check
    check (role in ('owner', 'admin', 'support', 'finance')),
  constraint admin_members_status_check
    check (status in ('active', 'disabled')),
  constraint admin_members_disabled_at_check
    check ((status = 'disabled') = (disabled_at is not null))
);

comment on table platform.admin_members is
  'Backend-owned fixed four-role Admin membership; it is not a profile or JWT role.';

create index platform_sessions_user_id_idx
  on platform.platform_sessions (user_id);

create index platform_sessions_active_expiry_idx
  on platform.platform_sessions (expires_at)
  where revoked_at is null;

create index admin_members_role_status_idx
  on platform.admin_members (role, status);

create index admin_members_created_by_idx
  on platform.admin_members (created_by);

create or replace function platform.prevent_session_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.user_id is distinct from old.user_id
     or new.token_hash is distinct from old.token_hash
     or new.csrf_hash is distinct from old.csrf_hash
     or new.idempotency_record_id is distinct from old.idempotency_record_id then
    raise exception using
      errcode = '23514',
      message = 'Platform Session identity fields cannot change';
  end if;
  return new;
end;
$$;

create trigger platform_sessions_prevent_identity_change
before update on platform.platform_sessions
for each row
execute function platform.prevent_session_identity_change();

create trigger platform_sessions_set_updated_at
before update on platform.platform_sessions
for each row
execute function platform.set_updated_at();

create trigger admin_members_set_updated_at
before update on platform.admin_members
for each row
execute function platform.set_updated_at();

create or replace function platform.prevent_admin_member_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.user_id is distinct from old.user_id then
    raise exception using
      errcode = '23514',
      message = 'Admin membership identity cannot change';
  end if;
  return new;
end;
$$;

create trigger admin_members_prevent_identity_change
before update on platform.admin_members
for each row
execute function platform.prevent_admin_member_identity_change();

alter table platform.platform_sessions enable row level security;
alter table platform.admin_members enable row level security;

revoke all on table platform.platform_sessions, platform.admin_members
  from public, anon, authenticated, service_role;
revoke all on function platform.prevent_session_identity_change()
  from public, anon, authenticated, service_role;
revoke all on function platform.prevent_admin_member_identity_change()
  from public, anon, authenticated, service_role;
