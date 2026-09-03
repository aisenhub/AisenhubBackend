-- R1 identity foundation: application policy, application membership and
-- OAuth client bindings. These records are private platform facts; callers
-- must use controlled backend functions rather than the Data API.

alter table platform.platform_apps
  add column registration_policy text not null default 'open',
  add column membership_policy text not null default 'explicit',
  add column default_locale text,
  add column terms_version text,
  add column privacy_version text;

alter table platform.platform_apps
  add constraint platform_apps_registration_policy_check
    check (registration_policy in ('open', 'invite_only', 'admin_created', 'closed')),
  add constraint platform_apps_membership_policy_check
    check (membership_policy in ('explicit', 'create_on_first_authorization', 'create_on_verified_purchase')),
  add constraint platform_apps_default_locale_format_check
    check (default_locale is null or default_locale ~ '^[A-Za-z]{2}(-[A-Za-z0-9]{2,8})?$'),
  add constraint platform_apps_terms_version_nonempty_check
    check (terms_version is null or btrim(terms_version) <> ''),
  add constraint platform_apps_privacy_version_nonempty_check
    check (privacy_version is null or btrim(privacy_version) <> '');

comment on column platform.platform_apps.registration_policy is
  'Controls who may register for this application; it is not an authentication role.';
comment on column platform.platform_apps.membership_policy is
  'Controls how an authenticated identity becomes an application member.';

