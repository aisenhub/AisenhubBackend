-- Core catalog identities and immutable product-version foundations.
-- Prices, feature snapshots, and state-changing command functions arrive in later migrations.

create table platform.features (
  id uuid primary key default gen_random_uuid(),
  app_id uuid references platform.platform_apps(id) on delete restrict,
  code text not null,
  name text not null,
  value_type text not null,
  status text not null default 'active',
  merge_strategy text not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint features_code_key unique (code),
  constraint features_code_format_check
    check (code = lower(code) and code ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'),
  constraint features_name_nonempty_check
    check (btrim(name) <> ''),
  constraint features_value_type_check
    check (value_type in ('boolean', 'integer', 'string', 'json')),
  constraint features_status_check
    check (status in ('active', 'retired')),
  constraint features_merge_strategy_check
    check (merge_strategy in ('any_true', 'sum', 'max', 'min', 'latest')),
  constraint features_merge_strategy_type_check
    check (
      (value_type = 'boolean' and merge_strategy = 'any_true')
      or (value_type = 'integer' and merge_strategy in ('sum', 'max', 'min', 'latest'))
      or (value_type in ('string', 'json') and merge_strategy = 'latest')
    )
);

comment on table platform.features is
  'Backend-owned atomic entitlement features; feature definitions are not user roles.';

create table platform.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null,
  name text not null,
  billing_type text not null,
  status text not null default 'draft',
  current_version_id uuid,
  entitlement_policy text not null default 'snapshot',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint products_sku_key unique (sku),
  constraint products_sku_format_check
    check (sku = upper(sku) and sku ~ '^[A-Z0-9][A-Z0-9_-]*$'),
  constraint products_name_nonempty_check
    check (btrim(name) <> ''),
  constraint products_billing_type_check
    check (billing_type in ('one_time', 'subscription', 'credits')),
  constraint products_status_check
    check (status in ('draft', 'active', 'archived')),
  constraint products_entitlement_policy_check
    check (entitlement_policy in ('snapshot', 'all_apps_access'))
);

comment on table platform.products is
  'Stable sales identities; prices and entitlement snapshots are versioned separately.';

create table platform.product_versions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references platform.products(id) on delete restrict,
  version integer not null,
  status text not null default 'draft',
  access_duration_days integer,
  sales_terms jsonb not null default '{}'::jsonb,
  published_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  constraint product_versions_product_version_key unique (product_id, version),
  constraint product_versions_id_product_key unique (id, product_id),
  constraint product_versions_version_positive_check
    check (version > 0),
  constraint product_versions_status_check
    check (status in ('draft', 'published', 'retired')),
  constraint product_versions_access_duration_check
    check (access_duration_days is null or access_duration_days > 0),
  constraint product_versions_sales_terms_object_check
    check (jsonb_typeof(sales_terms) = 'object'),
  constraint product_versions_published_at_check
    check ((status = 'draft' and published_at is null) or (status in ('published', 'retired') and published_at is not null))
);

comment on table platform.product_versions is
  'Frozen sales commitments; published and retired versions cannot be edited or deleted.';

alter table platform.products
  add constraint products_current_version_ownership_fk
  foreign key (current_version_id, id)
  references platform.product_versions (id, product_id)
  on delete restrict;

create or replace function platform.validate_product_current_version()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  selected_version record;
begin
  if new.current_version_id is not null then
    select version.id, version.product_id, version.status
      into selected_version
      from platform.product_versions as version
     where version.id = new.current_version_id;

    if not found or selected_version.product_id <> new.id then
      raise exception using
        errcode = '23514',
        message = 'Current product version must belong to the product';
    end if;

    if selected_version.status <> 'published' then
      raise exception using
        errcode = '23514',
        message = 'Current product version must be published';
    end if;
  end if;

  if new.status = 'active' and new.current_version_id is null then
    raise exception using
      errcode = '23514',
      message = 'Active products must have a current published version';
  end if;

  return new;
end;
$$;

create trigger products_validate_current_version
before insert or update on platform.products
for each row
execute function platform.validate_product_current_version();

create or replace function platform.prevent_product_version_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  catalog_command text := current_setting('app.catalog_command', true);
begin
  if tg_op = 'DELETE' then
    if old.status in ('published', 'retired') then
      raise exception using
        errcode = '23514',
        message = 'Published product versions cannot be deleted';
    end if;
    return old;
  end if;

  if old.status = 'retired' then
    raise exception using
      errcode = '23514',
      message = 'Retired product versions cannot be changed';
  end if;

  if old.status = 'published' then
    if catalog_command = 'retire'
       and new.status = 'retired'
       and new.product_id = old.product_id
       and new.version = old.version
       and new.access_duration_days is not distinct from old.access_duration_days
       and new.sales_terms is not distinct from old.sales_terms
       and new.published_at is not distinct from old.published_at
       and new.created_at is not distinct from old.created_at then
      return new;
    end if;

    raise exception using
      errcode = '23514',
      message = 'Published product versions are immutable; create a new version';
  end if;

  if new.status in ('published', 'retired') and old.status = 'draft' and catalog_command <> 'publish' then
    raise exception using
      errcode = '23514',
      message = 'Product version publication requires a controlled command';
  end if;

  return new;
end;
$$;

create trigger product_versions_prevent_mutation
before update or delete on platform.product_versions
for each row
execute function platform.prevent_product_version_mutation();

create or replace function platform.prevent_current_retired_version()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.status <> 'published'
     and exists (
       select 1
       from platform.products
       where id = new.product_id
         and current_version_id = new.id
     ) then
    raise exception using
      errcode = '23514',
      message = 'The current product version must remain published';
  end if;
  return new;
end;
$$;

create trigger product_versions_protect_current
before update on platform.product_versions
for each row
execute function platform.prevent_current_retired_version();

create trigger products_set_updated_at
before update on platform.products
for each row
execute function platform.set_updated_at();

alter table platform.features enable row level security;
alter table platform.products enable row level security;
alter table platform.product_versions enable row level security;

revoke all on table platform.features, platform.products, platform.product_versions
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema platform from public, anon, authenticated, service_role;
revoke all on function platform.validate_product_current_version() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_product_version_mutation() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_current_retired_version() from public, anon, authenticated, service_role;
