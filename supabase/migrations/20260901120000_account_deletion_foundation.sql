-- Account deletion request state machine and retry-safe local worker boundary.
-- Cross-system Supabase Auth anonymization is intentionally deferred to the worker phase.

create table platform.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending',
  execute_after timestamptz not null default timezone('utc', now()),
  attempt_count integer not null default 0,
  last_error_code text,
  next_attempt_at timestamptz,
  worker_id uuid,
  processing_started_at timestamptz,
  requested_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint account_deletion_requests_status_check
    check (status in ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  constraint account_deletion_requests_attempt_count_check
    check (attempt_count >= 0),
  constraint account_deletion_requests_error_code_check
    check (last_error_code is null or last_error_code ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  constraint account_deletion_requests_processing_fields_check
    check (
      (status = 'processing' and worker_id is not null and processing_started_at is not null)
      or (status <> 'processing' and worker_id is null and processing_started_at is null)
    ),
  constraint account_deletion_requests_completed_at_check
    check ((status = 'completed') = (completed_at is not null)),
  constraint account_deletion_requests_cancelled_at_check
    check ((status = 'cancelled') = (cancelled_at is not null)),
  constraint account_deletion_requests_failed_retry_check
    check (status <> 'failed' or next_attempt_at is not null)
);

comment on table platform.account_deletion_requests is
  'Recoverable account deletion workflow state; Auth anonymization is an external retryable step.';

comment on column platform.account_deletion_requests.last_error_code is
  'Stable operational code only; sensitive external error text is never stored.';

create unique index account_deletion_requests_one_open_idx
  on platform.account_deletion_requests (user_id)
  where status in ('pending', 'processing', 'failed');

create index account_deletion_requests_due_idx
  on platform.account_deletion_requests (execute_after, next_attempt_at, requested_at)
  where status in ('pending', 'failed');

create index account_deletion_requests_status_idx
  on platform.account_deletion_requests (status, requested_at desc);

create trigger account_deletion_requests_set_updated_at
before update on platform.account_deletion_requests
for each row
execute function platform.set_updated_at();

create or replace function public.request_account_deletion(
  p_user_id uuid,
  p_idempotency_key text,
  p_request_hash text,
  p_request_id uuid default null
)
returns table (
  deletion_request_id uuid,
  status text,
  execute_after timestamptz,
  requested_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  idempotency_row platform.idempotency_records%rowtype;
  request_row platform.account_deletion_requests%rowtype;
  profile_status_value text;
  now_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
  response_body_value jsonb;
begin
  if p_user_id is null
     or p_idempotency_key is null
     or btrim(p_idempotency_key) = ''
     or length(p_idempotency_key) > 255
     or p_request_hash is null
     or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'A user, idempotency key, and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('account.deletion.request', 'user:' || p_user_id::text, p_idempotency_key, p_request_hash,
     now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'account.deletion.request'
       and record.actor_key = 'user:' || p_user_id::text
       and record.idempotency_key = p_idempotency_key
     for update;

    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;

    if idempotency_row.status = 'completed' then
      return query
      select
        (idempotency_row.response_body ->> 'deletionRequestId')::uuid,
        idempotency_row.response_body ->> 'status',
        (idempotency_row.response_body ->> 'executeAfter')::timestamptz,
        (idempotency_row.response_body ->> 'requestedAt')::timestamptz,
        nullif(idempotency_row.response_body ->> 'completedAt', '')::timestamptz;
      return;
    end if;
  end if;

  select profiles.status
    into profile_status_value
    from platform.profiles as profiles
   where profiles.id = p_user_id
   for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The account profile was not found';
  end if;
  if profile_status_value <> 'active' then
    raise exception using errcode = '23514', message = 'Only active accounts can request deletion';
  end if;

  insert into platform.account_deletion_requests
    (user_id, status, execute_after, requested_at)
  values
    (p_user_id, 'pending', now_value, now_value)
  returning * into request_row;

  update platform.platform_sessions
     set revoked_at = coalesce(revoked_at, now_value),
         revoked_reason = coalesce(revoked_reason, 'account_deletion_requested')
   where user_id = p_user_id
     and revoked_at is null;

  update platform.profiles
     set status = 'deletion_pending'
   where id = p_user_id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'user', p_user_id, 'account.deletion.requested', 'account_deletion_request',
     request_row.id, p_request_id, 'User requested account deletion',
     jsonb_build_object('profileStatus', 'active'),
     jsonb_build_object('profileStatus', 'deletion_pending', 'status', request_row.status));

  response_body_value := jsonb_build_object(
    'deletionRequestId', request_row.id,
    'status', request_row.status,
    'executeAfter', request_row.execute_after,
    'requestedAt', request_row.requested_at,
    'completedAt', request_row.completed_at
  );
  update platform.idempotency_records
     set status = 'completed',
         resource_type = 'account_deletion_request',
         resource_id = request_row.id,
         response_status = 202,
         response_body = response_body_value
   where id = idempotency_row.id;

  return query
  select request_row.id, request_row.status, request_row.execute_after,
         request_row.requested_at, request_row.completed_at;
end;
$$;

create or replace function public.cancel_account_deletion(
  p_user_id uuid,
  p_request_id uuid default null
)
returns table (
  deletion_request_id uuid,
  status text,
  execute_after timestamptz,
  requested_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  request_row platform.account_deletion_requests%rowtype;
  latest_row platform.account_deletion_requests%rowtype;
  now_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
begin
  if p_user_id is null then
    raise exception using errcode = '22023', message = 'A user is required';
  end if;

  select request_item.*
    into latest_row
    from platform.account_deletion_requests as request_item
   where request_item.user_id = p_user_id
     and request_item.status in ('pending', 'processing', 'failed')
   order by request_item.requested_at desc, request_item.id desc
   limit 1
   for update;

  if not found then
    select request_item.*
      into latest_row
      from platform.account_deletion_requests as request_item
     where request_item.user_id = p_user_id
     order by request_item.requested_at desc, request_item.id desc
     limit 1
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
    end if;
  end if;

  if latest_row.status = 'cancelled' then
    return query select latest_row.id, latest_row.status, latest_row.execute_after,
                        latest_row.requested_at, latest_row.completed_at;
    return;
  end if;
  if latest_row.status not in ('pending', 'failed') then
    raise exception using errcode = '23514', message = 'The account deletion request cannot be cancelled in its current state';
  end if;

  update platform.account_deletion_requests
     set status = 'cancelled',
         cancelled_at = now_value,
         next_attempt_at = null,
         last_error_code = null
   where id = latest_row.id
  returning * into request_row;

  update platform.profiles
     set status = 'active'
   where id = p_user_id
     and platform.profiles.status = 'deletion_pending';

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'user', p_user_id, 'account.deletion.cancelled', 'account_deletion_request',
     request_row.id, p_request_id, 'User cancelled account deletion',
     jsonb_build_object('status', latest_row.status),
     jsonb_build_object('status', request_row.status));

  return query
  select request_row.id, request_row.status, request_row.execute_after,
         request_row.requested_at, request_row.completed_at;
end;
$$;

create or replace function public.claim_account_deletion_request(
  p_worker_id uuid
)
returns table (
  deletion_request_id uuid,
  user_id uuid,
  status text,
  attempt_count integer,
  execute_after timestamptz,
  processing_started_at timestamptz
)
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  request_row platform.account_deletion_requests%rowtype;
  now_value timestamptz := timezone('utc', now());
begin
  if p_worker_id is null then
    raise exception using errcode = '22023', message = 'A worker ID is required';
  end if;

  select request_item.*
    into request_row
    from platform.account_deletion_requests as request_item
   where request_item.status in ('pending', 'failed')
     and request_item.execute_after <= now_value
     and (request_item.next_attempt_at is null or request_item.next_attempt_at <= now_value)
   order by request_item.execute_after, request_item.requested_at, request_item.id
   limit 1
   for update skip locked;

  if not found then
    return;
  end if;

  update platform.account_deletion_requests
     set status = 'processing',
         attempt_count = request_row.attempt_count + 1,
         last_error_code = null,
         next_attempt_at = null,
         worker_id = p_worker_id,
         processing_started_at = now_value
   where id = request_row.id
  returning * into request_row;

  return query
  select request_row.id, request_row.user_id, request_row.status,
         request_row.attempt_count, request_row.execute_after,
         request_row.processing_started_at;
end;
$$;

create or replace function public.fail_account_deletion_request(
  p_request_id uuid,
  p_worker_id uuid,
  p_error_code text
)
returns table (
  deletion_request_id uuid,
  status text,
  attempt_count integer,
  next_attempt_at timestamptz,
  last_error_code text
)
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  request_row platform.account_deletion_requests%rowtype;
  now_value timestamptz := timezone('utc', now());
begin
  if p_request_id is null or p_worker_id is null or p_error_code is null
     or p_error_code not in ('AUTH_USER_UPDATE_FAILED', 'AUTH_USER_NOT_FOUND', 'DATABASE_STEP_FAILED', 'RETRYABLE_EXTERNAL_ERROR') then
    raise exception using errcode = '22023', message = 'A request, worker, and stable error code are required';
  end if;

  select request_item.*
    into request_row
    from platform.account_deletion_requests as request_item
   where request_item.id = p_request_id
   for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
  end if;
  if request_row.status <> 'processing' or request_row.worker_id is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'The worker does not own the processing request';
  end if;

  update platform.account_deletion_requests
     set status = 'failed',
         last_error_code = p_error_code,
         next_attempt_at = now_value + interval '5 minutes',
         worker_id = null,
         processing_started_at = null
   where id = request_row.id
  returning * into request_row;

  return query
  select request_row.id, request_row.status, request_row.attempt_count,
         request_row.next_attempt_at, request_row.last_error_code;
end;
$$;

comment on function public.request_account_deletion(uuid, text, text, uuid) is
  'Creates one pending deletion request, revokes platform sessions, freezes the profile, and records an idempotent audit event.';
comment on function public.cancel_account_deletion(uuid, uuid) is
  'Cancels a pending or failed deletion request and restores the profile to active without restoring sessions or entitlements.';
comment on function public.claim_account_deletion_request(uuid) is
  'Claims one due pending/failed request with a row lock for a later cross-system worker.';
comment on function public.fail_account_deletion_request(uuid, uuid, text) is
  'Records only a stable retryable failure code for a worker-owned deletion request.';

alter table platform.account_deletion_requests enable row level security;
revoke all on table platform.account_deletion_requests from public, anon, authenticated, service_role;
revoke all on function public.request_account_deletion(uuid, text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.cancel_account_deletion(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.claim_account_deletion_request(uuid)
  from public, anon, authenticated;
revoke all on function public.fail_account_deletion_request(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.request_account_deletion(uuid, text, text, uuid) to service_role;
grant execute on function public.cancel_account_deletion(uuid, uuid) to service_role;
grant execute on function public.claim_account_deletion_request(uuid) to service_role;
grant execute on function public.fail_account_deletion_request(uuid, uuid, text) to service_role;
