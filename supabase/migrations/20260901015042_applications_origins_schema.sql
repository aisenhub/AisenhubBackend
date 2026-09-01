-- AisenHub application registry and exact Origin allow-list.
-- Application identity is derived by the backend from Origin; browser headers are not authoritative.

create table platform.platform_apps (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  category text not null,
  status text not null default 'draft',
  primary_feature_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_apps_slug_key unique (slug),
  constraint platform_apps_slug_format_check
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint platform_apps_name_nonempty_check
    check (btrim(name) <> ''),
  constraint platform_apps_category_nonempty_check
    check (btrim(category) <> ''),
  constraint platform_apps_status_check
    check (status in ('draft', 'active', 'suspended', 'retired')),
  constraint platform_apps_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

comment on table platform.platform_apps is
  'Backend-owned registry of applications that may use the Platform API.';

comment on column platform.platform_apps.slug is
  'Lowercase machine identity; it becomes immutable once an Origin references the app.';

comment on column platform.platform_apps.primary_feature_id is
  'Reserved for the Catalog feature registry introduced in a later migration.';

create table platform.app_origins (
  id uuid primary key default gen_random_uuid(),
  app_id uuid not null references platform.platform_apps(id) on delete restrict,
  environment text not null,
  origin text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint app_origins_environment_check
    check (environment in ('development', 'staging', 'production')),
  constraint app_origins_origin_key unique (origin),
  constraint app_origins_origin_exact_check
    check (
      origin = lower(origin)
      and origin !~ '[*[:space:]]'
      and origin ~ '^https?://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$'
    )
);

comment on table platform.app_origins is
  'Exact Origin allow-list used by the backend to derive the calling application.';

comment on column platform.app_origins.origin is
  'Canonical scheme, host, and optional port only; paths, wildcards, query strings, and fragments are rejected.';

create index platform_apps_status_idx
  on platform.platform_apps (status);

create index app_origins_app_id_idx
  on platform.app_origins (app_id);

create index app_origins_active_lookup_idx
  on platform.app_origins (origin, is_active)
  where is_active;

create or replace function platform.prevent_referenced_app_slug_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.slug is distinct from old.slug
     and exists (
       select 1
       from platform.app_origins
       where app_id = old.id
     ) then
    raise exception using
      errcode = '23514',
      message = 'application slug cannot change after an Origin references the app';
  end if;
  return new;
end;
$$;

create trigger platform_apps_prevent_referenced_slug_change
before update on platform.platform_apps
for each row
execute function platform.prevent_referenced_app_slug_change();

create or replace function platform.prevent_origin_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.app_id is distinct from old.app_id
     or new.environment is distinct from old.environment
     or new.origin is distinct from old.origin then
    raise exception using
      errcode = '23514',
      message = 'application Origin identity cannot change; deactivate it and create a new exact Origin';
  end if;
  return new;
end;
$$;

create trigger app_origins_prevent_identity_change
before update on platform.app_origins
for each row
execute function platform.prevent_origin_identity_change();

create trigger platform_apps_set_updated_at
before update on platform.platform_apps
for each row
execute function platform.set_updated_at();

create trigger app_origins_set_updated_at
before update on platform.app_origins
for each row
execute function platform.set_updated_at();

alter table platform.platform_apps enable row level security;
alter table platform.app_origins enable row level security;

revoke all on table platform.platform_apps, platform.app_origins
  from public, anon, authenticated, service_role;
revoke all on function platform.prevent_referenced_app_slug_change()
  from public, anon, authenticated, service_role;
revoke all on function platform.prevent_origin_identity_change()
  from public, anon, authenticated, service_role;
