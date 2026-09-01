-- Order facts and immutable purchase snapshots.
-- Payment, fulfillment, and refund commands are introduced by later Commerce tasks.

create table platform.orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null,
  user_id uuid references auth.users(id) on delete set null,
  customer_ref uuid not null default gen_random_uuid(),
  status text not null default 'pending',
  currency char(3) not null,
  amount_total bigint not null,
  channel text not null,
  paid_at timestamptz,
  fulfilled_at timestamptz,
  cancelled_at timestamptz,
  refunded_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint orders_order_no_key unique (order_no),
  constraint orders_order_no_nonempty_check check (btrim(order_no) <> ''),
  constraint orders_customer_ref_not_null check (customer_ref is not null),
  constraint orders_status_check check (
    status in ('pending', 'paid', 'fulfilled', 'cancelled', 'partially_refunded', 'refunded', 'chargeback')
  ),
  constraint orders_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint orders_amount_total_check check (amount_total >= 0),
  constraint orders_channel_check check (
    channel in ('manual', 'code_sale')
    or channel ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'
  ),
  constraint orders_paid_at_consistency_check check (
    (status = 'pending' and paid_at is null)
    or (status = 'cancelled' and paid_at is null)
    or (status in ('paid', 'fulfilled', 'partially_refunded', 'refunded', 'chargeback') and paid_at is not null)
  ),
  constraint orders_fulfilled_at_consistency_check check (
    (status in ('fulfilled', 'partially_refunded', 'refunded', 'chargeback') and fulfilled_at is not null)
    or status not in ('fulfilled', 'partially_refunded', 'refunded', 'chargeback')
  ),
  constraint orders_cancelled_at_consistency_check check ((status = 'cancelled') = (cancelled_at is not null)),
  constraint orders_refunded_at_consistency_check check ((status = 'refunded') = (refunded_at is not null)),
  constraint orders_timestamp_order_check check (
    (paid_at is null or paid_at >= created_at)
    and (fulfilled_at is null or fulfilled_at >= coalesce(paid_at, created_at))
    and (cancelled_at is null or cancelled_at >= created_at)
    and (refunded_at is null or refunded_at >= coalesce(fulfilled_at, paid_at, created_at))
  )
);

comment on table platform.orders is
  'Backend-owned order facts; user_id may be anonymized while customer_ref preserves historical linkage.';
comment on column platform.orders.customer_ref is
  'Non-personal historical customer reference retained when the direct user link is cleared.';

create index orders_user_status_idx on platform.orders (user_id, status, created_at desc);
create index orders_customer_ref_idx on platform.orders (customer_ref);
create index orders_status_created_idx on platform.orders (status, created_at desc);

create table platform.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references platform.orders(id) on delete restrict,
  product_id uuid not null references platform.products(id) on delete restrict,
  product_version_id uuid not null,
  product_price_id uuid references platform.product_prices(id) on delete restrict,
  quantity integer not null default 1,
  unit_amount bigint not null,
  total_amount bigint not null,
  product_name text not null,
  sku_snapshot text not null,
  sales_terms jsonb not null default '{}'::jsonb,
  fulfillment_status text not null default 'pending',
  refunded_amount bigint not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint order_items_product_version_fk
    foreign key (product_version_id, product_id)
    references platform.product_versions (id, product_id)
    on delete restrict,
  constraint order_items_quantity_check check (quantity = 1),
  constraint order_items_unit_amount_check check (unit_amount >= 0),
  constraint order_items_total_amount_check check (total_amount >= 0 and total_amount = unit_amount * quantity),
  constraint order_items_product_name_nonempty_check check (btrim(product_name) <> ''),
  constraint order_items_sku_snapshot_format_check check (
    sku_snapshot = upper(sku_snapshot) and sku_snapshot ~ '^[A-Z0-9][A-Z0-9_-]*$'
  ),
  constraint order_items_sales_terms_object_check check (jsonb_typeof(sales_terms) = 'object'),
  constraint order_items_fulfillment_status_check check (fulfillment_status in ('pending', 'granted', 'revoked')),
  constraint order_items_refunded_amount_check check (refunded_amount between 0 and total_amount)
);

comment on table platform.order_items is
  'Smallest fulfillment and refund unit with a frozen purchase snapshot.';
comment on column platform.order_items.sales_terms is
  'Terms captured at purchase time; it is not re-read from a mutable catalog row.';

create index order_items_order_idx on platform.order_items (order_id, created_at);
create index order_items_product_version_idx on platform.order_items (product_id, product_version_id);
create index order_items_fulfillment_status_idx on platform.order_items (fulfillment_status, created_at);

