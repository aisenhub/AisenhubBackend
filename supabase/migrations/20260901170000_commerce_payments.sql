-- Payment identities and minimized webhook event facts.
-- Fulfillment and refund commands are introduced by later Commerce tasks.

create table platform.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references platform.orders(id) on delete restrict,
  provider text not null,
  external_payment_id text,
  status text not null default 'pending',
  currency char(3) not null,
  amount bigint not null,
  failure_code text,
  paid_at timestamptz,
  refunded_at timestamptz,
  disputed_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint payments_provider_check check (provider ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'),
  constraint payments_external_id_check check (
    external_payment_id is null
    or (btrim(external_payment_id) <> '' and external_payment_id !~ '[[:space:]]')
  ),
  constraint payments_status_check check (
    status in ('pending', 'succeeded', 'partially_refunded', 'refunded', 'disputed', 'failed')
  ),
  constraint payments_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint payments_amount_check check (amount >= 0),
  constraint payments_failure_code_check check (
    failure_code is null or failure_code ~ '^[A-Z0-9][A-Z0-9_.-]*$'
  ),
  constraint payments_status_timestamps_check check (
    (status = 'pending' and paid_at is null and refunded_at is null and disputed_at is null and failed_at is null)
    or (status = 'succeeded' and paid_at is not null and refunded_at is null and disputed_at is null and failed_at is null)
    or (status = 'partially_refunded' and paid_at is not null and refunded_at is not null and disputed_at is null and failed_at is null)
    or (status = 'refunded' and paid_at is not null and refunded_at is not null and disputed_at is null and failed_at is null)
    or (status = 'disputed' and paid_at is not null and disputed_at is not null and refunded_at is null and failed_at is null)
    or (status = 'failed' and paid_at is null and refunded_at is null and disputed_at is null and failed_at is not null)
  ),
  constraint payments_timestamp_order_check check (
    (paid_at is null or paid_at >= created_at)
    and (refunded_at is null or refunded_at >= coalesce(paid_at, created_at))
    and (disputed_at is null or disputed_at >= coalesce(paid_at, created_at))
    and (failed_at is null or failed_at >= created_at)
  )
);

comment on table platform.payments is
  'Backend-owned payment identity and status; no complete payment credentials are stored.';
comment on column platform.payments.external_payment_id is
  'Provider transaction identity only; secrets and complete payment credentials are prohibited.';

create unique index payments_provider_external_id_key
  on platform.payments (provider, external_payment_id)
  where external_payment_id is not null;
create index payments_order_status_idx on platform.payments (order_id, status, created_at desc);
create index payments_status_created_idx on platform.payments (status, created_at desc);

