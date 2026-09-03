-- Remove the remaining database function references to the retired shared
-- session table while preserving account deletion and retention state machines.

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
  if p_user_id is null or p_idempotency_key is null or btrim(p_idempotency_key) = ''
     or length(p_idempotency_key) > 255 or p_request_hash is null or btrim(p_request_hash) = '' then
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
    select record.* into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'account.deletion.request'
       and record.actor_key = 'user:' || p_user_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' then
      return query select
        (idempotency_row.response_body ->> 'deletionRequestId')::uuid,
        idempotency_row.response_body ->> 'status',
        (idempotency_row.response_body ->> 'executeAfter')::timestamptz,
        (idempotency_row.response_body ->> 'requestedAt')::timestamptz,
        nullif(idempotency_row.response_body ->> 'completedAt', '')::timestamptz;
      return;
    end if;
  end if;

  select profile.status into profile_status_value
    from platform.profiles as profile
   where profile.id = p_user_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The account profile was not found';
  end if;
  if profile_status_value <> 'active' then
    raise exception using errcode = '23514', message = 'Only active accounts can request deletion';
  end if;

  insert into platform.account_deletion_requests (user_id, status, execute_after, requested_at)
  values (p_user_id, 'pending', now_value, now_value)
  returning * into request_row;

  update platform.profiles set status = 'deletion_pending' where id = p_user_id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'user', p_user_id, 'account.deletion.requested', 'account_deletion_request',
     request_row.id, p_request_id, 'User requested account deletion',
     jsonb_build_object('profileStatus', 'active'),
     jsonb_build_object('profileStatus', 'deletion_pending', 'status', request_row.status));

  response_body_value := jsonb_build_object(
    'deletionRequestId', request_row.id, 'status', request_row.status,
    'executeAfter', request_row.execute_after, 'requestedAt', request_row.requested_at,
    'completedAt', request_row.completed_at);
  update platform.idempotency_records
     set status = 'completed', resource_type = 'account_deletion_request',
         resource_id = request_row.id, response_status = 202, response_body = response_body_value
   where id = idempotency_row.id;

  return query select request_row.id, request_row.status, request_row.execute_after,
                      request_row.requested_at, request_row.completed_at;
end;
$$;

create or replace function public.complete_account_deletion_request(
  p_deletion_request_id uuid,
  p_worker_id uuid,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  request_row platform.account_deletion_requests%rowtype;
  profile_row platform.profiles%rowtype;
  grant_row record;
  now_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
  revoked_grant_count integer := 0;
  anonymized_feedback_count integer := 0;
  detached_order_count integer := 0;
  disabled_admin_count integer := 0;
  result jsonb;
begin
  if p_deletion_request_id is null or p_worker_id is null then
    raise exception using errcode = '22023', message = 'A deletion request and worker are required';
  end if;
  select request_item.* into request_row
    from platform.account_deletion_requests as request_item
   where request_item.id = p_deletion_request_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
  end if;
  if request_row.status = 'completed' then
    return jsonb_build_object('deletionRequestId', request_row.id, 'userId', request_row.user_id,
      'status', request_row.status, 'completedAt', request_row.completed_at, 'idempotent', true);
  end if;
  if request_row.status <> 'processing' or request_row.worker_id is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'The worker does not own the processing request';
  end if;
  select profile_item.* into profile_row
    from platform.profiles as profile_item
   where profile_item.id = request_row.user_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The account profile was not found';
  end if;

  for grant_row in
    select grant_item.id from platform.entitlement_grants as grant_item
     where grant_item.user_id = request_row.user_id and grant_item.status = 'active'
     order by grant_item.id for update
  loop
    perform public.revoke_entitlement(grant_row.id, 'system', null,
      'Account deletion de-identification', p_request_id);
    revoked_grant_count := revoked_grant_count + 1;
  end loop;

  update platform.feedback_requests
     set user_id = null, title = '[deleted]', content = '[deleted]'
   where user_id = request_row.user_id;
  get diagnostics anonymized_feedback_count = row_count;
  update platform.orders set user_id = null where user_id = request_row.user_id;
  get diagnostics detached_order_count = row_count;
  update platform.admin_members
     set status = 'disabled', disabled_at = coalesce(disabled_at, now_value),
         created_by = case when created_by = request_row.user_id then null else created_by end
   where user_id = request_row.user_id and status = 'active';
  get diagnostics disabled_admin_count = row_count;

  perform set_config('app.audit_scrub', 'account_deletion', true);
  update platform.audit_logs set ip_hash = null
   where actor_id = request_row.user_id or (target_type = 'user' and target_id = request_row.user_id);
  perform set_config('app.audit_scrub', '', true);
  update platform.profiles
     set display_name = null, avatar_url = null, locale = null,
         status = 'deleted', deleted_at = coalesce(deleted_at, now_value)
   where id = request_row.user_id;
  update platform.account_deletion_requests
     set status = 'completed', completed_at = coalesce(completed_at, now_value),
         worker_id = null, processing_started_at = null, next_attempt_at = null, last_error_code = null
   where id = request_row.id returning * into request_row;

  result := jsonb_build_object('deletionRequestId', request_row.id, 'userId', request_row.user_id,
    'status', request_row.status, 'completedAt', request_row.completed_at,
    'revokedGrantCount', revoked_grant_count, 'anonymizedFeedbackCount', anonymized_feedback_count,
    'detachedOrderCount', detached_order_count, 'disabledAdminCount', disabled_admin_count,
    'idempotent', false);
  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'system', null, 'account.deletion.completed', 'account_deletion_request', request_row.id,
     p_request_id, 'Account deletion and de-identification completed',
     jsonb_build_object('profileStatus', profile_row.status, 'requestStatus', 'processing'), result);
  return result;