create or replace function platform.validate_order_item_snapshot()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  order_row platform.orders%rowtype;
  product_row platform.products%rowtype;
  version_row platform.product_versions%rowtype;
  price_row platform.product_prices%rowtype;
  now_value timestamptz := timezone('utc', now());
begin
  if tg_op = 'DELETE' then
    select * into order_row from platform.orders where id = old.order_id;
    if order_row.status is distinct from 'pending' then
      raise exception using errcode = '23514', message = 'Paid order items cannot be deleted';
    end if;
    return old;
  end if;

  select * into order_row from platform.orders where id = new.order_id;
  if not found then
    raise exception using errcode = '23503', message = 'Order item must reference an existing order';
  end if;

  if tg_op = 'UPDATE' and order_row.status is distinct from 'pending' then
    if new.order_id is distinct from old.order_id
       or new.product_id is distinct from old.product_id
       or new.product_version_id is distinct from old.product_version_id
       or new.product_price_id is distinct from old.product_price_id
       or new.quantity is distinct from old.quantity
       or new.unit_amount is distinct from old.unit_amount
       or new.total_amount is distinct from old.total_amount
       or new.product_name is distinct from old.product_name
       or new.sku_snapshot is distinct from old.sku_snapshot
       or new.sales_terms is distinct from old.sales_terms then
      raise exception using errcode = '23514', message = 'Paid order item purchase snapshots are immutable';
    end if;
  end if;

  select * into product_row from platform.products where id = new.product_id;
  if not found then
    raise exception using errcode = '23503', message = 'Order item product was not found';
  end if;

  select * into version_row
    from platform.product_versions
   where id = new.product_version_id
     and product_id = new.product_id;
  if not found or version_row.status <> 'published' then
    raise exception using errcode = '23514', message = 'Order item must reference a published product version';
  end if;
  if new.product_name <> product_row.name or new.sku_snapshot <> product_row.sku
     or new.sales_terms is distinct from version_row.sales_terms then
    raise exception using errcode = '23514', message = 'Order item purchase snapshots do not match the catalog';
  end if;

  if new.product_price_id is not null then
    select * into price_row from platform.product_prices where id = new.product_price_id;
    if not found or price_row.product_version_id <> new.product_version_id then
      raise exception using errcode = '23514', message = 'Order item price must belong to its product version';
    end if;
    if price_row.status <> 'active'
       or price_row.valid_from > now_value
       or (price_row.valid_until is not null and price_row.valid_until <= now_value) then
      raise exception using errcode = '23514', message = 'Order item price is not active';
    end if;
    if order_row.currency <> price_row.currency or new.unit_amount <> price_row.amount_minor then
      raise exception using errcode = '23514', message = 'Order item price and currency do not match the order';
    end if;
  end if;

  return new;
end;
$$;

create trigger order_items_validate_snapshot
before insert or update or delete on platform.order_items
for each row
execute function platform.validate_order_item_snapshot();

create or replace function platform.validate_order_total()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  order_row platform.orders%rowtype;
  item_total bigint;
  order_id_value uuid;
begin
  if tg_table_name = 'orders' then
    order_id_value := (to_jsonb(new) ->> 'id')::uuid;
  else
    order_id_value := coalesce(
      (to_jsonb(new) ->> 'order_id')::uuid,
      (to_jsonb(old) ->> 'order_id')::uuid
    );
  end if;
  select * into order_row from platform.orders where id = order_id_value;
  if not found or order_row.status = 'pending' then
    return coalesce(new, old);
  end if;

  select coalesce(sum(item.total_amount), 0)
    into item_total
    from platform.order_items as item
   where item.order_id = order_row.id;
  if item_total <> order_row.amount_total then
    raise exception using errcode = '23514', message = 'Order total must equal the sum of order items';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger orders_validate_total
after insert or update on platform.orders
for each row
execute function platform.validate_order_total();

create trigger order_items_validate_total
after insert or update or delete on platform.order_items
for each row
execute function platform.validate_order_total();

create trigger orders_set_updated_at
before update on platform.orders
for each row
execute function platform.set_updated_at();

create trigger order_items_set_updated_at
before update on platform.order_items
for each row
execute function platform.set_updated_at();

alter table platform.orders enable row level security;
alter table platform.order_items enable row level security;

revoke all on table platform.orders, platform.order_items
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema platform from public, anon, authenticated, service_role;
revoke all on function platform.validate_order_item_snapshot() from public, anon, authenticated, service_role;
revoke all on function platform.validate_order_total() from public, anon, authenticated, service_role;
