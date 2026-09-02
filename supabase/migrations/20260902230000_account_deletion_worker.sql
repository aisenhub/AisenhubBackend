-- Complete the cross-system account deletion workflow after Supabase Auth succeeds.
-- The database portion is idempotent and keeps financial/entitlement history intact.

alter table platform.feedback_requests
  alter column user_id drop not null;

comment on column platform.feedback_requests.user_id is
  'Nullable direct user link; cleared when account deletion de-identifies feedback.';

create or replace function platform.prevent_audit_log_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if tg_op = 'UPDATE'
     and current_setting('app.audit_scrub', true) = 'account_deletion'
     and old.ip_hash is not null
     and new.ip_hash is null
     and new.id is not distinct from old.id
     and new.actor_type is not distinct from old.actor_type
     and new.actor_id is not distinct from old.actor_id
     and new.action is not distinct from old.action
     and new.target_type is not distinct from old.target_type
     and new.target_id is not distinct from old.target_id
     and new.request_id is not distinct from old.request_id
     and new.reason is not distinct from old.reason
     and new.before_summary is not distinct from old.before_summary
     and new.after_summary is not distinct from old.after_summary
     and new.created_at is not distinct from old.created_at then
    return new;
  end if;

  raise exception using
    errcode = '23514',
    message = 'Audit logs are append-only';
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
  deleted_session_count integer := 0;
  anonymized_feedback_count integer := 0;
  detached_order_count integer := 0;
  disabled_admin_count integer := 0;
  result jsonb;
begin
  if p_deletion_request_id is null or p_worker_id is null then
    raise exception using errcode = '22023', message = 'A deletion request and worker are required';
  end if;

  select request_item.*
    into request_row
    from platform.account_deletion_requests as request_item
   where request_item.id = p_deletion_request_id
   for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
  end if;

  if request_row.status = 'completed' then
    return jsonb_build_object(
      'deletionRequestId', request_row.id,
      'userId', request_row.user_id,
      'status', request_row.status,
      'completedAt', request_row.completed_at,
      'idempotent', true
    );
  end if;

  if request_row.status <> 'processing' or request_row.worker_id is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'The worker does not own the processing request';
  end if;

  select profile_item.*
    into profile_row
    from platform.profiles as profile_item
   where profile_item.id = request_row.user_id
   for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The account profile was not found';
  end if;

  for grant_row in
    select grant_item.id
      from platform.entitlement_grants as grant_item
     where grant_item.user_id = request_row.user_id
       and grant_item.status = 'active'
     order by grant_item.id
     for update
  loop
    perform public.revoke_entitlement(
      grant_row.id,
      'system',
      null,
      'Account deletion de-identification',
      p_request_id
    );
    revoked_grant_count := revoked_grant_count + 1;
  end loop;

  delete from platform.platform_sessions
   where user_id = request_row.user_id;
  get diagnostics deleted_session_count = row_count;

  update platform.feedback_requests
     set user_id = null,
         title = '[deleted]',
         content = '[deleted]'
   where user_id = request_row.user_id;
  get diagnostics anonymized_feedback_count = row_count;

  update platform.orders
     set user_id = null
   where user_id = request_row.user_id;
  get diagnostics detached_order_count = row_count;

  update platform.admin_members
     set status = 'disabled',
         disabled_at = coalesce(disabled_at, now_value),
         created_by = case when created_by = request_row.user_id then null else created_by end
   where user_id = request_row.user_id
     and status = 'active';
  get diagnostics disabled_admin_count = row_count;

  perform set_config('app.audit_scrub', 'account_deletion', true);
  update platform.audit_logs
     set ip_hash = null
   where actor_id = request_row.user_id
      or (target_type = 'user' and target_id = request_row.user_id);
  perform set_config('app.audit_scrub', '', true);

  update platform.profiles
     set display_name = null,
         avatar_url = null,
         locale = null,
         status = 'deleted',
         deleted_at = coalesce(deleted_at, now_value)
   where id = request_row.user_id;

  update platform.account_deletion_requests
     set status = 'completed',
         completed_at = coalesce(completed_at, now_value),
         worker_id = null,
         processing_started_at = null,
         next_attempt_at = null,
         last_error_code = null
   where id = request_row.id
  returning * into request_row;

  result := jsonb_build_object(
    'deletionRequestId', request_row.id,
    'userId', request_row.user_id,
    'status', request_row.status,
    'completedAt', request_row.completed_at,
    'revokedGrantCount', revoked_grant_count,
    'deletedSessionCount', deleted_session_count,
    'anonymizedFeedbackCount', anonymized_feedback_count,
    'detachedOrderCount', detached_order_count,
    'disabledAdminCount', disabled_admin_count,
    'idempotent', false
  );

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'system', null, 'account.deletion.completed', 'account_deletion_request', request_row.id,
     p_request_id, 'Account deletion and de-identification completed',
     jsonb_build_object('profileStatus', profile_row.status, 'requestStatus', 'processing'),
     result);

  return result;
end;
$$;

comment on function public.complete_account_deletion_request(uuid, uuid, uuid) is
  'Completes one worker-owned deletion transaction after Auth anonymization, preserving financial facts and making the operation idempotent.';

revoke all on function public.complete_account_deletion_request(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.complete_account_deletion_request(uuid, uuid, uuid)
  to service_role;
