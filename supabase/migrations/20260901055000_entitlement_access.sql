-- Server-side deterministic entitlement resolution.

create or replace function public.check_access(
  p_user_id uuid,
  p_app_slug text,
  p_feature_code text
)
returns table (
  allowed boolean,
  feature text,
  value jsonb,
  source_product text,
  expires_at timestamptz,
  decision_id uuid
)
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  app_row record;
  feature_row record;
  contribution_count bigint;
  bool_value boolean;
  sum_value numeric;
  max_value numeric;
  min_value numeric;
  latest_value jsonb;
  source_product_value text;
  expiry_value timestamptz;
  resolved_value jsonb;
begin
  if p_user_id is null or p_app_slug is null or p_feature_code is null then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  select app.id, app.primary_feature_id
    into app_row
    from platform.platform_apps as app
   where app.slug = p_app_slug
     and app.status = 'active';

  if not found then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  select feature.id, feature.app_id, feature.value_type, feature.merge_strategy
    into feature_row
    from platform.features as feature
   where feature.code = p_feature_code
     and (feature.app_id is null or feature.app_id = app_row.id);

  if not found then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  with contributions as (
    select grants.id as grant_id,
           grants.expires_at,
           grants.created_at,
           products.sku,
           snapshots.value
      from platform.entitlement_grants as grants
      join platform.product_version_features as snapshots
        on snapshots.product_version_id = grants.product_version_id
      join platform.features as source_features
        on source_features.id = snapshots.feature_id
      join platform.products as products
        on products.id = grants.product_id
     where grants.user_id = p_user_id
       and grants.status = 'active'
       and grants.starts_at <= timezone('utc', now())
       and (grants.expires_at is null or grants.expires_at > timezone('utc', now()))
       and (
         source_features.id = feature_row.id
         or (
           feature_row.id = app_row.primary_feature_id
           and source_features.code = 'hub.all_apps_access'
           and source_features.app_id is null
           and snapshots.value = 'true'::jsonb
         )
       )
  )
  select count(*),
         bool_or(case when feature_row.merge_strategy = 'any_true' then (contributions.value #>> '{}')::boolean end),
         sum(case when feature_row.merge_strategy = 'sum' then (contributions.value #>> '{}')::numeric end),
         max(case when feature_row.merge_strategy in ('max', 'latest') and feature_row.value_type = 'integer' then (contributions.value #>> '{}')::numeric end),
         min(case when feature_row.merge_strategy = 'min' then (contributions.value #>> '{}')::numeric end),
         (array_agg(contributions.value order by contributions.created_at desc, contributions.grant_id desc))[1],
         string_agg(distinct sku, ',' order by sku),
         min(contributions.expires_at)
    into contribution_count, bool_value, sum_value, max_value, min_value,
         latest_value, source_product_value, expiry_value
    from contributions;

  if contribution_count = 0 then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  case feature_row.merge_strategy
    when 'any_true' then resolved_value := to_jsonb(coalesce(bool_value, false));
    when 'sum' then resolved_value := to_jsonb(sum_value);
    when 'max' then resolved_value := to_jsonb(max_value);
    when 'min' then resolved_value := to_jsonb(min_value);
    when 'latest' then resolved_value := latest_value;
    else
      raise exception using
        errcode = '23514',
        message = 'Unsupported entitlement merge strategy';
  end case;

  return query
  select true, p_feature_code, resolved_value, source_product_value, expiry_value, gen_random_uuid();
end;
$$;

comment on function public.check_access(uuid, text, text) is
  'Resolves all active nonexpired snapshot grants on the server with deterministic feature merging.';

revoke all on function public.check_access(uuid, text, text) from public, anon, authenticated;
grant execute on function public.check_access(uuid, text, text) to service_role;