end;
$$;

create or replace function public.run_retention_cleanup(
  p_session_expired_before timestamptz,
  p_security_context_before timestamptz,
  p_idempotency_response_before timestamptz,
  p_batch_size integer default 100,
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  redemption_ip_hash_count integer := 0;
  audit_ip_hash_count integer := 0;
  idempotency_response_count integer := 0;
  idempotency_deleted_count integer := 0;
  idempotency_row platform.idempotency_records%rowtype;
begin
  if p_session_expired_before is null or p_security_context_before is null or p_idempotency_response_before is null then
    raise exception using errcode = '22023', message = 'Cleanup cutoffs are required';
  end if;
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 1000 then
    raise exception using errcode = '22023', message = 'Cleanup batch size is invalid';
  end if;
  select count(*)::integer into redemption_ip_hash_count from (
    select id from platform.redemptions where ip_hash is not null and redeemed_at <= p_security_context_before
    order by redeemed_at, id limit p_batch_size) candidates;
  select count(*)::integer into audit_ip_hash_count from (
    select id from platform.audit_logs where ip_hash is not null and created_at <= p_security_context_before
    order by created_at, id limit p_batch_size) candidates;
  select count(*)::integer into idempotency_response_count from (
    select id from platform.idempotency_records where status = 'completed' and response_body is not null
      and expires_at <= p_idempotency_response_before order by expires_at, id limit p_batch_size) candidates;
  if p_dry_run then
    return jsonb_build_object('dryRun', true, 'sessionCount', 0,
      'redemptionIpHashCount', redemption_ip_hash_count, 'auditIpHashCount', audit_ip_hash_count,
      'idempotencyResponseCount', idempotency_response_count, 'idempotencyDeletedCount', 0,
      'batchSize', p_batch_size);
  end if;
  set local app.retention_cleanup = 'retention_cleanup';
  with candidates as (
    select id from platform.redemptions where ip_hash is not null and redeemed_at <= p_security_context_before
    order by redeemed_at, id limit p_batch_size for update skip locked
  ) update platform.redemptions item set ip_hash = null from candidates where item.id = candidates.id;
  set local app.audit_scrub = 'retention_cleanup';
  with candidates as (
    select id from platform.audit_logs where ip_hash is not null and created_at <= p_security_context_before
    order by created_at, id limit p_batch_size for update skip locked
  ) update platform.audit_logs item set ip_hash = null from candidates where item.id = candidates.id;
  for idempotency_row in
    select record.* from platform.idempotency_records record
     where record.status = 'completed' and record.response_body is not null
       and record.expires_at <= p_idempotency_response_before
     order by record.expires_at, record.id limit p_batch_size for update skip locked
  loop
    if exists (select 1 from platform.redemptions redemption where redemption.idempotency_record_id = idempotency_row.id) then
      update platform.idempotency_records set response_body = null, response_status = null where id = idempotency_row.id;
    else
      delete from platform.idempotency_records where id = idempotency_row.id;
      idempotency_deleted_count := idempotency_deleted_count + 1;
    end if;
  end loop;
  return jsonb_build_object('dryRun', false, 'sessionCount', 0,
    'redemptionIpHashCount', redemption_ip_hash_count, 'auditIpHashCount', audit_ip_hash_count,
    'idempotencyResponseCount', idempotency_response_count,
    'idempotencyDeletedCount', idempotency_deleted_count, 'batchSize', p_batch_size);
end;
$$;

-- Rewrite the existing Admin projections/commands in-place while retaining
-- their established contracts. This removes only the obsolete session work;
-- all entitlement, deletion and audit behavior remains backend-owned.
do $$
declare
  function_definition text;
begin
  select pg_get_functiondef(proc.oid)
    into function_definition
    from pg_proc as proc
   where proc.oid = 'public.admin_user_overview(uuid,uuid)'::regprocedure;
  function_definition := regexp_replace(
    function_definition,
    E'\\s*''sessionSummary'', jsonb_build_object\\(.*?\\n    ''deletionRequests''',
    E'''deletionRequests''',
    's'
  );
  execute function_definition;

  select pg_get_functiondef(proc.oid)
    into function_definition
    from pg_proc as proc
   where proc.oid = 'public.admin_customer_command(uuid,text,uuid,jsonb,text,text,text,uuid)'::regprocedure;
  function_definition := replace(
    function_definition,
    'revoked_session_count integer;',
    'revoked_session_count integer := 0;'
  );
  function_definition := regexp_replace(
    function_definition,
    E'\\s*update platform\\.platform_sessions.*?get diagnostics revoked_session_count = row_count;',
    '',
    's'
  );
  execute function_definition;
end;
$$;
