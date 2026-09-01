-- Controlled exact-Origin resolution for CORS and application identity.

create or replace function public.resolve_app_origin(p_origin text)
returns table (
  app_slug text,
  environment text
)
language sql
stable
security definer
set search_path = pg_catalog, platform
as $$
  select apps.slug, origins.environment
    from platform.app_origins as origins
    join platform.platform_apps as apps on apps.id = origins.app_id
   where origins.origin = $1
     and origins.is_active
     and apps.status = 'active';
$$;

comment on function public.resolve_app_origin(text) is
  'Resolves one exact active Origin to its active application slug; wildcards and declarations are never accepted as authority.';

revoke all on function public.resolve_app_origin(text)
  from public, service_role;
grant execute on function public.resolve_app_origin(text)
  to anon, authenticated;
