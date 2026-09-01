-- Redemption batches, hashed codes, and one-code-one-redemption records.

create table platform.redemption_batches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  product_id uuid not null,
  product_version_id uuid not null,
  resolution_mode text not null default 'snapshot',
  code_prefix text not null,
  quantity integer not null,
  per_user_limit integer not null default 1,
  status text not null default 'draft',
  starts_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz,
  source text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  constraint redemption_batches_product_version_fk
    foreign key (product_version_id, product_id)
    references platform.product_versions(id, product_id)
    on delete restrict,
  constraint redemption_batches_name_nonempty_check
    check (btrim(name) <> ''),
  constraint redemption_batches_resolution_mode_check
    check (resolution_mode = 'snapshot'),
  constraint redemption_batches_code_prefix_check
    check (code_prefix = upper(code_prefix) and code_prefix ~ '^[A-Z0-9]+(?:-[A-Z0-9]+)*$'),
  constraint redemption_batches_quantity_check
    check (quantity > 0),
  constraint redemption_batches_per_user_limit_check
    check (per_user_limit > 0 and per_user_limit <= quantity),
  constraint redemption_batches_status_check
    check (status in ('draft', 'active', 'paused', 'closed')),
  constraint redemption_batches_expiry_check
    check (expires_at is null or expires_at > starts_at),
  constraint redemption_batches_source_nonempty_check
    check (btrim(source) <> '')
);

comment on table platform.redemption_batches is
  'Backend-owned redemption campaigns tied to one immutable product-version snapshot.';

create index redemption_batches_status_window_idx
  on platform.redemption_batches (status, starts_at, expires_at);

create table platform.redemption_codes (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references platform.redemption_batches(id) on delete restrict,
  code_hash text not null unique,
  code_hint text not null,
  pepper_version smallint not null,
  status text not null default 'issued',
  redeemed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  constraint redemption_codes_hash_format_check
    check (code_hash ~ '^[0-9a-f]{64}$'),
  constraint redemption_codes_hint_nonempty_check
    check (btrim(code_hint) <> ''),
  constraint redemption_codes_pepper_version_check
    check (pepper_version > 0),
  constraint redemption_codes_status_check
    check (status in ('issued', 'redeemed', 'revoked')),
  constraint redemption_codes_redeemed_at_check
    check (
      (status = 'issued' and redeemed_at is null)
      or (status = 'redeemed' and redeemed_at is not null)
      or (status = 'revoked' and redeemed_at is null)
    )
);

comment on table platform.redemption_codes is
  'One-time redemption credentials; only HMAC digests and non-sensitive hints are stored.';

create index redemption_codes_batch_status_idx
  on platform.redemption_codes (batch_id, status);

create or replace function platform.prevent_redemption_code_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'Redemption code history cannot be deleted';
  end if;

  if new.id is distinct from old.id
     or new.batch_id is distinct from old.batch_id
     or new.code_hash is distinct from old.code_hash
     or new.code_hint is distinct from old.code_hint
     or new.pepper_version is distinct from old.pepper_version
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'Redemption code identity is immutable';
  end if;

  if old.status <> 'issued' then
    raise exception using
      errcode = '23514',
      message = 'Redeemed or revoked codes cannot be changed';
  end if;

  if new.status not in ('redeemed', 'revoked') then
    raise exception using
      errcode = '23514',
      message = 'Redemption codes only transition from issued';
  end if;

  return new;
end;
$$;

create trigger redemption_codes_prevent_mutation
before update or delete on platform.redemption_codes
for each row
execute function platform.prevent_redemption_code_mutation();

create table platform.redemptions (
  id uuid primary key default gen_random_uuid(),
  code_id uuid not null unique references platform.redemption_codes(id) on delete restrict,
  batch_id uuid not null references platform.redemption_batches(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  grant_id uuid not null unique references platform.entitlement_grants(id) on delete restrict,
  idempotency_record_id uuid not null unique references platform.idempotency_records(id) on delete restrict,
  ip_hash text,
  redeemed_at timestamptz not null default timezone('utc', now()),
  constraint redemptions_ip_hash_nonempty_check
    check (ip_hash is null or btrim(ip_hash) <> '')
);

comment on table platform.redemptions is
  'Immutable redemption receipts linking one code, user, entitlement grant, and idempotency record.';

create index redemptions_batch_redeemed_at_idx
  on platform.redemptions (batch_id, redeemed_at desc);

create index redemptions_user_redeemed_at_idx
  on platform.redemptions (user_id, redeemed_at desc);

create or replace function platform.validate_redemption_consistency()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  code_row record;
  batch_row record;
  grant_row record;
begin
  select code.batch_id, code.status
    into code_row
    from platform.redemption_codes as code
   where code.id = new.code_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Redemption must reference an existing code';
  end if;

  if code_row.status = 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Revoked redemption codes cannot be redeemed';
  end if;

  if code_row.batch_id <> new.batch_id then
    raise exception using
      errcode = '23514',
      message = 'Redemption code and batch must match';
  end if;

  select batch.product_id, batch.product_version_id
    into batch_row
    from platform.redemption_batches as batch
   where batch.id = new.batch_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Redemption must reference an existing batch';
  end if;

  select grant_item.user_id,
         grant_item.product_id,
         grant_item.product_version_id,
         grant_item.source_type,
         grant_item.source_id
    into grant_row
    from platform.entitlement_grants as grant_item
   where grant_item.id = new.grant_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Redemption must reference an existing entitlement grant';
  end if;

  if grant_row.user_id <> new.user_id
     or grant_row.product_id <> batch_row.product_id
     or grant_row.product_version_id <> batch_row.product_version_id
     or grant_row.source_type <> 'redemption'
     or grant_row.source_id <> new.id then
    raise exception using
      errcode = '23514',
      message = 'Redemption code, user, batch, and grant must describe one redemption';
  end if;

  return new;
end;
$$;

create trigger redemptions_validate_consistency
before insert or update on platform.redemptions
for each row
execute function platform.validate_redemption_consistency();

create or replace function platform.prevent_redemption_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'Redemption receipts are immutable';
end;
$$;

create trigger redemptions_prevent_mutation
before update or delete on platform.redemptions
for each row
execute function platform.prevent_redemption_mutation();

alter table platform.redemption_batches enable row level security;
alter table platform.redemption_codes enable row level security;
alter table platform.redemptions enable row level security;

revoke all on table platform.redemption_batches, platform.redemption_codes, platform.redemptions
  from public, anon, authenticated, service_role;
revoke all on function platform.prevent_redemption_code_mutation() from public, anon, authenticated, service_role;
revoke all on function platform.validate_redemption_consistency() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_redemption_mutation() from public, anon, authenticated, service_role;
