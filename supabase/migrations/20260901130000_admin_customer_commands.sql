-- Customer business commands: role-checked, audited, idempotent wrappers over
-- the entitlement and account-lifecycle domain functions.

create or replace function public.admin_customer_command(
  p_actor_id uuid,
  p_action text,
  p_resource_id uuid,
  p_payload jsonb default '{}'::jsonb,
  p_reason text default null,
  p_idempotency_key text default null,
  p_request_hash text default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, auth, platform
as $$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  profile_row platform.profiles%rowtype;
  grant_row platform.entitlement_grants%rowtype;
  deletion_row platform.account_deletion_requests%rowtype;
  grant_result record;
  revoked_session_count integer;
  audit_id_value uuid;
  now_value timestamptz := timezone('utc', now());
  previous_deletion_status text;
  result jsonb;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';

  if actor_role is null then
    raise exception using errcode = '42501', message = 'Customer commands require an active administrator';
  end if;
  if p_action not in ('grant_entitlement', 'revoke_entitlement', 'restore_entitlement',
                      'disable_user', 'process_account_deletion') then
    raise exception using errcode = '22023', message = 'The Customer command is not supported';
  end if;
  if p_resource_id is null or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The Customer command target or payload is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Customer command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  if p_action in ('restore_entitlement', 'disable_user', 'process_account_deletion')
     and actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'This Customer command requires an owner or administrator';
  end if;
  if p_action in ('grant_entitlement', 'revoke_entitlement')
     and actor_role not in ('owner', 'admin', 'support') then
    raise exception using errcode = '42501', message = 'This Entitlement command is not allowed for the administrator';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.customer.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.customer.command'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The Customer command is already in progress';
    end if;
  end if;

  if p_action = 'grant_entitlement' then
    if actor_role not in ('owner', 'admin', 'support')
       or exists (select 1 from jsonb_object_keys(p_payload) as key
                  where key not in ('productVersionId', 'startsAt', 'expiresAt'))
       or p_payload->>'productVersionId' is null then
      raise exception using errcode = '22023', message = 'The Entitlement grant fields are invalid';
    end if;
    select profile.* into profile_row
      from platform.profiles as profile
     where profile.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The User was not found';
    end if;
    if profile_row.status <> 'active' then
      raise exception using errcode = '23514', message = 'Only active users can receive an entitlement grant';
    end if;
    select granted.* into grant_result
      from public.grant_entitlement(
        p_resource_id,
        (p_payload->>'productVersionId')::uuid,
        'admin',
        null,
        coalesce((p_payload->>'startsAt')::timestamptz, now_value),
        (p_payload->>'expiresAt')::timestamptz,
        'admin',
        p_actor_id,
        p_reason,
        null,
        p_request_id
      ) as granted;
    result := jsonb_build_object(
      'grantId', grant_result.grant_id,
      'sourceId', grant_result.source_id,
      'status', grant_result.status,
      'startsAt', grant_result.starts_at,
      'expiresAt', grant_result.expires_at,
      'auditLogId', grant_result.audit_log_id
    );
  elsif p_action = 'revoke_entitlement' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'Entitlement revoke does not accept additional fields';
    end if;
    select grant_item.* into grant_row
      from platform.entitlement_grants as grant_item
     where grant_item.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Entitlement grant was not found';
    end if;
    select revoked.* into grant_result
      from public.revoke_entitlement(p_resource_id, 'admin', p_actor_id, p_reason, p_request_id) as revoked;
    result := jsonb_build_object(
      'grantId', grant_result.grant_id,
      'status', grant_result.status,
      'revokedAt', grant_result.revoked_at,
      'auditLogId', grant_result.audit_log_id
    );
  elsif p_action = 'restore_entitlement' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'Entitlement restore does not accept additional fields';
    end if;
    select grant_item.* into grant_row
      from platform.entitlement_grants as grant_item
     where grant_item.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Entitlement grant was not found';
    end if;
    select restored.* into grant_result
      from public.restore_entitlement(p_resource_id, p_actor_id, p_reason, p_request_id) as restored;
    result := jsonb_build_object(
      'grantId', grant_result.grant_id,
      'sourceId', grant_result.source_id,
      'status', grant_result.status,
      'startsAt', grant_result.starts_at,
      'expiresAt', grant_result.expires_at,
      'restoredGrantId', grant_result.grant_id,
      'restoresGrantId', p_resource_id,
      'auditLogId', grant_result.audit_log_id
    );
  elsif p_action = 'disable_user' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'User disable does not accept additional fields';
    end if;
    select profile.* into profile_row
      from platform.profiles as profile
     where profile.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The User was not found';
    end if;
    if profile_row.status <> 'active' then
      raise exception using errcode = '23514', message = 'Only active users can be disabled';
    end if;
    update platform.platform_sessions
       set revoked_at = coalesce(revoked_at, now_value),
           revoked_reason = coalesce(revoked_reason, 'admin_user_disabled')
     where user_id = p_resource_id
       and revoked_at is null;
    get diagnostics revoked_session_count = row_count;
    update platform.profiles
       set status = 'disabled'
     where id = p_resource_id;
    result := jsonb_build_object(
      'userId', p_resource_id,
      'status', 'disabled',
      'revokedSessionCount', revoked_session_count
    );
    insert into platform.audit_logs
      (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
    values
      ('admin', p_actor_id, 'users.disable', 'user', p_resource_id, p_request_id, p_reason,
       jsonb_build_object('status', profile_row.status), result)
    returning id into audit_id_value;
    result := result || jsonb_build_object('auditLogId', audit_id_value);
  elsif p_action = 'process_account_deletion' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'Deletion processing does not accept additional fields';
    end if;
    select request_item.* into deletion_row
      from platform.account_deletion_requests as request_item
     where request_item.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
    end if;
    if deletion_row.status not in ('pending', 'failed')
       or deletion_row.execute_after > now_value
       or (deletion_row.next_attempt_at is not null and deletion_row.next_attempt_at > now_value) then
      raise exception using errcode = '23514', message = 'The account deletion request is not ready to process';
    end if;
    previous_deletion_status := deletion_row.status;
    update platform.account_deletion_requests
       set status = 'processing',
           attempt_count = deletion_row.attempt_count + 1,
           last_error_code = null,
           next_attempt_at = null,
           worker_id = p_actor_id,
           processing_started_at = now_value
     where id = p_resource_id
     returning * into deletion_row;
    result := jsonb_build_object(
      'deletionRequestId', deletion_row.id,
      'userId', deletion_row.user_id,
      'status', deletion_row.status,
      'attemptCount', deletion_row.attempt_count,
      'processingStartedAt', deletion_row.processing_started_at
    );
    insert into platform.audit_logs
      (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
    values
      ('admin', p_actor_id, 'account.deletion.process', 'account_deletion_request', deletion_row.id,
       p_request_id, p_reason,
       jsonb_build_object('status', previous_deletion_status, 'attemptCount', deletion_row.attempt_count - 1), result)
    returning id into audit_id_value;
    result := result || jsonb_build_object('auditLogId', audit_id_value);
  end if;

  update platform.idempotency_records
     set status = 'completed',
         resource_type = case
           when p_action in ('grant_entitlement', 'revoke_entitlement', 'restore_entitlement')
             then 'entitlement_grant'
           when p_action = 'process_account_deletion'
             then 'account_deletion_request'
           else 'user'
         end,
         resource_id = case when p_action = 'grant_entitlement' then (result->>'grantId')::uuid
                            when p_action = 'restore_entitlement' then (result->>'restoredGrantId')::uuid
                            else p_resource_id end,
         response_status = 200,
         response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.admin_customer_command(uuid, text, uuid, jsonb, text, text, text, uuid) is
  'Executes named Customer commands with role checks, domain transactions, append-only audit, and idempotent retries.';

revoke all on function public.admin_customer_command(uuid, text, uuid, jsonb, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_customer_command(uuid, text, uuid, jsonb, text, text, text, uuid)
  to service_role;
