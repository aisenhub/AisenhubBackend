-- Product-version feature snapshots and independent prices.

create table platform.product_version_features (
  product_version_id uuid not null references platform.product_versions(id) on delete restrict,
  feature_id uuid not null references platform.features(id) on delete restrict,
  value jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint product_version_features_pkey primary key (product_version_id, feature_id)
);

comment on table platform.product_version_features is
  'Feature values promised by a specific product version; published snapshots are immutable.';

create index product_version_features_feature_id_idx
  on platform.product_version_features (feature_id);

create table platform.product_prices (
  id uuid primary key default gen_random_uuid(),
  product_version_id uuid not null references platform.product_versions(id) on delete restrict,
  currency char(3) not null,
  amount_minor bigint not null,
  channel text not null,
  external_price_id text,
  status text not null default 'draft',
  valid_from timestamptz not null default timezone('utc', now()),
  valid_until timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint product_prices_currency_check
    check (currency ~ '^[A-Z]{3}$'),
  constraint product_prices_amount_check
    check (amount_minor >= 0),
  constraint product_prices_channel_check
    check (channel in ('manual', 'redemption') or channel ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'),
  constraint product_prices_external_id_check
    check (external_price_id is null or btrim(external_price_id) <> ''),
  constraint product_prices_status_check
    check (status in ('draft', 'active', 'retired')),
  constraint product_prices_valid_window_check
    check (valid_until is null or valid_until > valid_from)
);

comment on table platform.product_prices is
  'Channel and currency pricing independent from immutable product-version sales terms.';

create unique index product_prices_channel_external_id_key
  on platform.product_prices (channel, external_price_id)
  where external_price_id is not null;

create index product_prices_version_status_idx
  on platform.product_prices (product_version_id, status);

create or replace function platform.validate_product_version_feature_value()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  feature_type text;
begin
  select feature.value_type
    into feature_type
    from platform.features as feature
   where feature.id = new.feature_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Product version feature must reference an existing feature';
  end if;

  if feature_type = 'boolean' and jsonb_typeof(new.value) <> 'boolean' then
    raise exception using
      errcode = '23514',
      message = 'Boolean feature values must be JSON booleans';
  elsif feature_type = 'integer' then
    if jsonb_typeof(new.value) <> 'number' then
      raise exception using
        errcode = '23514',
        message = 'Integer feature values must be whole JSON numbers';
    elsif (new.value #>> '{}')::numeric <> trunc((new.value #>> '{}')::numeric) then
      raise exception using
        errcode = '23514',
        message = 'Integer feature values must be whole JSON numbers';
    end if;
  elsif feature_type = 'string' and jsonb_typeof(new.value) <> 'string' then
    raise exception using
      errcode = '23514',
      message = 'String feature values must be JSON strings';
  end if;

  return new;
end;
$$;

create trigger product_version_features_validate_value
before insert or update on platform.product_version_features
for each row
execute function platform.validate_product_version_feature_value();

create or replace function platform.prevent_product_version_feature_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  version_status text;
begin
  if tg_op = 'DELETE' then
    select version.status
      into version_status
      from platform.product_versions as version
     where version.id = old.product_version_id;
    if version_status in ('published', 'retired') then
      raise exception using
        errcode = '23514',
        message = 'Published product version feature snapshots cannot be deleted';
    end if;
    return old;
  end if;

  if new.product_version_id is distinct from old.product_version_id
     or new.feature_id is distinct from old.feature_id then
    raise exception using
      errcode = '23514',
      message = 'Product version feature identity cannot change';
  end if;

  select version.status
    into version_status
    from platform.product_versions as version
   where version.id = old.product_version_id;
  if version_status in ('published', 'retired') then
    raise exception using
      errcode = '23514',
      message = 'Published product version feature snapshots are immutable';
  end if;

  return new;
end;
$$;

create trigger product_version_features_prevent_mutation
before update or delete on platform.product_version_features
for each row
execute function platform.prevent_product_version_feature_mutation();

create or replace function platform.validate_product_price_status()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  version_status text;
begin
  if new.status = 'active' then
    select version.status
      into version_status
      from platform.product_versions as version
     where version.id = new.product_version_id;

    if not found or version_status <> 'published' then
      raise exception using
        errcode = '23514',
        message = 'Active prices must reference a published product version';
    end if;
  end if;
  return new;
end;
$$;

create trigger product_prices_validate_status
before insert or update on platform.product_prices
for each row
execute function platform.validate_product_price_status();

create trigger product_prices_set_updated_at
before update on platform.product_prices
for each row
execute function platform.set_updated_at();

alter table platform.product_version_features enable row level security;
alter table platform.product_prices enable row level security;

revoke all on table platform.product_version_features, platform.product_prices
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema platform from public, anon, authenticated, service_role;
revoke all on function platform.validate_product_version_feature_value() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_product_version_feature_mutation() from public, anon, authenticated, service_role;
revoke all on function platform.validate_product_price_status() from public, anon, authenticated, service_role;
