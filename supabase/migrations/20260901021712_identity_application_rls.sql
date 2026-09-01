-- Public exposes only a minimal, user-scoped profile projection.
-- Sensitive identity/application/session tables remain private in platform.

create or replace function public.current_profile()
returns table (
  id uuid,
  display_name text,
  avatar_url text,
  locale text,
  status text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, auth, platform
as $$
  select
    profiles.id,
    profiles.display_name,
    profiles.avatar_url,
    profiles.locale,
    profiles.status,
    profiles.created_at,
    profiles.updated_at
  from platform.profiles
  where auth.uid() is not null
    and profiles.id = auth.uid();
$$;

comment on function public.current_profile() is
  'Authenticated user-scoped profile projection; never exposes another user or profile deletion metadata.';

revoke all on function public.current_profile() from public, anon, service_role;
grant execute on function public.current_profile() to authenticated;
