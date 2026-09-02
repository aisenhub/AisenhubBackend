-- Bounded cleanup for short-lived security context and expired idempotency responses.
-- Orders, payments, grants, redemptions, and audit facts remain retained.

create index if not exists redemptions_ip_hash_redeemed_at_idx
  on platform.redemptions (redeemed_at)
  where ip_hash is not null;

create index if not exists audit_logs_ip_hash_created_at_idx
  on platform.audit_logs (created_at)
  where ip_hash is not null;

create or replace function platform.prevent_audit_log_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if tg_op = 'UPDATE'
     and current_setting('app.audit_scrub', true) in ('account_deletion', 'retention_cleanup')
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

create or replace function platform.prevent_redemption_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if tg_op = 'UPDATE'
     and current_setting('app.retention_cleanup', true) = 'retention_cleanup'
     and old.ip_hash is not null
     and new.ip_hash is null
     and new.id is not distinct from old.id
     and new.code_id is not distinct from old.code_id
     and new.batch_id is not distinct from old.batch_id
     and new.user_id is not distinct from old.user_id
     and new.grant_id is not distinct from old.grant_id
     and new.idempotency_record_id is not distinct from old.idempotency_record_id
     and new.redeemed_at is not distinct from old.redeemed_at then
    return new;
  end if;

  raise exception using
    errcode = '23514',
    message = 'Redemption receipts are immutable';
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
  session_count integer := 0;
  redemption_ip_hash_count integer := 0;
  audit_ip_hash_count integer := 0;
  idempotency_response_count integer := 0;
  idempotency_deleted_count integer := 0;
  idempotency_row platform.idempotency_records%rowtype;
begin
  if p_session_expired_before is null
     or p_security_context_before is null
     or p_idempotency_response_before is null then
    raise exception using errcode = '22023', message = 'Cleanup cutoffs are required';
  end if;
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 1000 then
    raise exception using errcode = '22023', message = 'Cleanup batch size is invalid';
  end if;

  select count(*)::integer
    into session_count
    from (
      select sessions.id
        from platform.platform_sessions as sessions
       where sessions.expires_at <= p_session_expired_before
       order by sessions.expires_at, sessions.id
       limit p_batch_size
    ) as candidates;

  select count(*)::integer
    into redemption_ip_hash_count
    from (
      select redemption.id
        from platform.redemptions as redemption
       where redemption.ip_hash is not null
         and redemption.redeemed_at <= p_security_context_before
       order by redemption.redeemed_at, redemption.id
       limit p_batch_size
    ) as candidates;

  select count(*)::integer
    into audit_ip_hash_count
    from (
      select audit.id
        from platform.audit_logs as audit
       where audit.ip_hash is not null
         and audit.created_at <= p_security_context_before
       order by audit.created_at, audit.id
       limit p_batch_size
    ) as candidates;

  select count(*)::integer
    into idempotency_response_count
    from (
      select record.id
        from platform.idempotency_records as record
       where record.status = 'completed'
         and record.response_body is not null
         and record.expires_at <= p_idempotency_response_before
       order by record.expires_at, record.id
       limit p_batch_size
    ) as candidates;

  if p_dry_run then
    return jsonb_build_object(
      'dryRun', true,
      'sessionCount', session_count,
      'redemptionIpHashCount', redemption_ip_hash_count,
      'auditIpHashCount', audit_ip_hash_count,
      'idempotencyResponseCount', idempotency_response_count,
      'idempotencyDeletedCount', 0,
      'batchSize', p_batch_size
    );
  end if;

  delete from platform.platform_sessions as sessions
   where sessions.id in (
     select candidate.id
       from platform.platform_sessions as candidate
      where candidate.expires_at <= p_session_expired_before
      order by candidate.expires_at, candidate.id
      limit p_batch_size
      for update skip locked
   );
  get diagnostics session_count = row_count;

  set local app.retention_cleanup = 'retention_cleanup';

  with candidates as (
    select redemption.id
      from platform.redemptions as redemption
     where redemption.ip_hash is not null
       and redemption.redeemed_at <= p_security_context_before
     order by redemption.redeemed_at, redemption.id
     limit p_batch_size
     for update skip locked
  )
  update platform.redemptions as redemption
     set ip_hash = null
    from candidates
   where redemption.id = candidates.id;
  get diagnostics redemption_ip_hash_count = row_count;

  set local app.audit_scrub = 'retention_cleanup';

  with candidates as (
    select audit.id
      from platform.audit_logs as audit
     where audit.ip_hash is not null
       and audit.created_at <= p_security_context_before
     order by audit.created_at, audit.id
     limit p_batch_size
     for update skip locked
  )
  update platform.audit_logs as audit
     set ip_hash = null
    from candidates
   where audit.id = candidates.id;
  get diagnostics audit_ip_hash_count = row_count;

  for idempotency_row in
    select record.*
      from platform.idempotency_records as record
     where record.status = 'completed'
       and record.response_body is not null
       and record.expires_at <= p_idempotency_response_before
     order by record.expires_at, record.id
     limit p_batch_size
     for update skip locked
  loop
    if exists (
      select 1 from platform.platform_sessions as sessions
       where sessions.idempotency_record_id = idempotency_row.id
    ) or exists (
      select 1 from platform.redemptions as redemption
       where redemption.idempotency_record_id = idempotency_row.id
    ) then
      update platform.idempotency_records
         set response_body = null,
             response_status = null
       where id = idempotency_row.id;
    else
      delete from platform.idempotency_records
       where id = idempotency_row.id;
      idempotency_deleted_count := idempotency_deleted_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'dryRun', false,
    'sessionCount', session_count,
    'redemptionIpHashCount', redemption_ip_hash_count,
    'auditIpHashCount', audit_ip_hash_count,
    'idempotencyResponseCount', idempotency_response_count,
    'idempotencyDeletedCount', idempotency_deleted_count,
    'batchSize', p_batch_size
  );
end;
$$;

comment on function public.run_retention_cleanup(timestamptz, timestamptz, timestamptz, integer, boolean) is
  'Runs one bounded, retry-safe cleanup batch for expired sessions, short-lived IP hashes, and expired idempotency response bodies.';

revoke all on function public.run_retention_cleanup(timestamptz, timestamptz, timestamptz, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.run_retention_cleanup(timestamptz, timestamptz, timestamptz, integer, boolean)
  to service_role;
