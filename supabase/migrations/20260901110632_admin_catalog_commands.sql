-- Explicit high-risk Catalog commands. The domain state functions remain the
-- only state-transition authority; this wrapper adds Admin authorization
-- context, atomic audit history, and retry-safe idempotency.

create or replace function public.admin_catalog_command(
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
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  version_row platform.product_versions%rowtype;
  product_row platform.products%rowtype;
  origin_row platform.app_origins%rowtype;
  selected_origin platform.app_origins%rowtype;
  app_row platform.platform_apps%rowtype;
  target_id uuid;
  target_type text;
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  command_status text;
  command_published_at timestamptz;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Catalog commands require an active catalog administrator';
  end if;

  if p_action not in ('publish_product_version', 'retire_product_version',
                      'set_current_product_version', 'change_production_origin') then
    raise exception using errcode = '22023', message = 'The Catalog command is not supported';
  end if;
  if p_resource_id is null or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The Catalog command target or payload is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Catalog command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.catalog.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.catalog.command'
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
      raise exception using errcode = '40001', message = 'The Catalog command is already in progress';
    end if;
  end if;

  if p_action = 'publish_product_version' then
    if p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Publish does not accept additional fields';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product Version was not found';
    end if;
    before_summary := jsonb_build_object('id', version_row.id, 'status', version_row.status,
      'publishedAt', version_row.published_at);
    select published.product_version_id, published.status, published.published_at
      into target_id, command_status, command_published_at
      from public.publish_product_version(p_resource_id) as published;
    target_type := 'product_version';
    result := jsonb_build_object('productVersionId', target_id, 'status', command_status,
      'publishedAt', command_published_at);
    after_summary := jsonb_build_object('id', target_id, 'status', command_status,
      'publishedAt', command_published_at);
  elsif p_action = 'retire_product_version' then
    if p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Retire does not accept additional fields';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product Version was not found';
    end if;
    before_summary := jsonb_build_object('id', version_row.id, 'status', version_row.status);
    select retired.product_version_id, retired.status
      into target_id, command_status
      from public.retire_product_version(p_resource_id) as retired;
    target_type := 'product_version';
    result := jsonb_build_object('productVersionId', target_id, 'status', command_status,
      'publishedAt', null);
    after_summary := jsonb_build_object('id', target_id, 'status', command_status);
  elsif p_action = 'set_current_product_version' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key where key <> 'productVersionId')
       or p_payload->>'productVersionId' is null then
      raise exception using errcode = '22023', message = 'Set-current requires only productVersionId';
    end if;
    select product.*
      into product_row
      from platform.products as product
     where product.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product was not found';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = (p_payload->>'productVersionId')::uuid
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product Version was not found';
    end if;
    before_summary := jsonb_build_object('id', product_row.id, 'currentVersionId', product_row.current_version_id);
    select current_product.product_id, current_product.current_version_id
      into target_id, version_row.id
      from public.set_current_product_version(p_resource_id, (p_payload->>'productVersionId')::uuid)
        as current_product;
    target_type := 'product';
    result := jsonb_build_object('productId', target_id, 'currentVersionId', version_row.id);
    after_summary := jsonb_build_object('id', target_id, 'currentVersionId', version_row.id);
  elsif p_action = 'change_production_origin' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('origin', 'appSlug'))
       or p_payload->>'origin' is null or p_payload->>'appSlug' is null
       or p_payload->>'origin' !~ '^https?://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$'
       or p_payload->>'appSlug' !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      raise exception using errcode = '22023', message = 'The production Origin command fields are invalid';
    end if;
    select origin.*
      into origin_row
      from platform.app_origins as origin
     where origin.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The application Origin was not found';
    end if;
    select app.*
      into app_row
      from platform.platform_apps as app
     where app.id = origin_row.app_id
     for update;
    if not found or app_row.slug <> p_payload->>'appSlug' then
      raise exception using errcode = '22023', message = 'The App Slug does not match the application Origin';
    end if;
    before_summary := jsonb_build_object('applicationId', app_row.id, 'appSlug', app_row.slug,
      'previousProductionOrigin', (select jsonb_agg(jsonb_build_object('id', id, 'origin', origin))
        from platform.app_origins where app_id = app_row.id and environment = 'production' and is_active));
    select existing.*
      into selected_origin
      from platform.app_origins as existing
     where existing.app_id = app_row.id
       and existing.environment = 'production'
       and existing.origin = lower(p_payload->>'origin')
     for update;
    if not found then
      insert into platform.app_origins (app_id, environment, origin, is_active)
      values (app_row.id, 'production', lower(p_payload->>'origin'), true)
      returning * into selected_origin;
    end if;
    update platform.app_origins
       set is_active = (id = selected_origin.id)
     where app_id = app_row.id
       and environment = 'production';
    select origin.*
      into selected_origin
      from platform.app_origins as origin
     where origin.id = selected_origin.id;
    target_id := selected_origin.id;
    target_type := 'app_origin';
    result := jsonb_build_object('originId', selected_origin.id, 'applicationId', selected_origin.app_id,
      'appSlug', app_row.slug, 'environment', selected_origin.environment, 'origin', selected_origin.origin,
      'isActive', selected_origin.is_active, 'createdAt', selected_origin.created_at, 'updatedAt', selected_origin.updated_at);
    after_summary := jsonb_build_object('id', selected_origin.id, 'applicationId', selected_origin.app_id,
      'environment', selected_origin.environment, 'origin', selected_origin.origin, 'isActive', selected_origin.is_active);
  end if;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, 'catalog.' || p_action, target_type, target_id, p_request_id, p_reason,
     before_summary, coalesce(after_summary, '{}'::jsonb))
  returning id into command_status;

  result := result || jsonb_build_object('auditLogId', command_status::uuid);
  update platform.idempotency_records
     set status = 'completed', resource_type = target_type, resource_id = target_id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.admin_catalog_command(uuid, text, uuid, jsonb, text, text, text, uuid) is
  'Executes explicit, audited high-risk Catalog commands with domain state functions and idempotent retries.';

revoke all on function public.admin_catalog_command(uuid, text, uuid, jsonb, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_catalog_command(uuid, text, uuid, jsonb, text, text, text, uuid)
  to service_role;
