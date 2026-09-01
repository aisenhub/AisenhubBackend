-- Immutable entitlement history. Grant/revoke/restore commands arrive in the next task.

create table platform.entitlement_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  product_id uuid not null references platform.products(id) on delete restrict,
  product_version_id uuid not null,
  resolution_mode text not null default 'snapshot',
  source_type text not null,
  source_id uuid not null,
  status text not null default 'active',
  starts_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoke_reason text,
  restores_grant_id uuid references platform.entitlement_grants(id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  constraint entitlement_grants_product_version_fk
    foreign key (product_version_id, product_id)
    references platform.product_versions(id, product_id)
    on delete restrict,
  constraint entitlement_grants_source_key unique (source_type, source_id),
  constraint entitlement_grants_resolution_mode_check
    check (resolution_mode = 'snapshot'),
  constraint entitlement_grants_source_type_check
    check (source_type in ('order_item', 'redemption', 'admin', 'promotion', 'admin_restore')),
  constraint entitlement_grants_status_check
    check (status in ('active', 'revoked')),
  constraint entitlement_grants_expiry_check
    check (expires_at is null or expires_at > starts_at),
  constraint entitlement_grants_revocation_fields_check
    check (
      (status = 'active' and revoked_at is null and revoke_reason is null)
      or (status = 'revoked' and revoked_at is not null and revoke_reason is not null and btrim(revoke_reason) <> '')
    ),
  constraint entitlement_grants_restore_shape_check
    check ((source_type = 'admin_restore') = (restores_grant_id is not null)),
  constraint entitlement_grants_restore_not_self_check
    check (restores_grant_id is null or restores_grant_id <> id)
);

comment on table platform.entitlement_grants is
  'Append-only business entitlement history; access is resolved from all valid grants, not a user role.';

comment on column platform.entitlement_grants.product_version_id is
  'The product version promised at grant time; it never follows the product current version.';

create index entitlement_grants_user_status_expiry_idx
  on platform.entitlement_grants (user_id, status, expires_at);

create index entitlement_grants_product_status_idx
  on platform.entitlement_grants (product_id, status);

create index entitlement_grants_restores_grant_id_idx
  on platform.entitlement_grants (restores_grant_id)
  where restores_grant_id is not null;

create or replace function platform.validate_entitlement_restore_link()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  original_grant record;
begin
  if new.restores_grant_id is null then
    return new;
  end if;

  select grant_row.id,
         grant_row.user_id,
         grant_row.product_id,
         grant_row.product_version_id,
         grant_row.status,
         grant_row.restores_grant_id
    into original_grant
    from platform.entitlement_grants as grant_row
   where grant_row.id = new.restores_grant_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Restored entitlement must reference an existing grant';
  end if;

  if original_grant.status <> 'revoked'
     or original_grant.restores_grant_id is not null
     or original_grant.user_id <> new.user_id
     or original_grant.product_id <> new.product_id
     or original_grant.product_version_id <> new.product_version_id then
    raise exception using
      errcode = '23514',
      message = 'Admin restore must point to a matching original revoked grant';
  end if;

  return new;
end;
$$;

create trigger entitlement_grants_validate_restore
before insert or update on platform.entitlement_grants
for each row
execute function platform.validate_entitlement_restore_link();

create or replace function platform.prevent_entitlement_grant_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'Entitlement grant history cannot be deleted';
  end if;

  if new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.product_id is distinct from old.product_id
     or new.product_version_id is distinct from old.product_version_id
     or new.resolution_mode is distinct from old.resolution_mode
     or new.source_type is distinct from old.source_type
     or new.source_id is distinct from old.source_id
     or new.starts_at is distinct from old.starts_at
     or new.expires_at is distinct from old.expires_at
     or new.restores_grant_id is distinct from old.restores_grant_id
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'Entitlement grant identity and terms are immutable';
  end if;

  if old.status = 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Revoked entitlement grants cannot be changed';
  end if;

  if new.status <> 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Entitlement grants only transition from active to revoked';
  end if;

  return new;
end;
$$;

create trigger entitlement_grants_prevent_mutation
before update or delete on platform.entitlement_grants
for each row
execute function platform.prevent_entitlement_grant_mutation();

alter table platform.entitlement_grants enable row level security;

revoke all on table platform.entitlement_grants
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema platform from public, anon, authenticated, service_role;
revoke all on function platform.validate_entitlement_restore_link() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_entitlement_grant_mutation() from public, anon, authenticated, service_role;
