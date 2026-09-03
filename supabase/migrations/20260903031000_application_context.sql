-- R2 application context resolution. The token-derived client_id is the only
-- authenticated application selector; Origin remains a separate browser check.

create or replace function public.resolve_application_context(
  p_user_id uuid,
  p_client_id text
)
returns table (
  user_id uuid,
  profile_status text,
  client_id text,
  client_status text,
  application_id uuid,
  application_slug text,
  application_status text,
  membership_id uuid,
  membership_status text,
  membership_policy text
)
language sql
security definer
stable
set search_path = pg_catalog, platform
as $$
  select profile.id,
         profile.status,
         client.external_client_id,
         client.status,
         app.id,
         app.slug,
         app.status,
         membership.id,
         membership.status,
         app.membership_policy
    from platform.profiles as profile
    join platform.application_oauth_clients as client
      on client.external_client_id = p_client_id
    join platform.platform_apps as app
      on app.id = client.application_id
    left join platform.application_memberships as membership
      on membership.application_id = app.id
     and membership.user_id = profile.id
   where p_user_id is not null
     and p_client_id is not null
     and btrim(p_client_id) <> ''
     and profile.id = p_user_id;
$$;

comment on function public.resolve_application_context(uuid, text) is
  'Resolves verified user and OAuth client claims into private Application Context facts; it never trusts a request application header.';

revoke all on function public.resolve_application_context(uuid, text)
  from public, anon, authenticated;
grant execute on function public.resolve_application_context(uuid, text)
  to service_role;
