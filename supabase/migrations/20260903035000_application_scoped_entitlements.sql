-- Application-scoped entitlement projections. The old user-wide projection is
-- retained only for historical tests; runtime APIs use these context-bound RPCs.

create or replace function public.list_user_application_entitlements(
  p_user_id uuid,
  p_application_id uuid
)
returns table (
  feature text,
  value jsonb,
  source_product text,
  expires_at timestamptz
)
language sql
security definer
stable
set search_path = pg_catalog, platform
as $$
  select feature.code, snapshot.value, product.sku, grant_item.expires_at
    from platform.entitlement_grants as grant_item
    join platform.product_version_features as snapshot
      on snapshot.product_version_id = grant_item.product_version_id
    join platform.features as feature
      on feature.id = snapshot.feature_id
     and (feature.app_id is null or feature.app_id = p_application_id)
    join platform.products as product
      on product.id = grant_item.product_id
   where p_user_id is not null
     and p_application_id is not null
     and exists (
       select 1
         from platform.application_memberships as membership
        where membership.application_id = p_application_id
          and membership.user_id = p_user_id
          and membership.status = 'active'
     )
     and grant_item.user_id = p_user_id
     and grant_item.status = 'active'
     and grant_item.starts_at <= timezone('utc', now())
     and (grant_item.expires_at is null or grant_item.expires_at > timezone('utc', now()))
   order by feature.code, grant_item.created_at desc, grant_item.id desc;
$$;

create or replace function public.check_application_access(
  p_user_id uuid,
  p_application_id uuid,
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
stable
set search_path = pg_catalog, platform
as $$
declare
  app_slug text;
begin
  if p_user_id is null or p_application_id is null or p_feature_code is null then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;
  if not exists (
    select 1
      from platform.application_memberships as membership
     where membership.application_id = p_application_id
       and membership.user_id = p_user_id
       and membership.status = 'active'
  ) then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;
  select app.slug into app_slug
    from platform.platform_apps as app
   where app.id = p_application_id
     and app.status = 'active';
  if app_slug is null then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;
  return query select access.allowed, access.feature, access.value, access.source_product,
                      access.expires_at, access.decision_id
                 from public.check_access(p_user_id, app_slug, p_feature_code) as access;
end;
$$;

comment on function public.list_user_application_entitlements(uuid, uuid) is
  'Returns only active entitlement features applicable to the verified Application and member.';
comment on function public.check_application_access(uuid, uuid, text) is
  'Resolves access only after verifying an active Application Membership.';

revoke all on function public.list_user_application_entitlements(uuid, uuid) from public, anon, authenticated;
grant execute on function public.list_user_application_entitlements(uuid, uuid) to service_role;
revoke all on function public.check_application_access(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.check_application_access(uuid, uuid, text) to service_role;
