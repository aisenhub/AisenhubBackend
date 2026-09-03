-- Resolve the Admin role from the bearer-authenticated identity.
-- The Admin API never reads this table from a browser or accepts role claims
-- from an unverified request header.

create or replace function public.resolve_admin_membership(p_user_id uuid)
returns table (
  user_id uuid,
  display_name text,
  role text,
  status text
)
language sql
security definer
stable
set search_path = pg_catalog, platform
as $$
  select member.user_id, profile.display_name, member.role, member.status
    from platform.admin_members as member
    join platform.profiles as profile on profile.id = member.user_id
   where member.user_id = p_user_id
     and member.status = 'active'
   limit 1;
$$;

comment on function public.resolve_admin_membership(uuid) is
  'Resolves the active Admin role for a verified bearer identity.';

revoke all on function public.resolve_admin_membership(uuid) from public, anon, authenticated;
grant execute on function public.resolve_admin_membership(uuid) to service_role;
