-- Explicit Admin draft commands. These are not a generic table update API:
-- each action owns its writable field allow-list and lifecycle invariants.

create or replace function public.admin_catalog_draft_command(
  p_actor_id uuid,
  p_action text,
  p_resource_id uuid default null,
  p_parent_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_expected_updated_at timestamptz default null,
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
  target_id uuid;
  target_type text;
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  status_code integer := 200;
  app_row platform.platform_apps%rowtype;
  origin_row platform.app_origins%rowtype;
  feature_row platform.features%rowtype;
  product_row platform.products%rowtype;
  version_row platform.product_versions%rowtype;
  price_row platform.product_prices%rowtype;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Catalog draft editing requires an active catalog administrator';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The draft payload must be an object';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A draft change reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.catalog.draft', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.catalog.draft'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
  end if;

  if p_action = 'create_application' then
    if p_resource_id is not null or p_parent_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('slug', 'name', 'category', 'metadata')) then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    if p_payload->>'slug' is null or p_payload->>'slug' !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
       or btrim(coalesce(p_payload->>'name', '')) = ''
       or btrim(coalesce(p_payload->>'category', '')) = '' then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    if p_payload ? 'metadata' and jsonb_typeof(p_payload->'metadata') <> 'object' then
      raise exception using errcode = '22023', message = 'Application metadata must be an object';
    end if;
    insert into platform.platform_apps (slug, name, category, metadata)
    values (p_payload->>'slug', btrim(p_payload->>'name'), btrim(p_payload->>'category'), coalesce(p_payload->'metadata', '{}'::jsonb))
    returning * into app_row;
    target_id := app_row.id;
    target_type := 'platform_app';
    status_code := 201;
    result := jsonb_build_object('id', app_row.id, 'slug', app_row.slug, 'name', app_row.name, 'category', app_row.category,
      'status', app_row.status, 'originCount', 0, 'createdAt', app_row.created_at, 'updatedAt', app_row.updated_at);
    after_summary := jsonb_build_object('id', app_row.id, 'slug', app_row.slug, 'name', app_row.name, 'category', app_row.category);
  elsif p_action = 'update_application' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('name', 'category', 'metadata'))
       or p_expected_updated_at is null then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    select app.* into app_row from platform.platform_apps as app where app.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The application was not found'; end if;
    if app_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The application changed before this draft update';
    end if;
    before_summary := jsonb_build_object('id', app_row.id, 'name', app_row.name, 'category', app_row.category);
    update platform.platform_apps
       set name = case when p_payload ? 'name' then btrim(p_payload->>'name') else name end,
           category = case when p_payload ? 'category' then btrim(p_payload->>'category') else category end,
           metadata = case when p_payload ? 'metadata' then p_payload->'metadata' else metadata end
     where id = app_row.id;
    select app.* into app_row from platform.platform_apps as app where app.id = p_resource_id;
    if btrim(app_row.name) = '' or btrim(app_row.category) = '' or jsonb_typeof(app_row.metadata) <> 'object' then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    target_id := app_row.id;
    target_type := 'platform_app';
    result := jsonb_build_object('id', app_row.id, 'slug', app_row.slug, 'name', app_row.name, 'category', app_row.category,
      'status', app_row.status, 'originCount', (select count(*)::integer from platform.app_origins where app_id = app_row.id and is_active),
      'createdAt', app_row.created_at, 'updatedAt', app_row.updated_at);
    after_summary := jsonb_build_object('id', app_row.id, 'name', app_row.name, 'category', app_row.category);
  elsif p_action = 'create_origin' then
    if p_resource_id is not null or p_parent_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('environment', 'origin')) then
      raise exception using errcode = '22023', message = 'The Origin draft fields are invalid';
    end if;
    if not exists (select 1 from platform.platform_apps where id = p_parent_id) then
      raise exception using errcode = 'P0002', message = 'The application was not found';
    end if;
    if p_payload->>'environment' not in ('development', 'staging')
       or p_payload->>'origin' !~ '^https?://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$' then
      raise exception using errcode = '22023', message = 'The Origin draft fields are invalid';
    end if;
    insert into platform.app_origins (app_id, environment, origin)
    values (p_parent_id, p_payload->>'environment', lower(p_payload->>'origin'))
    returning * into origin_row;
    target_id := origin_row.id;
    target_type := 'app_origin';
    status_code := 201;
    result := jsonb_build_object('id', origin_row.id, 'appId', origin_row.app_id,
      'appSlug', (select slug from platform.platform_apps where id = origin_row.app_id), 'environment', origin_row.environment,
      'origin', origin_row.origin, 'isActive', origin_row.is_active, 'createdAt', origin_row.created_at, 'updatedAt', origin_row.updated_at);
    after_summary := jsonb_build_object('id', origin_row.id, 'appId', origin_row.app_id, 'environment', origin_row.environment, 'origin', origin_row.origin);
  elsif p_action = 'update_origin' then
    if p_resource_id is null or p_expected_updated_at is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('isActive'))
       or not (p_payload ? 'isActive') or jsonb_typeof(p_payload->'isActive') <> 'boolean' then
      raise exception using errcode = '22023', message = 'The Origin draft fields are invalid';
    end if;
    select origin.* into origin_row from platform.app_origins as origin where origin.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Origin was not found'; end if;
    if origin_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The Origin changed before this draft update';
    end if;
    before_summary := jsonb_build_object('id', origin_row.id, 'isActive', origin_row.is_active);
    update platform.app_origins set is_active = (p_payload->>'isActive')::boolean where id = origin_row.id;
    select origin.* into origin_row from platform.app_origins as origin where origin.id = p_resource_id;
    target_id := origin_row.id;
    target_type := 'app_origin';
    result := jsonb_build_object('id', origin_row.id, 'appId', origin_row.app_id,
      'appSlug', (select slug from platform.platform_apps where id = origin_row.app_id), 'environment', origin_row.environment,
      'origin', origin_row.origin, 'isActive', origin_row.is_active, 'createdAt', origin_row.created_at, 'updatedAt', origin_row.updated_at);
    after_summary := jsonb_build_object('id', origin_row.id, 'isActive', origin_row.is_active);
  elsif p_action = 'create_feature' then
    if p_resource_id is not null or p_parent_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('appId', 'code', 'name', 'valueType', 'mergeStrategy')) then
      raise exception using errcode = '22023', message = 'The Feature draft fields are invalid';
    end if;
    if p_payload->>'code' is null or p_payload->>'code' !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
       or btrim(coalesce(p_payload->>'name', '')) = ''
       or p_payload->>'valueType' not in ('boolean', 'integer', 'string', 'json')
       or p_payload->>'mergeStrategy' not in ('any_true', 'sum', 'max', 'min', 'latest') then
      raise exception using errcode = '22023', message = 'The Feature draft fields are invalid';
    end if;
    insert into platform.features (app_id, code, name, value_type, merge_strategy)
    values (case when p_payload ? 'appId' then (p_payload->>'appId')::uuid else null end,
      p_payload->>'code', btrim(p_payload->>'name'), p_payload->>'valueType', p_payload->>'mergeStrategy')
    returning * into feature_row;
    target_id := feature_row.id;
    target_type := 'feature';
    status_code := 201;
    result := jsonb_build_object('id', feature_row.id, 'appSlug', (select slug from platform.platform_apps where id = feature_row.app_id),
      'code', feature_row.code, 'name', feature_row.name, 'valueType', feature_row.value_type, 'status', feature_row.status,
      'mergeStrategy', feature_row.merge_strategy, 'createdAt', feature_row.created_at);
    after_summary := jsonb_build_object('id', feature_row.id, 'code', feature_row.code, 'name', feature_row.name);
  elsif p_action = 'update_feature' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('name', 'mergeStrategy')) then
      raise exception using errcode = '22023', message = 'The Feature draft fields are invalid';
    end if;
    select feature.* into feature_row from platform.features as feature where feature.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Feature was not found'; end if;
    before_summary := jsonb_build_object('id', feature_row.id, 'name', feature_row.name, 'mergeStrategy', feature_row.merge_strategy);
    update platform.features
       set name = case when p_payload ? 'name' then btrim(p_payload->>'name') else name end,
           merge_strategy = case when p_payload ? 'mergeStrategy' then p_payload->>'mergeStrategy' else merge_strategy end
     where id = feature_row.id;
    select feature.* into feature_row from platform.features as feature where feature.id = p_resource_id;
    if btrim(feature_row.name) = '' then raise exception using errcode = '22023', message = 'The Feature draft fields are invalid'; end if;
    target_id := feature_row.id;
    target_type := 'feature';
    result := jsonb_build_object('id', feature_row.id, 'appSlug', (select slug from platform.platform_apps where id = feature_row.app_id),
      'code', feature_row.code, 'name', feature_row.name, 'valueType', feature_row.value_type, 'status', feature_row.status,
      'mergeStrategy', feature_row.merge_strategy, 'createdAt', feature_row.created_at);
    after_summary := jsonb_build_object('id', feature_row.id, 'name', feature_row.name, 'mergeStrategy', feature_row.merge_strategy);
  elsif p_action = 'create_product' then
    if p_resource_id is not null or p_parent_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('sku', 'name', 'billingType', 'entitlementPolicy')) then
      raise exception using errcode = '22023', message = 'The Product draft fields are invalid';
    end if;
    if p_payload->>'sku' is null or p_payload->>'sku' !~ '^[A-Z0-9][A-Z0-9_-]*$'
       or btrim(coalesce(p_payload->>'name', '')) = ''
       or p_payload->>'billingType' not in ('one_time', 'subscription', 'credits')
       or coalesce(p_payload->>'entitlementPolicy', 'snapshot') not in ('snapshot', 'all_apps_access') then
      raise exception using errcode = '22023', message = 'The Product draft fields are invalid';
    end if;
    insert into platform.products (sku, name, billing_type, entitlement_policy)
    values (p_payload->>'sku', btrim(p_payload->>'name'), p_payload->>'billingType', coalesce(p_payload->>'entitlementPolicy', 'snapshot'))
    returning * into product_row;
    target_id := product_row.id;
    target_type := 'product';
    status_code := 201;
    result := jsonb_build_object('id', product_row.id, 'sku', product_row.sku, 'name', product_row.name, 'billingType', product_row.billing_type,
      'status', product_row.status, 'currentVersion', null);
    after_summary := jsonb_build_object('id', product_row.id, 'sku', product_row.sku, 'name', product_row.name);
  elsif p_action = 'update_product' then
    if p_resource_id is null or p_expected_updated_at is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('name', 'billingType', 'entitlementPolicy')) then
      raise exception using errcode = '22023', message = 'The Product draft fields are invalid';
    end if;
    select product.* into product_row from platform.products as product where product.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Product was not found'; end if;
    if product_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The Product changed before this draft update';
    end if;
    if product_row.status <> 'draft' then raise exception using errcode = '23514', message = 'Only draft products can be edited'; end if;
    before_summary := jsonb_build_object('id', product_row.id, 'name', product_row.name, 'billingType', product_row.billing_type, 'entitlementPolicy', product_row.entitlement_policy);
    update platform.products
       set name = case when p_payload ? 'name' then btrim(p_payload->>'name') else name end,
           billing_type = case when p_payload ? 'billingType' then p_payload->>'billingType' else billing_type end,
           entitlement_policy = case when p_payload ? 'entitlementPolicy' then p_payload->>'entitlementPolicy' else entitlement_policy end
     where id = product_row.id;
    select product.* into product_row from platform.products as product where product.id = p_resource_id;
    if btrim(product_row.name) = '' then raise exception using errcode = '22023', message = 'The Product draft fields are invalid'; end if;
    target_id := product_row.id;
    target_type := 'product';
    result := jsonb_build_object('id', product_row.id, 'sku', product_row.sku, 'name', product_row.name, 'billingType', product_row.billing_type,
      'status', product_row.status, 'currentVersion', null);
    after_summary := jsonb_build_object('id', product_row.id, 'name', product_row.name, 'billingType', product_row.billing_type, 'entitlementPolicy', product_row.entitlement_policy);
  elsif p_action = 'create_product_version' then
    if p_resource_id is not null or p_parent_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('version', 'accessDurationDays', 'salesTerms')) then
      raise exception using errcode = '22023', message = 'The Product Version draft fields are invalid';
    end if;
    if not exists (select 1 from platform.products where id = p_parent_id) or p_payload->>'version' is null then
      raise exception using errcode = '22023', message = 'The Product Version draft fields are invalid';
    end if;
    if p_payload ? 'salesTerms' and jsonb_typeof(p_payload->'salesTerms') <> 'object' then
      raise exception using errcode = '22023', message = 'Sales terms must be an object';
    end if;
    insert into platform.product_versions (product_id, version, access_duration_days, sales_terms)
    values (p_parent_id, (p_payload->>'version')::integer,
      case when p_payload ? 'accessDurationDays' then (p_payload->>'accessDurationDays')::integer else null end,
      coalesce(p_payload->'salesTerms', '{}'::jsonb))
    returning * into version_row;
    target_id := version_row.id;
    target_type := 'product_version';
    status_code := 201;
    result := jsonb_build_object('id', version_row.id, 'productId', version_row.product_id,
      'productSku', (select sku from platform.products where id = version_row.product_id), 'version', version_row.version,
      'status', version_row.status, 'publishedAt', version_row.published_at);
    after_summary := jsonb_build_object('id', version_row.id, 'productId', version_row.product_id, 'version', version_row.version);
  elsif p_action = 'update_product_version' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('accessDurationDays', 'salesTerms')) then
      raise exception using errcode = '22023', message = 'The Product Version draft fields are invalid';
    end if;
    select version.* into version_row from platform.product_versions as version where version.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Product Version was not found'; end if;
    if version_row.status <> 'draft' then raise exception using errcode = '23514', message = 'Only draft product versions can be edited'; end if;
    if p_payload ? 'salesTerms' and jsonb_typeof(p_payload->'salesTerms') <> 'object' then
      raise exception using errcode = '22023', message = 'Sales terms must be an object';
    end if;
    update platform.product_versions
       set access_duration_days = case when p_payload ? 'accessDurationDays' then (p_payload->>'accessDurationDays')::integer else access_duration_days end,
           sales_terms = case when p_payload ? 'salesTerms' then p_payload->'salesTerms' else sales_terms end
     where id = version_row.id;
    select version.* into version_row from platform.product_versions as version where version.id = p_resource_id;
    target_id := version_row.id;
    target_type := 'product_version';
    result := jsonb_build_object('id', version_row.id, 'productId', version_row.product_id,
      'productSku', (select sku from platform.products where id = version_row.product_id), 'version', version_row.version,
      'status', version_row.status, 'publishedAt', version_row.published_at);
    after_summary := jsonb_build_object('id', version_row.id, 'accessDurationDays', version_row.access_duration_days);
  elsif p_action = 'create_price' then
    if p_resource_id is not null or p_parent_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('currency', 'amountMinor', 'channel', 'externalPriceId', 'validFrom', 'validUntil')) then
      raise exception using errcode = '22023', message = 'The Price draft fields are invalid';
    end if;
    if not exists (select 1 from platform.product_versions where id = p_parent_id)
       or p_payload->>'currency' !~ '^[A-Z]{3}$' or p_payload->>'amountMinor' is null
       or p_payload->>'channel' is null then
      raise exception using errcode = '22023', message = 'The Price draft fields are invalid';
    end if;
    insert into platform.product_prices (product_version_id, currency, amount_minor, channel, external_price_id, valid_from, valid_until)
    values (p_parent_id, p_payload->>'currency', (p_payload->>'amountMinor')::bigint, p_payload->>'channel',
      nullif(p_payload->>'externalPriceId', ''),
      coalesce(case when p_payload ? 'validFrom' then (p_payload->>'validFrom')::timestamptz else null end, timezone('utc', now())),
      case when p_payload ? 'validUntil' then (p_payload->>'validUntil')::timestamptz else null end)
    returning * into price_row;
    target_id := price_row.id;
    target_type := 'product_price';
    status_code := 201;
    result := jsonb_build_object('id', price_row.id, 'productId', (select product_id from platform.product_versions where id = price_row.product_version_id),
      'productSku', (select product.sku from platform.products as product join platform.product_versions as version on version.product_id = product.id where version.id = price_row.product_version_id),
      'productVersion', (select version from platform.product_versions where id = price_row.product_version_id), 'currency', price_row.currency,
      'amountMinor', price_row.amount_minor, 'channel', price_row.channel, 'externalPriceId', price_row.external_price_id,
      'status', price_row.status, 'validFrom', price_row.valid_from, 'validUntil', price_row.valid_until, 'createdAt', price_row.created_at, 'updatedAt', price_row.updated_at);
    after_summary := jsonb_build_object('id', price_row.id, 'productVersionId', price_row.product_version_id, 'currency', price_row.currency, 'amountMinor', price_row.amount_minor, 'channel', price_row.channel);
  elsif p_action = 'update_price' then
    if p_resource_id is null or p_expected_updated_at is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('currency', 'amountMinor', 'channel', 'externalPriceId', 'validFrom', 'validUntil')) then
      raise exception using errcode = '22023', message = 'The Price draft fields are invalid';
    end if;
    select price.* into price_row from platform.product_prices as price where price.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Price was not found'; end if;
    if price_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The Price changed before this draft update';
    end if;
    if price_row.status <> 'draft' then raise exception using errcode = '23514', message = 'Only draft prices can be edited'; end if;
    before_summary := jsonb_build_object('id', price_row.id, 'currency', price_row.currency, 'amountMinor', price_row.amount_minor, 'channel', price_row.channel);
    update platform.product_prices
       set currency = case when p_payload ? 'currency' then p_payload->>'currency' else currency end,
           amount_minor = case when p_payload ? 'amountMinor' then (p_payload->>'amountMinor')::bigint else amount_minor end,
           channel = case when p_payload ? 'channel' then p_payload->>'channel' else channel end,
           external_price_id = case when p_payload ? 'externalPriceId' then nullif(p_payload->>'externalPriceId', '') else external_price_id end,
           valid_from = case when p_payload ? 'validFrom' then (p_payload->>'validFrom')::timestamptz else valid_from end,
           valid_until = case when p_payload ? 'validUntil' then (p_payload->>'validUntil')::timestamptz else valid_until end
     where id = price_row.id;
    select price.* into price_row from platform.product_prices as price where price.id = p_resource_id;
    target_id := price_row.id;
    target_type := 'product_price';
    result := jsonb_build_object('id', price_row.id, 'productId', (select product_id from platform.product_versions where id = price_row.product_version_id),
      'productSku', (select product.sku from platform.products as product join platform.product_versions as version on version.product_id = product.id where version.id = price_row.product_version_id),
      'productVersion', (select version from platform.product_versions where id = price_row.product_version_id), 'currency', price_row.currency,
      'amountMinor', price_row.amount_minor, 'channel', price_row.channel, 'externalPriceId', price_row.external_price_id,
      'status', price_row.status, 'validFrom', price_row.valid_from, 'validUntil', price_row.valid_until, 'createdAt', price_row.created_at, 'updatedAt', price_row.updated_at);
    after_summary := jsonb_build_object('id', price_row.id, 'currency', price_row.currency, 'amountMinor', price_row.amount_minor, 'channel', price_row.channel);
  else
    raise exception using errcode = '22023', message = 'The draft command is not supported';
  end if;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, p_action, target_type, target_id, p_request_id, p_reason, before_summary, coalesce(after_summary, result));

  update platform.idempotency_records
     set status = 'completed', resource_type = target_type, resource_id = target_id,
         response_status = status_code, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.admin_catalog_draft_command(uuid, text, uuid, uuid, jsonb, timestamptz, text, text, text, uuid) is
  'Executes explicit, audited Catalog draft create/edit actions with allowlisted fields and idempotent retries.';

revoke all on function public.admin_catalog_draft_command(uuid, text, uuid, uuid, jsonb, timestamptz, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_catalog_draft_command(uuid, text, uuid, uuid, jsonb, timestamptz, text, text, text, uuid) to service_role;
