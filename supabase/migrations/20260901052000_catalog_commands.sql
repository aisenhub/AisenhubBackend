-- Controlled catalog state transitions.
-- These RPCs are backend-only entry points; direct table writes remain denied.

create or replace function platform.validate_product_current_version()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  selected_version record;
  catalog_command text := current_setting('app.catalog_command', true);
begin
  if tg_op = 'INSERT'
     and new.current_version_id is not null
     and coalesce(catalog_command, '') <> 'set_current' then
    raise exception using
      errcode = '42501',
      message = 'Current product version changes require a controlled command';
  end if;

  if tg_op = 'UPDATE'
     and new.current_version_id is distinct from old.current_version_id
     and coalesce(catalog_command, '') <> 'set_current' then
    raise exception using
      errcode = '42501',
      message = 'Current product version changes require a controlled command';
  end if;

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

create or replace function public.publish_product_version(p_product_version_id uuid)
returns table (
  product_version_id uuid,
  status text,
  published_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  version_row platform.product_versions%rowtype;
  previous_command text := current_setting('app.catalog_command', true);
begin
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

  if version_row.status <> 'draft' then
    raise exception using
      errcode = '23514',
      message = 'Only draft product versions can be published';
  end if;

  if not exists (
    select 1
    from platform.product_version_features as feature_snapshot
    where feature_snapshot.product_version_id = version_row.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'A product version needs at least one feature before publication';
  end if;

  if not exists (
    select 1
    from platform.product_prices as price
    where price.product_version_id = version_row.id
      and price.status in ('draft', 'active')
  ) then
    raise exception using
      errcode = '23514',
      message = 'A product version needs at least one price before publication';
  end if;

  perform set_config('app.catalog_command', 'publish', true);
  update platform.product_versions
  set status = 'published',
      published_at = timezone('utc', now())
  where id = version_row.id;
  perform set_config('app.catalog_command', coalesce(previous_command, ''), true);

  return query
  select version.id, version.status, version.published_at
  from platform.product_versions as version
  where version.id = version_row.id;
end;
$$;

create or replace function public.retire_product_version(p_product_version_id uuid)
returns table (
  product_version_id uuid,
  status text
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  version_row platform.product_versions%rowtype;
  previous_command text := current_setting('app.catalog_command', true);
begin
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
      message = 'Only published product versions can be retired';
  end if;

  if exists (
    select 1
    from platform.products as product
    where product.id = version_row.product_id
      and product.current_version_id = version_row.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'The current product version must be changed before retirement';
  end if;

  perform set_config('app.catalog_command', 'retire', true);
  update platform.product_versions
  set status = 'retired'
  where id = version_row.id;

  update platform.product_prices as price
  set status = 'retired'
  where price.product_version_id = version_row.id
    and price.status = 'active';
  perform set_config('app.catalog_command', coalesce(previous_command, ''), true);

  return query
  select version.id, version.status
  from platform.product_versions as version
  where version.id = version_row.id;
end;
$$;

create or replace function public.set_current_product_version(
  p_product_id uuid,
  p_product_version_id uuid
)
returns table (
  product_id uuid,
  current_version_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  selected_version platform.product_versions%rowtype;
  product_row platform.products%rowtype;
  previous_command text := current_setting('app.catalog_command', true);
begin
  select product.*
    into product_row
    from platform.products as product
   where product.id = p_product_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Product was not found';
  end if;

  if product_row.status = 'archived' then
    raise exception using
      errcode = '23514',
      message = 'Archived products cannot select a current version';
  end if;

  select version.*
    into selected_version
    from platform.product_versions as version
   where version.id = p_product_version_id
     and version.product_id = p_product_id
   for update;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Current product version must belong to the product';
  end if;

  if selected_version.status <> 'published' then
    raise exception using
      errcode = '23514',
      message = 'Current product version must be published';
  end if;

  if not exists (
    select 1
    from platform.product_prices as price
    where price.product_version_id = selected_version.id
      and price.status = 'active'
      and price.valid_from <= timezone('utc', now())
      and (price.valid_until is null or price.valid_until > timezone('utc', now()))
  ) then
    raise exception using
      errcode = '23514',
      message = 'Current product version must have an active price';
  end if;

  perform set_config('app.catalog_command', 'set_current', true);
  update platform.products
  set current_version_id = selected_version.id
  where id = product_row.id;
  perform set_config('app.catalog_command', coalesce(previous_command, ''), true);

  return query
  select product.id, product.current_version_id
  from platform.products as product
  where product.id = product_row.id;
end;
$$;

comment on function public.publish_product_version(uuid) is
  'Publishes a complete draft product version through one controlled transaction.';
comment on function public.retire_product_version(uuid) is
  'Retires a non-current published product version and its active prices atomically.';
comment on function public.set_current_product_version(uuid, uuid) is
  'Sets a product current version only after ownership, publication, and active-price checks.';

revoke all on function public.publish_product_version(uuid) from public, anon, authenticated;
revoke all on function public.retire_product_version(uuid) from public, anon, authenticated;
revoke all on function public.set_current_product_version(uuid, uuid) from public, anon, authenticated;
grant execute on function public.publish_product_version(uuid) to service_role;
grant execute on function public.retire_product_version(uuid) to service_role;
grant execute on function public.set_current_product_version(uuid, uuid) to service_role;
