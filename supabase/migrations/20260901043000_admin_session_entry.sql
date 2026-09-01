-- Controlled Admin Session read entrypoint.
-- The caller supplies only the one-way Platform Session digest.

create or replace function public.get_admin_session(p_token_hash text)
returns table (
  user_id uuid,
  display_name text,
  role text,
  aal text,
  mfa_state text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, auth, platform
as $$
begin
  if p_token_hash is null or btrim(p_token_hash) = '' then
    return;
  end if;

  return query
  select sessions.user_id,
         profiles.display_name,
         members.role,
         'aal1'::text as aal,
         'required'::text as mfa_state,
         least(sessions.expires_at, sessions.created_at + interval '15 minutes') as expires_at
    from platform.platform_sessions as sessions
    join platform.profiles as profiles
      on profiles.id = sessions.user_id
    join platform.admin_members as members
      on members.user_id = sessions.user_id
   where sessions.token_hash = p_token_hash
     and sessions.revoked_at is null
     and sessions.expires_at > now()
     and sessions.created_at + interval '15 minutes' > now()
     and profiles.status = 'active'
     and members.status = 'active';
end;
$$;

comment on function public.get_admin_session(text) is
  'Returns minimal active Admin identity from an unexpired Platform Session and active membership.';

revoke all on function public.get_admin_session(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_admin_session(text)
  to anon, authenticated;