create table platform.payment_events (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references platform.payments(id) on delete restrict,
  order_id uuid not null references platform.orders(id) on delete restrict,
  provider text not null,
  external_event_id text not null,
  event_type text not null,
  status text not null default 'received',
  currency char(3) not null,
  amount bigint not null,
  payload_summary jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null,
  processed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint payment_events_provider_check check (provider ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'),
  constraint payment_events_external_id_check check (
    btrim(external_event_id) <> '' and external_event_id !~ '[[:space:]]'
  ),
  constraint payment_events_type_check check (event_type ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'),
  constraint payment_events_status_check check (status in ('received', 'processed', 'ignored', 'failed')),
  constraint payment_events_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint payment_events_amount_check check (amount >= 0),
  constraint payment_events_summary_object_check check (jsonb_typeof(payload_summary) = 'object'),
  constraint payment_events_summary_size_check check (octet_length(payload_summary::text) <= 32768),
  constraint payment_events_processed_at_check check (
    (status = 'received' and processed_at is null)
    or (status in ('processed', 'ignored', 'failed') and processed_at is not null)
  ),
  constraint payment_events_timestamp_order_check check (
    occurred_at <= created_at
    and (processed_at is null or processed_at >= created_at)
  )
);

comment on table platform.payment_events is
  'Backend-owned minimized payment event facts used for webhook idempotency; raw credentials are not stored.';
comment on column platform.payment_events.payload_summary is
  'Small validated summary only; never store raw webhook bodies, tokens, card data, or credentials.';

create unique index payment_events_provider_external_id_key
  on platform.payment_events (provider, external_event_id);
create index payment_events_payment_created_idx on platform.payment_events (payment_id, created_at desc);
create index payment_events_order_created_idx on platform.payment_events (order_id, created_at desc);

create or replace function platform.payment_event_summary_is_safe(value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, platform
as $$
declare
  key_name text;
  child jsonb;
begin
  if jsonb_typeof(value) = 'object' then
    for key_name, child in
      select entry.key_name, entry.child
        from jsonb_each(value) as entry(key_name, child)
    loop
      if lower(key_name) in (
        'authorization', 'card_number', 'card_expiry', 'cvv', 'cvc', 'pan',
        'password', 'secret', 'token', 'access_token', 'refresh_token',
        'payment_method', 'payment_method_token', 'credential', 'credentials'
      ) then
        return false;
      end if;
      if not platform.payment_event_summary_is_safe(child) then
        return false;
      end if;
    end loop;
  elsif jsonb_typeof(value) = 'array' then
    for child in
      select entry.child
        from jsonb_array_elements(value) as entry(child)
    loop
      if not platform.payment_event_summary_is_safe(child) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$$;

create or replace function platform.validate_payment_consistency()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  order_row platform.orders%rowtype;
begin
  select * into order_row from platform.orders where id = new.order_id;
  if not found then
    raise exception using errcode = '23503', message = 'Payment must reference an existing order';
  end if;

  if new.currency <> order_row.currency or new.amount <> order_row.amount_total then
    raise exception using errcode = '23514', message = 'Payment amount and currency must match the order';
  end if;

  if tg_op = 'UPDATE'
     and (new.id is distinct from old.id
       or new.order_id is distinct from old.order_id
       or new.provider is distinct from old.provider
       or new.external_payment_id is distinct from old.external_payment_id
       or new.currency is distinct from old.currency
       or new.amount is distinct from old.amount
       or new.created_at is distinct from old.created_at) then
    raise exception using errcode = '23514', message = 'Payment identity is immutable';
  end if;
  return new;
end;
$$;

create trigger payments_validate_consistency
before insert or update on platform.payments
for each row
execute function platform.validate_payment_consistency();

create or replace function platform.validate_payment_event_consistency()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  payment_row platform.payments%rowtype;
begin
  select * into payment_row from platform.payments where id = new.payment_id;
  if not found then
    raise exception using errcode = '23503', message = 'Payment event must reference an existing payment';
  end if;

  if payment_row.order_id <> new.order_id
     or payment_row.provider <> new.provider
     or payment_row.currency <> new.currency
     or payment_row.amount <> new.amount then
    raise exception using errcode = '23514', message = 'Payment event must match its payment and order';
  end if;

  if not platform.payment_event_summary_is_safe(new.payload_summary) then
    raise exception using errcode = '23514', message = 'Payment event summary contains prohibited credentials';
  end if;

  if tg_op = 'UPDATE'
     and (new.id is distinct from old.id
       or new.payment_id is distinct from old.payment_id
       or new.order_id is distinct from old.order_id
       or new.provider is distinct from old.provider
       or new.external_event_id is distinct from old.external_event_id
       or new.event_type is distinct from old.event_type
       or new.currency is distinct from old.currency
       or new.amount is distinct from old.amount
       or new.occurred_at is distinct from old.occurred_at
       or new.created_at is distinct from old.created_at) then
    raise exception using errcode = '23514', message = 'Payment event identity is immutable';
  end if;
  return new;
end;
$$;

create trigger payment_events_validate_consistency
before insert or update on platform.payment_events
for each row
execute function platform.validate_payment_event_consistency();

create trigger payments_set_updated_at
before update on platform.payments
for each row
execute function platform.set_updated_at();

create trigger payment_events_set_updated_at
before update on platform.payment_events
for each row
execute function platform.set_updated_at();

alter table platform.payments enable row level security;
alter table platform.payment_events enable row level security;

revoke all on table platform.payments, platform.payment_events
  from public, anon, authenticated, service_role;
revoke all on function platform.payment_event_summary_is_safe(jsonb) from public, anon, authenticated, service_role;
revoke all on function platform.validate_payment_consistency() from public, anon, authenticated, service_role;
revoke all on function platform.validate_payment_event_consistency() from public, anon, authenticated, service_role;
