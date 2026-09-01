-- Entitlement command core and append-only audit history.

create table platform.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_type text not null,
  actor_id uuid,
  action text not null,
  target_type text not null,
  target_id uuid not null,
  request_id uuid,
  reason text not null,
  before_summary jsonb not null default '{}'::jsonb,
  after_summary jsonb not null default '{}'::jsonb,
  ip_hash text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint audit_logs_actor_type_check
    check (actor_type in ('admin', 'system', 'user', 'webhook')),
  constraint audit_logs_action_nonempty_check
    check (btrim(action) <> ''),
  constraint audit_logs_target_type_nonempty_check
    check (btrim(target_type) <> ''),
  constraint audit_logs_reason_nonempty_check
    check (btrim(reason) <> ''),
  constraint audit_logs_before_summary_object_check
    check (jsonb_typeof(before_summary) = 'object'),
  constraint audit_logs_after_summary_object_check
    check (jsonb_typeof(after_summary) = 'object')
);

comment on table platform.audit_logs is
  'Append-only authoritative audit history for backend business commands.';

create index audit_logs_target_created_idx
  on platform.audit_logs (target_type, target_id, created_at desc);

create index audit_logs_request_id_idx
  on platform.audit_logs (request_id)
  where request_id is not null;

create or replace function platform.prevent_audit_log_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'Audit logs are append-only';
end;
$$;

create trigger audit_logs_prevent_update
before update or delete on platform.audit_logs
for each row
execute function platform.prevent_audit_log_mutation();

create table platform.entitlement_restore_links (
  restores_grant_id uuid primary key references platform.entitlement_grants(id) on delete restrict,
  restored_grant_id uuid not null unique references platform.entitlement_grants(id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now())
);

comment on table platform.entitlement_restore_links is
  'One-time restore policy: one original grant can produce at most one restore grant.';

create or replace function public.grant_entitlement(
  p_user_id uuid,
  p_product_version_id uuid,
  p_source_type text,
  p_source_id uuid default null,
  p_starts_at timestamptz default timezone('utc', now()),
  p_expires_at timestamptz default null,
  p_actor_type text default 'system',
  p_actor_id uuid default null,
  p_reason text default null,
  p_restores_grant_id uuid default null,
  p_request_id uuid default null
)
returns table (
  grant_id uuid,
  source_id uuid,
  status text,
  starts_at timestamptz,
  expires_at timestamptz,
  audit_log_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  version_row platform.product_versions%rowtype;
  grant_id_value uuid := gen_random_uuid();
  audit_id_value uuid := gen_random_uuid();
  effective_source_id uuid;
begin
  if p_reason is null or btrim(p_reason) = '' then
    raise exception using
      errcode = '23514',
      message = 'An entitlement grant reason is required';
  end if;

  if p_actor_type not in ('admin', 'system', 'user', 'webhook') then
    raise exception using
      errcode = '23514',
      message = 'Invalid audit actor type';
  end if;

  select version.*
    into version_row
    from platform.product_versions as version
   where version.id = p_product_version_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Product version was not found';
  end if;

  if version_row.status <> 'published' then
    raise exception using
      errcode = '23514',
      message = 'Entitlements must reference a published product version';
  end if;

  if p_source_type in ('admin', 'admin_restore') then
    if p_actor_type <> 'admin' or p_actor_id is null then
      raise exception using
        errcode = '42501',
        message = 'Admin entitlement grants require an admin actor';
    end if;
    if p_source_id is not null then
      raise exception using
        errcode = '23514',
        message = 'Admin grant source IDs are generated from audit IDs';
    end if;
    effective_source_id := audit_id_value;
  else
    if p_source_id is null then
      raise exception using
        errcode = '23514',
        message = 'Non-admin entitlement grants require a source ID';
    end if;
    if p_restores_grant_id is not null then
      raise exception using
        errcode = '23514',
        message = 'Only admin restore grants may link an original grant';
    end if;
    effective_source_id := p_source_id;
  end if;

  if p_source_type = 'admin' and p_restores_grant_id is not null then
    raise exception using
      errcode = '23514',
      message = 'Ordinary admin grants cannot restore an original grant';
  end if;

  if p_source_type = 'admin_restore'
     and exists (
       select 1
       from platform.entitlement_restore_links as link
       where link.restores_grant_id = p_restores_grant_id
     ) then
    raise exception using
      errcode = '23505',
      message = 'The original entitlement has already been restored';
  end if;

  insert into platform.entitlement_grants
    (id, user_id, product_id, product_version_id, source_type, source_id,
     starts_at, expires_at, restores_grant_id)
  values
    (grant_id_value, p_user_id, version_row.product_id, version_row.id, p_source_type, effective_source_id,
     p_starts_at, p_expires_at, p_restores_grant_id);

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, p_actor_type, p_actor_id, 'entitlements.grant', 'entitlement_grant', grant_id_value,
     p_request_id, p_reason, '{}'::jsonb,
     jsonb_build_object(
       'grantId', grant_id_value,
       'productVersionId', version_row.id,
       'sourceType', p_source_type,
       'status', 'active'
     ));

  if p_source_type = 'admin_restore' then
    insert into platform.entitlement_restore_links (restores_grant_id, restored_grant_id)
    values (p_restores_grant_id, grant_id_value);
  end if;

  return query
  select grant_id_value, effective_source_id, 'active', p_starts_at, p_expires_at, audit_id_value;
