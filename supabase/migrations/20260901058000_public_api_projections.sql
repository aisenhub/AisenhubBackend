-- Public catalog and server-owned product API projections.

create table platform.feedback_requests (
  id uuid primary key default gen_random_uuid(),
  app_id uuid not null references platform.platform_apps(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  kind text not null,
  title text not null,
  content text not null,
  status text not null default 'open',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint feedback_requests_kind_nonempty_check check (btrim(kind) <> ''),
  constraint feedback_requests_title_nonempty_check check (btrim(title) <> ''),
  constraint feedback_requests_content_nonempty_check check (btrim(content) <> ''),
  constraint feedback_requests_status_check check (status in ('open', 'in_progress', 'resolved', 'closed'))
);

comment on table platform.feedback_requests is
  'User feedback attributed to the server-resolved application, never to a client-supplied app ID.';

create index feedback_requests_app_created_idx
  on platform.feedback_requests (app_id, created_at desc);

create index feedback_requests_user_created_idx
  on platform.feedback_requests (user_id, created_at desc);

create trigger feedback_requests_set_updated_at
before update on platform.feedback_requests
for each row
execute function platform.set_updated_at();

create or replace function public.get_public_products()
returns table (
  sku text,
  name text,
  billing_type text,
  version integer
)
language sql
security definer
stable
set search_path = pg_catalog, platform
as $$
  select product.sku, product.name, product.billing_type, version.version
    from platform.products as product
    join platform.product_versions as version
      on version.id = product.current_version_id
     and version.product_id = product.id
   where product.status = 'active'
     and version.status = 'published'
   order by product.sku;
$$;

create or replace function public.list_user_entitlements(p_user_id uuid)
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
    join platform.products as product
      on product.id = grant_item.product_id
   where grant_item.user_id = p_user_id
     and grant_item.status = 'active'
     and grant_item.starts_at <= timezone('utc', now())
     and (grant_item.expires_at is null or grant_item.expires_at > timezone('utc', now()))
   order by feature.code, grant_item.created_at desc, grant_item.id desc;
$$;

create or replace function public.create_feedback(
  p_app_slug text,
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_content text
)
returns table (
  id uuid,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  app_id_value uuid;
  feedback_id_value uuid := gen_random_uuid();
begin
  if p_app_slug is null or p_user_id is null or p_kind is null or btrim(p_kind) = ''
     or p_title is null or btrim(p_title) = ''
     or p_content is null or btrim(p_content) = '' then
    raise exception using errcode = '23514', message = 'Feedback fields are required';
  end if;

  select app.id
    into app_id_value
    from platform.platform_apps as app
   where app.slug = p_app_slug
     and app.status = 'active';

  if not found then
    raise exception using errcode = 'P0002', message = 'Application was not found';
  end if;

  insert into platform.feedback_requests (id, app_id, user_id, kind, title, content)
  values (feedback_id_value, app_id_value, p_user_id, p_kind, p_title, p_content);

  return query select feedback_id_value, 'open', now();
end;
$$;

comment on function public.get_public_products() is
  'Returns only active products and their current published version for the public catalog.';
comment on function public.list_user_entitlements(uuid) is
  'Returns active entitlement snapshots for server-side authenticated account views.';
comment on function public.create_feedback(text, uuid, text, text, text) is
  'Creates feedback using the server-resolved application identity.';

alter table platform.feedback_requests enable row level security;
revoke all on table platform.feedback_requests from public, anon, authenticated, service_role;
revoke all on function public.get_public_products() from public, service_role;
grant execute on function public.get_public_products() to anon, authenticated;
revoke all on function public.list_user_entitlements(uuid) from public, anon, authenticated;
grant execute on function public.list_user_entitlements(uuid) to service_role;
revoke all on function public.create_feedback(text, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.create_feedback(text, uuid, text, text, text) to service_role;
