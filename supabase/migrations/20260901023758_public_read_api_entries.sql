-- Controlled public entries for API read paths. Platform tables remain private.

create or replace function public.get_public_app(app_slug text)
returns table (
  slug text,
  name text,
  category text,
  status text
)
language sql
stable
security definer
set search_path = pg_catalog, platform
as $$
  select
    apps.slug,
    apps.name,
    apps.category,
    apps.status
  from platform.platform_apps as apps
  where apps.slug = $1
    and apps.status = 'active';
$$;

comment on function public.get_public_app(text) is
  'Returns the minimal active application identity for public API reads.';

revoke all on function public.get_public_app(text) from public, service_role;
grant execute on function public.get_public_app(text) to anon, authenticated;
