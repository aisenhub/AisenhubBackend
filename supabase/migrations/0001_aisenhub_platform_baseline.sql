-- AisenHub Platform clean database baseline.
-- Sensitive platform data stays outside the schemas exposed by the Data API.

create schema if not exists platform;

comment on schema platform is
  'Private platform schema. Access is provided through controlled backend functions.';

revoke all on schema platform from public, anon, authenticated, service_role;

alter default privileges in schema platform
  revoke all on tables from public, anon, authenticated, service_role;

alter default privileges in schema platform
  revoke all on sequences from public, anon, authenticated, service_role;

alter default privileges in schema platform
  revoke all on functions from public, anon, authenticated, service_role;

create table platform.idempotency_records (
  id uuid primary key default gen_random_uuid(),
  scope text not null,
  actor_key text not null,
  idempotency_key text not null,
  request_hash text not null,
  status text not null default 'in_progress',
  resource_type text,
  resource_id uuid,
  response_status integer,
  response_body jsonb,
  expires_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint idempotency_records_scope_nonempty
    check (btrim(scope) <> ''),
  constraint idempotency_records_actor_key_nonempty
    check (btrim(actor_key) <> ''),
  constraint idempotency_records_key_nonempty
    check (btrim(idempotency_key) <> ''),
  constraint idempotency_records_hash_nonempty
    check (btrim(request_hash) <> ''),
  constraint idempotency_records_status_check
    check (status in ('in_progress', 'completed', 'failed')),
  constraint idempotency_records_response_status_check
    check (response_status is null or response_status between 100 and 599),
  constraint idempotency_records_resource_pair_check
    check ((resource_type is null) = (resource_id is null)),
  constraint idempotency_records_scope_actor_key_unique
    unique (scope, actor_key, idempotency_key)
);

comment on table platform.idempotency_records is
  'Backend-owned command retry records; the request hash prevents key reuse for a different request.';

comment on column platform.idempotency_records.actor_key is
  'Stable identity key for a user, administrator, webhook, or service actor.';

comment on column platform.idempotency_records.request_hash is
  'Hash of the canonical request payload used to reject same-key/different-request reuse.';

create index idempotency_records_expires_at_idx
  on platform.idempotency_records (expires_at);

create or replace function platform.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create trigger idempotency_records_set_updated_at
before update on platform.idempotency_records
for each row
execute function platform.set_updated_at();

revoke all on all tables in schema platform from public, anon, authenticated, service_role;
revoke all on all sequences in schema platform from public, anon, authenticated, service_role;
revoke all on all functions in schema platform from public, anon, authenticated, service_role;