end;
$$;

create or replace function public.revoke_entitlement(
  p_grant_id uuid,
  p_actor_type text,
  p_actor_id uuid,
  p_reason text,
  p_request_id uuid default null
)
returns table (
  grant_id uuid,
  status text,
  revoked_at timestamptz,
  audit_log_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  grant_row platform.entitlement_grants%rowtype;
  revoked_at_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
begin
  if p_reason is null or btrim(p_reason) = '' then
    raise exception using
      errcode = '23514',
      message = 'An entitlement revoke reason is required';
  end if;

  select grant_item.*
    into grant_row
    from platform.entitlement_grants as grant_item
   where grant_item.id = p_grant_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Entitlement grant was not found';
  end if;

  if grant_row.status <> 'active' then
    raise exception using
      errcode = '23514',
      message = 'Only active entitlement grants can be revoked';
  end if;

  update platform.entitlement_grants
  set status = 'revoked',
      revoked_at = revoked_at_value,
      revoke_reason = p_reason
  where id = grant_row.id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, p_actor_type, p_actor_id, 'entitlements.revoke', 'entitlement_grant', grant_row.id,
     p_request_id, p_reason,
     jsonb_build_object('grantId', grant_row.id, 'status', 'active'),
     jsonb_build_object('grantId', grant_row.id, 'status', 'revoked', 'revokedAt', revoked_at_value));

  return query
  select grant_row.id, 'revoked', revoked_at_value, audit_id_value;
end;
$$;

create or replace function public.restore_entitlement(
  p_grant_id uuid,
  p_actor_id uuid,
  p_reason text,
  p_request_id uuid default null
)
returns table (
  grant_id uuid,
  source_id uuid,
  status text,
  starts_at timestamptz,
  expires_at timestamptz,
  audit_log_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  original_grant platform.entitlement_grants%rowtype;
begin
  select grant_item.*
    into original_grant
    from platform.entitlement_grants as grant_item
   where grant_item.id = p_grant_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Entitlement grant was not found';
  end if;

  if original_grant.status <> 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Only revoked entitlement grants can be restored';
  end if;

  return query
  select restored.*
  from public.grant_entitlement(
    original_grant.user_id,
    original_grant.product_version_id,
    'admin_restore',
    null,
    timezone('utc', now()),
    original_grant.expires_at,
    'admin',
    p_actor_id,
    p_reason,
    original_grant.id,
    p_request_id
  ) as restored;
end;
$$;

comment on function public.grant_entitlement(uuid, uuid, text, uuid, timestamptz, timestamptz, text, uuid, text, uuid, uuid) is
  'Creates every entitlement source through one validated, audited transaction.';
comment on function public.revoke_entitlement(uuid, text, uuid, text, uuid) is
  'Revokes one active entitlement and writes an audit event atomically.';
comment on function public.restore_entitlement(uuid, uuid, text, uuid) is
  'Creates one new admin_restore entitlement while preserving the revoked original.';

alter table platform.audit_logs enable row level security;
alter table platform.entitlement_restore_links enable row level security;

revoke all on table platform.audit_logs, platform.entitlement_restore_links
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema platform from public, anon, authenticated, service_role;
revoke all on function platform.prevent_audit_log_mutation() from public, anon, authenticated, service_role;
revoke all on function public.grant_entitlement(uuid, uuid, text, uuid, timestamptz, timestamptz, text, uuid, text, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.revoke_entitlement(uuid, text, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.restore_entitlement(uuid, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.grant_entitlement(uuid, uuid, text, uuid, timestamptz, timestamptz, text, uuid, text, uuid, uuid)
  to service_role;
grant execute on function public.revoke_entitlement(uuid, text, uuid, text, uuid)
  to service_role;
grant execute on function public.restore_entitlement(uuid, uuid, text, uuid)
  to service_role;
