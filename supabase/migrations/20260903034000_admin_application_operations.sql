-- Admin application operations are explicit, role-checked commands. The private
-- membership and OAuth binding tables remain inaccessible to every client role.

create or replace function public.admin_application_membership_command(
  p_actor_id uuid,
  p_action text,
  p_application_id uuid default null,
  p_user_id uuid default null,
  p_membership_id uuid default null,
  p_reason text default null,
  p_idempotency_key text default null,
  p_request_hash text default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  membership_application_id uuid;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Application membership commands require an owner or administrator';
  end if;
  if p_action not in ('create', 'suspend', 'restore', 'delete') then
    raise exception using errcode = '22023', message = 'The Application membership command is not supported';
  end if;
  if p_action = 'create' then
    if p_application_id is null or p_user_id is null or p_membership_id is not null then
      raise exception using errcode = '22023', message = 'Membership creation fields are invalid';
    end if;
  else
    if p_membership_id is null or p_application_id is null then
      raise exception using errcode = '22023', message = 'Membership target fields are required';
    end if;
    select membership.application_id into membership_application_id
      from platform.application_memberships as membership
     where membership.id = p_membership_id;
    if membership_application_id is null then
      raise exception using errcode = 'P0002', message = 'The Application membership was not found';
    end if;
    if membership_application_id <> p_application_id then
      raise exception using errcode = '42501', message = 'The membership does not belong to the requested Application';
    end if;
  end if;

  return public.application_membership_command(
    p_actor_id,
    p_action,
    p_application_id,
    p_user_id,
    p_membership_id,
    'admin',
    p_reason,
    p_idempotency_key,
    p_request_hash,
    p_request_id
  );
end;
$$;

comment on function public.admin_application_membership_command(uuid, text, uuid, uuid, uuid, text, text, text, uuid) is
  'Executes owner/admin-only application membership lifecycle commands through the audited domain command.';

revoke all on function public.admin_application_membership_command(uuid, text, uuid, uuid, uuid, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_application_membership_command(uuid, text, uuid, uuid, uuid, text, text, text, uuid)
  to service_role;

create or replace function public.admin_oauth_client_command(
  p_actor_id uuid,
  p_action text,
  p_application_id uuid,
  p_client_id uuid default null,
  p_provider text default null,
  p_external_client_id text default null,
  p_client_type text default null,
  p_environment text default null,
  p_name text default null,
  p_reason text default null,
  p_idempotency_key text default null,
  p_request_hash text default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  app_row platform.platform_apps%rowtype;
  client_row platform.application_oauth_clients%rowtype;
  idempotency_row platform.idempotency_records%rowtype;
  audit_id uuid := gen_random_uuid();
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'OAuth client commands require an owner or administrator';
  end if;
  if p_action not in ('create', 'disable', 'restore') or p_application_id is null then
    raise exception using errcode = '22023', message = 'The OAuth client command fields are invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'An OAuth client command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.oauth_client.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.* into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.oauth_client.command'
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
      raise exception using errcode = '40001', message = 'The OAuth client command is already in progress';
    end if;
  end if;

  select app.* into app_row
    from platform.platform_apps as app
   where app.id = p_application_id
     and app.status = 'active'
   for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'The active Application was not found';
  end if;

  if p_action = 'create' then
    if p_client_id is not null or p_provider is null or btrim(p_provider) = ''
       or p_external_client_id is null or btrim(p_external_client_id) = ''
       or p_client_type is null or p_environment is null or p_name is null or btrim(p_name) = '' then
      raise exception using errcode = '22023', message = 'OAuth client creation fields are invalid';
    end if;
    insert into platform.application_oauth_clients
      (application_id, provider, external_client_id, client_type, environment, name)
    values
      (p_application_id, btrim(p_provider), btrim(p_external_client_id), p_client_type,
       p_environment, btrim(p_name))
    returning * into client_row;
  else
    if p_client_id is null then
      raise exception using errcode = '22023', message = 'OAuth client id is required';
    end if;
    select client.* into client_row
      from platform.application_oauth_clients as client
     where client.id = p_client_id
       and client.application_id = p_application_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The OAuth client binding was not found';
    end if;
    before_summary := jsonb_build_object('id', client_row.id, 'status', client_row.status);
    if p_action = 'disable' then
      if client_row.status <> 'active' then
        raise exception using errcode = '23514', message = 'Only an active OAuth client can be disabled';
      end if;
      update platform.application_oauth_clients set status = 'disabled' where id = client_row.id;
    elsif client_row.status <> 'disabled' then
      raise exception using errcode = '23514', message = 'Only a disabled OAuth client can be restored';
    else
      update platform.application_oauth_clients set status = 'active' where id = client_row.id;
    end if;
    select client.* into client_row from platform.application_oauth_clients as client where client.id = p_client_id;
  end if;

  after_summary := jsonb_build_object('id', client_row.id, 'applicationId', client_row.application_id,
    'provider', client_row.provider, 'externalClientId', client_row.external_client_id,
    'clientType', client_row.client_type, 'environment', client_row.environment,
    'name', client_row.name, 'status', client_row.status);
  result := jsonb_build_object(
    'id', client_row.id,
    'applicationId', client_row.application_id,
    'provider', client_row.provider,
    'externalClientId', client_row.external_client_id,
    'clientType', client_row.client_type,
    'environment', client_row.environment,
    'name', client_row.name,
    'status', client_row.status,
    'createdAt', client_row.created_at,
    'updatedAt', client_row.updated_at
  );
  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason,
     before_summary, after_summary)
  values
    (audit_id, 'admin', p_actor_id, 'applications.oauth_client.' || p_action,
     'application_oauth_client', client_row.id, p_request_id, btrim(p_reason),
     before_summary, after_summary);
  result := result || jsonb_build_object('auditLogId', audit_id);
  update platform.idempotency_records
     set status = 'completed', resource_type = 'application_oauth_client', resource_id = client_row.id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.admin_oauth_client_command(uuid, text, uuid, uuid, text, text, text, text, text, text, text, text, uuid) is
  'Executes owner/admin-only OAuth client binding commands without accepting or storing provider secrets.';

revoke all on function public.admin_oauth_client_command(uuid, text, uuid, uuid, text, text, text, text, text, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_oauth_client_command(uuid, text, uuid, uuid, text, text, text, text, text, text, text, text, uuid)
  to service_role;