create table platform.application_memberships (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references platform.platform_apps(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending',
  created_source text not null,
  joined_at timestamptz not null default timezone('utc', now()),
  activated_at timestamptz,
  suspended_at timestamptz,
  suspended_reason text,
  left_at timestamptz,
  deleted_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint application_memberships_application_user_key unique (application_id, user_id),
  constraint application_memberships_status_check
    check (status in ('pending', 'active', 'suspended', 'left', 'deleted')),
  constraint application_memberships_source_nonempty_check
    check (btrim(created_source) <> '' and length(created_source) <= 100),
  constraint application_memberships_suspended_shape_check
    check ((status = 'suspended') = (suspended_at is not null and suspended_reason is not null and btrim(suspended_reason) <> '')),
  constraint application_memberships_active_shape_check
    check (status <> 'active' or activated_at is not null),
  constraint application_memberships_left_shape_check
    check (status not in ('left', 'deleted') or left_at is not null),
  constraint application_memberships_deleted_shape_check
    check ((status = 'deleted') = (deleted_at is not null)),
  constraint application_memberships_joined_at_check
    check (joined_at >= created_at),
  constraint application_memberships_activated_at_check
    check (activated_at is null or activated_at >= joined_at),
  constraint application_memberships_suspended_at_check
    check (suspended_at is null or suspended_at >= joined_at),
  constraint application_memberships_left_at_check
    check (left_at is null or left_at >= joined_at),
  constraint application_memberships_deleted_at_check
    check (deleted_at is null or deleted_at >= joined_at)
);

comment on table platform.application_memberships is
  'Application-scoped user membership; Global Identity existence never grants membership implicitly.';
comment on column platform.application_memberships.created_source is
  'Controlled backend reason such as admin, oauth, purchase, self_service or system.';

create index application_memberships_user_status_idx
  on platform.application_memberships (user_id, status);
create index application_memberships_application_status_idx
  on platform.application_memberships (application_id, status);

create table platform.application_oauth_clients (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references platform.platform_apps(id) on delete restrict,
  provider text not null,
  external_client_id text not null,
  client_type text not null,
  environment text not null,
  name text not null,
  status text not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint application_oauth_clients_external_id_key unique (external_client_id),
  constraint application_oauth_clients_provider_nonempty_check
    check (btrim(provider) <> '' and length(provider) <= 100),
  constraint application_oauth_clients_external_id_nonempty_check
    check (btrim(external_client_id) <> '' and length(external_client_id) <= 255),
  constraint application_oauth_clients_client_type_check
    check (client_type in ('public', 'confidential')),
  constraint application_oauth_clients_environment_check
    check (environment in ('development', 'staging', 'production')),
  constraint application_oauth_clients_name_nonempty_check
    check (btrim(name) <> '' and length(name) <= 200),
  constraint application_oauth_clients_status_check
    check (status in ('active', 'disabled'))
);

comment on table platform.application_oauth_clients is
  'Private binding from a verified provider client_id to exactly one Application.';
comment on column platform.application_oauth_clients.external_client_id is
  'Provider client_id only; client secrets and redirect configuration remain with the provider.';

create index application_oauth_clients_application_status_idx
  on platform.application_oauth_clients (application_id, status);
create index application_oauth_clients_environment_idx
  on platform.application_oauth_clients (environment, status);

create or replace function platform.prevent_referenced_app_slug_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.slug is distinct from old.slug
     and (
       exists (select 1 from platform.app_origins where app_id = old.id)
       or exists (select 1 from platform.application_oauth_clients where application_id = old.id)
     ) then
    raise exception using
      errcode = '23514',
      message = 'application slug cannot change after the application is externally referenced';
  end if;
  return new;
end;
$$;

create or replace function platform.prevent_application_membership_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.id <> old.id
     or new.application_id is distinct from old.application_id
     or new.user_id is distinct from old.user_id
     or new.created_source is distinct from old.created_source
     or new.created_by is distinct from old.created_by
     or new.joined_at is distinct from old.joined_at then
    raise exception using
      errcode = '23514',
      message = 'Application membership identity fields cannot change';
  end if;
  return new;
end;
$$;

create trigger application_memberships_prevent_identity_change
before update on platform.application_memberships
for each row
execute function platform.prevent_application_membership_identity_change();

create trigger application_memberships_set_updated_at
before update on platform.application_memberships
for each row
execute function platform.set_updated_at();

create or replace function platform.prevent_application_oauth_client_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.id <> old.id
     or new.application_id is distinct from old.application_id
     or new.provider is distinct from old.provider
     or new.external_client_id is distinct from old.external_client_id
     or new.client_type is distinct from old.client_type
     or new.environment is distinct from old.environment then
    raise exception using
      errcode = '23514',
      message = 'OAuth Client Binding identity fields cannot change';
  end if;
  return new;
end;
$$;

create trigger application_oauth_clients_prevent_identity_change
before update on platform.application_oauth_clients
for each row
execute function platform.prevent_application_oauth_client_identity_change();

create trigger application_oauth_clients_set_updated_at
before update on platform.application_oauth_clients
for each row
execute function platform.set_updated_at();

alter table platform.application_memberships enable row level security;
alter table platform.application_oauth_clients enable row level security;

revoke all on table platform.application_memberships, platform.application_oauth_clients
  from public, anon, authenticated, service_role;
revoke all on function platform.prevent_application_membership_identity_change() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_application_oauth_client_identity_change() from public, anon, authenticated, service_role;

create or replace function public.application_membership_command(
  p_actor_id uuid,
  p_action text,
  p_application_id uuid default null,
  p_user_id uuid default null,
  p_membership_id uuid default null,
  p_created_source text default 'system',
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
  membership_row platform.application_memberships%rowtype;
  app_row platform.platform_apps%rowtype;
  idempotency_row platform.idempotency_records%rowtype;
  audit_id uuid := gen_random_uuid();
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  is_admin boolean;
  target_user_id uuid;
  target_application_id uuid;
begin
  if p_actor_id is null or p_action is null or btrim(p_action) = '' then
    raise exception using errcode = '22023', message = 'Membership command actor and action are required';
  end if;
  if p_request_id is null then
    p_request_id := gen_random_uuid();
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Membership command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  is_admin := coalesce(actor_role in ('owner', 'admin', 'support'), false);

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('application.membership.command', 'user:' || p_actor_id::text, p_idempotency_key,
     p_request_hash, timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'application.membership.command'
       and record.actor_key = 'user:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The Membership command is already in progress';
    end if;
  end if;

  if p_action = 'create' then
    if p_application_id is null or p_user_id is null or p_membership_id is not null then
      raise exception using errcode = '22023', message = 'Membership creation fields are invalid';
    end if;
    if p_user_id <> p_actor_id and not is_admin then
      raise exception using errcode = '42501', message = 'Only an Admin can create membership for another user';
    end if;
    select app.* into app_row
      from platform.platform_apps as app
     where app.id = p_application_id and app.status = 'active'
     for share;
    if not found then
      raise exception using errcode = 'P0002', message = 'The active Application was not found';
    end if;
    if p_created_source is null or btrim(p_created_source) = '' or length(p_created_source) > 100 then
      raise exception using errcode = '22023', message = 'Membership creation source is invalid';
    end if;
    insert into platform.application_memberships
      (id, application_id, user_id, status, created_source, activated_at, created_by)
    values
      (gen_random_uuid(), p_application_id, p_user_id,
       case when app_row.membership_policy = 'create_on_first_authorization' then 'active' else 'pending' end,
       btrim(p_created_source),
       case when app_row.membership_policy = 'create_on_first_authorization' then timezone('utc', now()) else null end,
       p_actor_id)
    returning * into membership_row;
  else
    if p_membership_id is null then
      raise exception using errcode = '22023', message = 'Membership id is required';
    end if;
    select membership.* into membership_row
      from platform.application_memberships as membership
     where membership.id = p_membership_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Application membership was not found';
    end if;
    before_summary := jsonb_build_object(
      'id', membership_row.id,
      'applicationId', membership_row.application_id,
      'userId', membership_row.user_id,
      'status', membership_row.status
    );
    target_user_id := membership_row.user_id;
    target_application_id := membership_row.application_id;
    if p_actor_id <> target_user_id and not is_admin then
      raise exception using errcode = '42501', message = 'Membership management requires the member or an Admin';
    end if;
    if p_action = 'activate' then
      if p_actor_id <> target_user_id and not is_admin then
        raise exception using errcode = '42501', message = 'Only the member or an Admin can activate membership';
      end if;
      if membership_row.status <> 'pending' then
        raise exception using errcode = '23514', message = 'Only pending membership can be activated';
      end if;
      update platform.application_memberships
         set status = 'active', activated_at = timezone('utc', now()),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    elsif p_action = 'suspend' then
      if not is_admin then
        raise exception using errcode = '42501', message = 'Only an Admin can suspend membership';
      end if;
      if membership_row.status <> 'active' then
        raise exception using errcode = '23514', message = 'Only active membership can be suspended';
      end if;
      update platform.application_memberships
         set status = 'suspended', suspended_at = timezone('utc', now()), suspended_reason = btrim(p_reason)
       where id = membership_row.id;
    elsif p_action = 'restore' then
      if not is_admin then
        raise exception using errcode = '42501', message = 'Only an Admin can restore membership';
      end if;
      if membership_row.status <> 'suspended' then
        raise exception using errcode = '23514', message = 'Only suspended membership can be restored';
      end if;
      update platform.application_memberships
         set status = 'active', activated_at = coalesce(activated_at, timezone('utc', now())),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    elsif p_action = 'leave' then
      if membership_row.status not in ('pending', 'active', 'suspended') then
        raise exception using errcode = '23514', message = 'Only current membership can be left';
      end if;
      update platform.application_memberships
         set status = 'left', left_at = timezone('utc', now()),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    elsif p_action = 'delete' then
      if not is_admin then
        raise exception using errcode = '42501', message = 'Only an Admin can delete membership';
      end if;
      if membership_row.status not in ('left', 'suspended') then
        raise exception using errcode = '23514', message = 'Only left or suspended membership can be deleted';
      end if;
      update platform.application_memberships
         set status = 'deleted', deleted_at = timezone('utc', now()),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    else
      raise exception using errcode = '22023', message = 'The Membership command is not supported';
    end if;
    select membership.* into membership_row
      from platform.application_memberships as membership
     where membership.id = p_membership_id;
  end if;

  before_summary := case when p_action = 'create' then '{}'::jsonb else before_summary end;
  after_summary := jsonb_build_object(
    'id', membership_row.id,
    'applicationId', membership_row.application_id,
    'userId', membership_row.user_id,
    'status', membership_row.status,
    'createdSource', membership_row.created_source
  );
  result := jsonb_build_object(
    'id', membership_row.id,
    'applicationId', membership_row.application_id,
    'userId', membership_row.user_id,
    'status', membership_row.status,
    'createdSource', membership_row.created_source,
    'joinedAt', membership_row.joined_at,
    'activatedAt', membership_row.activated_at,
    'suspendedAt', membership_row.suspended_at,
    'leftAt', membership_row.left_at,
    'deletedAt', membership_row.deleted_at,
    'auditLogId', audit_id
  );

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason,
     before_summary, after_summary)
  values
    (audit_id, case when is_admin then 'admin' else 'user' end, p_actor_id,
     'applications.membership.' || p_action, 'application_membership', membership_row.id,
     p_request_id, btrim(p_reason), before_summary, after_summary);

  update platform.idempotency_records
     set status = 'completed', resource_type = 'application_membership', resource_id = membership_row.id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.application_membership_command(uuid, text, uuid, uuid, uuid, text, text, text, text, uuid) is
  'Executes application membership lifecycle transitions without changing Global Profile state.';

revoke all on function public.application_membership_command(uuid, text, uuid, uuid, uuid, text, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.application_membership_command(uuid, text, uuid, uuid, uuid, text, text, text, text, uuid)
  to service_role;

create or replace function public.list_user_application_memberships(p_user_id uuid)
returns table (
  id uuid,
  application_id uuid,
  application_slug text,
  application_name text,
  application_category text,
  application_status text,
  registration_policy text,
  membership_policy text,
  default_locale text,
  membership_status text,
  created_source text,
  joined_at timestamptz,
  activated_at timestamptz,
  suspended_at timestamptz,
  left_at timestamptz,
  deleted_at timestamptz
)
language sql
security definer
stable
set search_path = pg_catalog, platform
as $$
  select membership.id,
         app.id,
         app.slug,
         app.name,
         app.category,
         app.status,
         app.registration_policy,
         app.membership_policy,
         app.default_locale,
         membership.status,
         membership.created_source,
         membership.joined_at,
         membership.activated_at,
         membership.suspended_at,
         membership.left_at,
         membership.deleted_at
    from platform.application_memberships as membership
    join platform.platform_apps as app on app.id = membership.application_id
   where p_user_id is not null
     and membership.user_id = p_user_id
     and membership.status <> 'deleted'
   order by membership.joined_at desc, membership.id desc;
$$;

create or replace function public.admin_list_application_memberships(
  p_actor_id uuid,
  p_application_id uuid
)
returns table (
  id uuid,
  application_id uuid,
  application_slug text,
  application_name text,
  user_id uuid,
  membership_status text,
  created_source text,
  joined_at timestamptz,
  activated_at timestamptz,
  suspended_at timestamptz,
  suspended_reason text,
  left_at timestamptz,
  deleted_at timestamptz
)
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if coalesce(actor_role in ('owner', 'admin', 'support'), false) = false then
    raise exception using errcode = '42501', message = 'Application membership access requires an Admin member';
  end if;
  if p_application_id is null then
    raise exception using errcode = '22023', message = 'Application id is required';
  end if;
  return query
  select membership.id,
         app.id,
         app.slug,
         app.name,
         membership.user_id,
         membership.status,
         membership.created_source,
         membership.joined_at,
         membership.activated_at,
         membership.suspended_at,
         membership.suspended_reason,
         membership.left_at,
         membership.deleted_at
    from platform.application_memberships as membership
    join platform.platform_apps as app on app.id = membership.application_id
   where membership.application_id = p_application_id
   order by membership.joined_at desc, membership.id desc;
end;
$$;

create or replace function public.admin_list_application_oauth_clients(
  p_actor_id uuid,
  p_application_id uuid
)
returns table (
  id uuid,
  application_id uuid,
  provider text,
  external_client_id text,
  client_type text,
  environment text,
  name text,
  status text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if coalesce(actor_role in ('owner', 'admin', 'support'), false) = false then
    raise exception using errcode = '42501', message = 'OAuth client access requires an Admin member';
  end if;
  if p_application_id is null then
    raise exception using errcode = '22023', message = 'Application id is required';
  end if;
  return query
  select client.id,
         client.application_id,
         client.provider,
         client.external_client_id,
         client.client_type,
         client.environment,
         client.name,
         client.status,
         client.created_at,
         client.updated_at
    from platform.application_oauth_clients as client
   where client.application_id = p_application_id
   order by client.environment, client.name, client.id;
end;
$$;

comment on function public.list_user_application_memberships(uuid) is
  'Returns safe application memberships for one Global Identity; private membership records are never directly exposed.';
comment on function public.admin_list_application_memberships(uuid, uuid) is
  'Returns safe member summaries for an authorized Admin and one Application.';
comment on function public.admin_list_application_oauth_clients(uuid, uuid) is
  'Returns OAuth client binding metadata without provider secrets or redirect configuration.';

revoke all on function public.list_user_application_memberships(uuid) from public, anon, authenticated;
grant execute on function public.list_user_application_memberships(uuid) to service_role;
revoke all on function public.admin_list_application_memberships(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_list_application_memberships(uuid, uuid) to service_role;
revoke all on function public.admin_list_application_oauth_clients(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_list_application_oauth_clients(uuid, uuid) to service_role;
