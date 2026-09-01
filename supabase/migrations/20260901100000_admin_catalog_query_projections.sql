-- Read-only Catalog and Redemption projections. Every resource and sort key is explicit;
-- callers cannot provide table names, columns, or SQL expressions.

create or replace function public.admin_query_catalog_resource(
  p_actor_id uuid,
  p_resource text,
  p_cursor text default null,
  p_limit integer default 25,
  p_search text default null,
  p_status text default null,
  p_sort text default 'createdAt',
  p_direction text default 'desc'
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  cursor_value text;
  cursor_id uuid;
  cursor_json jsonb;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  if p_resource not in ('origins', 'features', 'product-versions', 'prices', 'redemption-batches', 'redemption-codes') then
    raise exception using errcode = '22023', message = 'The Catalog resource is not supported';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'The Catalog page size is invalid';
  end if;
  if p_direction not in ('asc', 'desc') then
    raise exception using errcode = '22023', message = 'The Catalog sort direction is invalid';
  end if;
  if p_search is not null and (length(p_search) < 1 or length(p_search) > 200) then
    raise exception using errcode = '22023', message = 'The Catalog search value is invalid';
  end if;
  if p_cursor is not null then
    begin
      cursor_json := convert_from(decode(p_cursor, 'base64'), 'utf8')::jsonb;
      cursor_value := cursor_json ->> 'value';
      cursor_id := (cursor_json ->> 'id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'The Catalog cursor is invalid';
    end;
  end if;

  if p_resource = 'origins' then
    if actor_role = 'finance' then
      raise exception using errcode = '42501', message = 'The Admin role cannot read origins';
    end if;
    if p_status is not null or p_sort not in ('createdAt', 'updatedAt', 'origin', 'environment') then
      raise exception using errcode = '22023', message = 'The Origin query is invalid';
    end if;
    return (
      with base as (
        select origin.id, origin.app_id, app.slug as app_slug, origin.environment, origin.origin,
               origin.is_active, origin.created_at, origin.updated_at,
               case p_sort when 'updatedAt' then to_char(origin.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                 when 'origin' then origin.origin when 'environment' then origin.environment
                 else to_char(origin.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.app_origins as origin join platform.platform_apps as app on app.id = origin.app_id
         where (p_search is null or app.slug ilike '%' || p_search || '%' or origin.origin ilike '%' || p_search || '%')
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'appId', app_id, 'appSlug', app_slug, 'environment', environment, 'origin', origin, 'isActive', is_active, 'createdAt', created_at, 'updatedAt', updated_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'features' then
    if p_sort not in ('createdAt', 'code', 'name', 'status') then
      raise exception using errcode = '22023', message = 'The Feature query is invalid';
    end if;
    return (
      with base as (
        select feature.id, app.slug as app_slug, feature.code, feature.name, feature.value_type, feature.status, feature.merge_strategy, feature.created_at,
               case p_sort when 'code' then feature.code when 'name' then feature.name when 'status' then feature.status
                 else to_char(feature.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.features as feature left join platform.platform_apps as app on app.id = feature.app_id
         where (p_search is null or feature.code ilike '%' || p_search || '%' or feature.name ilike '%' || p_search || '%')
           and (p_status is null or feature.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'appSlug', app_slug, 'code', code, 'name', name, 'valueType', value_type, 'status', status, 'mergeStrategy', merge_strategy, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'product-versions' then
    if p_sort not in ('createdAt', 'version', 'status') then
      raise exception using errcode = '22023', message = 'The Product Version query is invalid';
    end if;
    return (
      with base as (
        select version.id, version.product_id, product.sku as product_sku, version.version, version.status, version.published_at, version.created_at,
               case p_sort when 'version' then lpad(version.version::text, 10, '0') when 'status' then version.status
                 else to_char(version.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.product_versions as version join platform.products as product on product.id = version.product_id
         where (p_search is null or product.sku ilike '%' || p_search || '%') and (p_status is null or version.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'productId', product_id, 'productSku', product_sku, 'version', version, 'status', status, 'publishedAt', published_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'prices' then
    if p_sort not in ('createdAt', 'updatedAt', 'status') then
      raise exception using errcode = '22023', message = 'The Price query is invalid';
    end if;
    return (
      with base as (
        select price.id, product.id as product_id, product.sku as product_sku, version.version as product_version, price.currency, price.amount_minor, price.channel,
               price.external_price_id, price.status, price.valid_from, price.valid_until, price.created_at, price.updated_at,
               case p_sort when 'updatedAt' then to_char(price.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') when 'status' then price.status
                 else to_char(price.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id
          join platform.products as product on product.id = version.product_id
         where (p_search is null or product.sku ilike '%' || p_search || '%' or price.channel ilike '%' || p_search || '%') and (p_status is null or price.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'productId', product_id, 'productSku', product_sku, 'productVersion', product_version, 'currency', currency, 'amountMinor', amount_minor, 'channel', channel, 'externalPriceId', external_price_id, 'status', status, 'validFrom', valid_from, 'validUntil', valid_until, 'createdAt', created_at, 'updatedAt', updated_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'redemption-batches' then
    if p_sort not in ('createdAt', 'name', 'status') then
      raise exception using errcode = '22023', message = 'The Redemption Batch query is invalid';
    end if;
    return (
      with base as (
        select batch.id, batch.name, product.sku as product_sku, version.version as product_version, batch.status, batch.code_prefix, batch.quantity,
               (select count(*)::integer from platform.redemption_codes as code where code.batch_id = batch.id) as issued_count,
               (select count(*)::integer from platform.redemptions as redemption where redemption.batch_id = batch.id) as redeemed_count,
               batch.starts_at, batch.expires_at, batch.created_at,
               case p_sort when 'name' then batch.name when 'status' then batch.status else to_char(batch.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.redemption_batches as batch join platform.products as product on product.id = batch.product_id
          join platform.product_versions as version on version.id = batch.product_version_id
         where (p_search is null or batch.name ilike '%' || p_search || '%' or product.sku ilike '%' || p_search || '%') and (p_status is null or batch.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'productSku', product_sku, 'productVersion', product_version, 'status', status, 'codePrefix', code_prefix, 'quantity', quantity, 'issuedCount', issued_count, 'redeemedCount', redeemed_count, 'startsAt', starts_at, 'expiresAt', expires_at, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'redemption-codes' then
    if p_sort not in ('createdAt', 'redeemedAt', 'status') then
      raise exception using errcode = '22023', message = 'The Redemption Code query is invalid';
    end if;
    return (
      with base as (
        select code.id, code.batch_id, code.code_hint, code.status, code.redeemed_at, code.created_at,
               case p_sort when 'redeemedAt' then coalesce(to_char(code.redeemed_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') when 'status' then code.status
                 else to_char(code.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.redemption_codes as code join platform.redemption_batches as batch on batch.id = code.batch_id
         where (p_search is null or code.code_hint ilike '%' || p_search || '%' or batch.name ilike '%' || p_search || '%') and (p_status is null or code.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'batchId', batch_id, 'codeHint', code_hint, 'status', status, 'redeemedAt', redeemed_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  raise exception using errcode = '22023', message = 'The Catalog resource is not supported';
end;
$$;

create or replace function public.admin_product_overview(p_actor_id uuid, p_product_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  product_row jsonb;
begin
  select member.role into actor_role from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  select jsonb_build_object('id', product.id, 'sku', product.sku, 'name', product.name, 'billingType', product.billing_type, 'status', product.status,
    'currentVersion', case when current_version.id is null then null else jsonb_build_object('id', current_version.id, 'version', current_version.version, 'status', current_version.status) end)
    into product_row
    from platform.products as product left join platform.product_versions as current_version on current_version.id = product.current_version_id
   where product.id = p_product_id;
  if product_row is null then
    raise exception using errcode = 'P0002', message = 'The Product was not found';
  end if;
  return jsonb_build_object(
    'product', product_row,
    'versions', coalesce((select jsonb_agg(jsonb_build_object('id', version.id, 'productId', version.product_id, 'productSku', product.sku, 'version', version.version, 'status', version.status, 'publishedAt', version.published_at) order by version.version desc)
      from platform.product_versions as version join platform.products as product on product.id = version.product_id where version.product_id = p_product_id), '[]'::jsonb),
    'prices', coalesce((select jsonb_agg(jsonb_build_object('id', price.id, 'productId', product.id, 'productSku', product.sku, 'productVersion', version.version, 'currency', price.currency, 'amountMinor', price.amount_minor, 'channel', price.channel, 'externalPriceId', price.external_price_id, 'status', price.status, 'validFrom', price.valid_from, 'validUntil', price.valid_until, 'createdAt', price.created_at, 'updatedAt', price.updated_at) order by price.created_at desc)
      from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id join platform.products as product on product.id = version.product_id where product.id = p_product_id), '[]'::jsonb),
    'featureSnapshots', coalesce((select jsonb_agg(jsonb_build_object('featureCode', feature.code, 'value', snapshot.value) order by feature.code)
      from platform.product_version_features as snapshot join platform.features as feature on feature.id = snapshot.feature_id join platform.product_versions as version on version.id = snapshot.product_version_id where version.product_id = p_product_id), '[]'::jsonb),
    'redemptionBatches', coalesce((select jsonb_agg(jsonb_build_object('id', batch.id, 'name', batch.name, 'productSku', product.sku, 'productVersion', version.version, 'status', batch.status, 'codePrefix', batch.code_prefix, 'quantity', batch.quantity,
        'issuedCount', (select count(*)::integer from platform.redemption_codes as code where code.batch_id = batch.id), 'redeemedCount', (select count(*)::integer from platform.redemptions as redemption where redemption.batch_id = batch.id),
        'startsAt', batch.starts_at, 'expiresAt', batch.expires_at, 'createdAt', batch.created_at) order by batch.created_at desc)
      from platform.redemption_batches as batch join platform.products as product on product.id = batch.product_id join platform.product_versions as version on version.id = batch.product_version_id where batch.product_id = p_product_id), '[]'::jsonb),
    'auditLogs', coalesce((select jsonb_agg(jsonb_build_object('id', audit.id, 'actorType', audit.actor_type, 'actorId', audit.actor_id, 'action', audit.action, 'targetType', audit.target_type, 'targetId', audit.target_id, 'requestId', audit.request_id, 'reason', audit.reason, 'beforeSummary', audit.before_summary, 'afterSummary', audit.after_summary, 'createdAt', audit.created_at) order by audit.created_at desc)
      from platform.audit_logs as audit where audit.target_id = p_product_id or audit.target_id in (select version.id from platform.product_versions as version where version.product_id = p_product_id)), '[]'::jsonb)
  );
end;
$$;

comment on function public.admin_query_catalog_resource(uuid, text, text, integer, text, text, text, text) is
  'Returns allowlisted Catalog and Redemption projections without plaintext codes or hashes.';
comment on function public.admin_product_overview(uuid, uuid) is
  'Returns one Product 360 projection composed from existing Catalog, Redemption, and Audit facts.';

revoke all on function public.admin_query_catalog_resource(uuid, text, text, integer, text, text, text, text) from public, anon, authenticated;
revoke all on function public.admin_product_overview(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_query_catalog_resource(uuid, text, text, integer, text, text, text, text) to service_role;
grant execute on function public.admin_product_overview(uuid, uuid) to service_role;

create or replace function public.admin_catalog_resource_detail(
  p_actor_id uuid,
  p_resource text,
  p_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  result jsonb;
begin
  select member.role into actor_role from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  if p_resource not in ('applications', 'origins', 'features', 'products', 'product-versions', 'prices', 'redemption-batches', 'redemption-codes', 'redemptions', 'entitlements') then
    raise exception using errcode = '22023', message = 'The Catalog detail resource is not supported';
  end if;
  if p_resource in ('applications', 'origins') and actor_role = 'finance' then
    raise exception using errcode = '42501', message = 'The Admin role cannot read this resource';
  end if;

  if p_resource = 'applications' then
    select jsonb_build_object('id', app.id, 'slug', app.slug, 'name', app.name, 'category', app.category, 'status', app.status,
      'originCount', (select count(*)::integer from platform.app_origins as origin where origin.app_id = app.id and origin.is_active), 'createdAt', app.created_at, 'updatedAt', app.updated_at)
      into result from platform.platform_apps as app where app.id = p_id;
  elsif p_resource = 'origins' then
    select jsonb_build_object('id', origin.id, 'appId', origin.app_id, 'appSlug', app.slug, 'environment', origin.environment, 'origin', origin.origin, 'isActive', origin.is_active, 'createdAt', origin.created_at, 'updatedAt', origin.updated_at)
      into result from platform.app_origins as origin join platform.platform_apps as app on app.id = origin.app_id where origin.id = p_id;
  elsif p_resource = 'features' then
    select jsonb_build_object('id', feature.id, 'appSlug', app.slug, 'code', feature.code, 'name', feature.name, 'valueType', feature.value_type, 'status', feature.status, 'mergeStrategy', feature.merge_strategy, 'createdAt', feature.created_at)
      into result from platform.features as feature left join platform.platform_apps as app on app.id = feature.app_id where feature.id = p_id;
  elsif p_resource = 'products' then
    select jsonb_build_object('id', product.id, 'sku', product.sku, 'name', product.name, 'billingType', product.billing_type, 'status', product.status,
      'currentVersion', case when version.id is null then null else jsonb_build_object('id', version.id, 'version', version.version, 'status', version.status) end)
      into result from platform.products as product left join platform.product_versions as version on version.id = product.current_version_id where product.id = p_id;
  elsif p_resource = 'product-versions' then
    select jsonb_build_object('id', version.id, 'productId', version.product_id, 'productSku', product.sku, 'version', version.version, 'status', version.status, 'publishedAt', version.published_at)
      into result from platform.product_versions as version join platform.products as product on product.id = version.product_id where version.id = p_id;
  elsif p_resource = 'prices' then
    select jsonb_build_object('id', price.id, 'productId', product.id, 'productSku', product.sku, 'productVersion', version.version, 'currency', price.currency, 'amountMinor', price.amount_minor, 'channel', price.channel, 'externalPriceId', price.external_price_id, 'status', price.status, 'validFrom', price.valid_from, 'validUntil', price.valid_until, 'createdAt', price.created_at, 'updatedAt', price.updated_at)
      into result from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id join platform.products as product on product.id = version.product_id where price.id = p_id;
  elsif p_resource = 'redemption-batches' then
    select jsonb_build_object('id', batch.id, 'name', batch.name, 'productSku', product.sku, 'productVersion', version.version, 'status', batch.status, 'codePrefix', batch.code_prefix, 'quantity', batch.quantity,
      'issuedCount', (select count(*)::integer from platform.redemption_codes as code where code.batch_id = batch.id), 'redeemedCount', (select count(*)::integer from platform.redemptions as redemption where redemption.batch_id = batch.id), 'startsAt', batch.starts_at, 'expiresAt', batch.expires_at, 'createdAt', batch.created_at)
      into result from platform.redemption_batches as batch join platform.products as product on product.id = batch.product_id join platform.product_versions as version on version.id = batch.product_version_id where batch.id = p_id;
  elsif p_resource = 'redemption-codes' then
    select jsonb_build_object('id', code.id, 'batchId', code.batch_id, 'codeHint', code.code_hint, 'status', code.status, 'redeemedAt', code.redeemed_at)
      into result from platform.redemption_codes as code where code.id = p_id;
  elsif p_resource = 'redemptions' then
    select jsonb_build_object('id', redemption.id, 'batchId', redemption.batch_id, 'userId', redemption.user_id, 'productSku', product.sku, 'status', 'redeemed', 'redeemedAt', redemption.redeemed_at)
      into result from platform.redemptions as redemption join platform.redemption_batches as batch on batch.id = redemption.batch_id join platform.products as product on product.id = batch.product_id where redemption.id = p_id;
  elsif p_resource = 'entitlements' then
    select jsonb_build_object('id', grant_item.id, 'userId', grant_item.user_id, 'displayName', case when actor_role = 'finance' then null else profile.display_name end, 'productSku', product.sku, 'productVersion', version.version, 'sourceType', grant_item.source_type, 'status', grant_item.status, 'startsAt', grant_item.starts_at, 'expiresAt', grant_item.expires_at, 'createdAt', grant_item.created_at)
      into result from platform.entitlement_grants as grant_item join platform.products as product on product.id = grant_item.product_id join platform.product_versions as version on version.id = grant_item.product_version_id join platform.profiles as profile on profile.id = grant_item.user_id where grant_item.id = p_id;
  end if;

  if result is null then
    raise exception using errcode = 'P0002', message = 'The Catalog resource was not found';
  end if;
  return result;
end;
$$;

comment on function public.admin_catalog_resource_detail(uuid, text, uuid) is
  'Returns one explicit Catalog or Redemption projection without sensitive code material.';
revoke all on function public.admin_catalog_resource_detail(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_catalog_resource_detail(uuid, text, uuid) to service_role;
