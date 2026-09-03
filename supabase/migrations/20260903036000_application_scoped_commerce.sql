-- Attach application context to Commerce/Redemption facts while delegating
-- state transitions to the existing atomic domain functions.

alter table platform.orders
  add column application_id uuid references platform.platform_apps(id) on delete restrict;
alter table platform.entitlement_grants
  add column application_id uuid references platform.platform_apps(id) on delete restrict;
alter table platform.redemptions
  add column application_id uuid references platform.platform_apps(id) on delete restrict;

create index orders_application_status_idx
  on platform.orders (application_id, status, created_at desc);
create index entitlement_grants_application_status_idx
  on platform.entitlement_grants (application_id, status, created_at desc);
create index redemptions_application_redeemed_at_idx
  on platform.redemptions (application_id, redeemed_at desc);

create or replace function platform.assign_application_context_to_entitlement()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  context_value text := nullif(current_setting('app.application_id', true), '');
begin
  if new.application_id is null and context_value is not null then
    new.application_id := context_value::uuid;
  end if;
  return new;
end;
$$;

create trigger entitlement_grants_assign_application_context
before insert on platform.entitlement_grants
for each row execute function platform.assign_application_context_to_entitlement();

create or replace function platform.application_owns_product_version(
  p_application_id uuid,
  p_product_version_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, platform
as $$
  select p_application_id is not null
     and p_product_version_id is not null
     and exists (
       select 1
         from platform.product_version_features as snapshot
         join platform.features as feature on feature.id = snapshot.feature_id
        where snapshot.product_version_id = p_product_version_id
          and (feature.app_id is null or feature.app_id = p_application_id)
     );
$$;

create or replace function platform.validate_application_scoped_entitlement()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.application_id is not null
     and not platform.application_owns_product_version(new.application_id, new.product_version_id) then
    raise exception using
      errcode = '23514',
      message = 'Entitlement application does not own the product version feature';
  end if;
  return new;
end;
$$;

create trigger entitlement_grants_validate_application_scope
before insert or update on platform.entitlement_grants
for each row execute function platform.validate_application_scoped_entitlement();

create or replace function platform.prevent_entitlement_application_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if old.application_id is not null and new.application_id is distinct from old.application_id then
    raise exception using
      errcode = '23514',
      message = 'Entitlement application context is immutable';
  end if;
  return new;
end;
$$;

create trigger entitlement_grants_application_immutable
before update on platform.entitlement_grants
for each row execute function platform.prevent_entitlement_application_change();

create or replace function platform.validate_application_scoped_order_item()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  order_application_id uuid;
begin
  select order_fact.application_id into order_application_id
    from platform.orders as order_fact
   where order_fact.id = new.order_id;
  if order_application_id is not null
     and not platform.application_owns_product_version(order_application_id, new.product_version_id) then
    raise exception using
      errcode = '23514',
      message = 'Order application does not own the product version feature';
  end if;
  return new;
end;
$$;

create trigger order_items_validate_application_scope
before insert or update on platform.order_items
for each row execute function platform.validate_application_scoped_order_item();

create or replace function platform.prevent_redemption_application_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if old.application_id is not null and new.application_id is distinct from old.application_id then
    raise exception using
      errcode = '23514',
      message = 'Redemption application context is immutable';
  end if;
  return new;
end;
$$;

create or replace function platform.assign_application_context_to_redemption()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  context_value text := nullif(current_setting('app.application_id', true), '');
begin
  if new.application_id is null and context_value is not null then
    new.application_id := context_value::uuid;
  end if;
  return new;
end;
$$;

create trigger redemptions_assign_application_context
before insert on platform.redemptions
for each row execute function platform.assign_application_context_to_redemption();

create trigger redemptions_application_immutable
before update on platform.redemptions
for each row execute function platform.prevent_redemption_application_change();

create or replace function public.redeem_application_code(
  p_code_hash text,
  p_user_id uuid,
  p_application_id uuid,
  p_idempotency_key text,
  p_request_hash text,
  p_ip_hash text default null
)
returns table (
  redemption_id uuid,
  code_id uuid,
  batch_id uuid,
  grant_id uuid,
  status text,
  idempotency_record_id uuid,
  redeemed_at timestamptz
)
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  code_row platform.redemption_codes%rowtype;
  batch_row platform.redemption_batches%rowtype;
  redemption_result record;
begin
  if p_user_id is null or p_application_id is null
     or not exists (
       select 1 from platform.application_memberships as membership
        where membership.application_id = p_application_id
          and membership.user_id = p_user_id
          and membership.status = 'active'
     ) then
    raise exception using errcode = '42501', message = 'An active Application membership is required';
  end if;
  select code.* into code_row
    from platform.redemption_codes as code
   where code.code_hash = p_code_hash;
  if not found then
    raise exception using errcode = 'P0001', message = 'The redemption code is unavailable';
  end if;
  select batch.* into batch_row
    from platform.redemption_batches as batch
   where batch.id = code_row.batch_id;
  if not found or not platform.application_owns_product_version(p_application_id, batch_row.product_version_id) then
    raise exception using errcode = 'P0001', message = 'The redemption code is unavailable';
  end if;

  perform set_config('app.application_id', p_application_id::text, true);
  select * into redemption_result
    from public.redeem_code(p_code_hash, p_user_id, p_idempotency_key, p_request_hash, p_ip_hash);
  return query select redemption_result.redemption_id, redemption_result.code_id,
                      redemption_result.batch_id, redemption_result.grant_id,
                      redemption_result.status, redemption_result.idempotency_record_id,
                      redemption_result.redeemed_at;
end;
$$;

comment on function public.redeem_application_code(text, uuid, uuid, text, text, text) is
  'Validates server-resolved Application ownership, then delegates to the atomic redemption state machine.';

revoke all on function public.redeem_application_code(text, uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.redeem_application_code(text, uuid, uuid, text, text, text)
  to service_role;

revoke all on function platform.application_owns_product_version(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function platform.assign_application_context_to_entitlement() from public, anon, authenticated, service_role;
revoke all on function platform.validate_application_scoped_entitlement() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_entitlement_application_change() from public, anon, authenticated, service_role;
revoke all on function platform.validate_application_scoped_order_item() from public, anon, authenticated, service_role;
revoke all on function platform.assign_application_context_to_redemption() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_redemption_application_change() from public, anon, authenticated, service_role;
