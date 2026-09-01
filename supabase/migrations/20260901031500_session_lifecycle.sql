-- Controlled Platform Session lifecycle entrypoints.
-- The API supplies only one-way token digests; raw cookies never cross this boundary.

create or replace function public.get_platform_session(p_token_hash text)
returns table (
  session_id uuid,
  user_id uuid,
  expires_at timestamptz,
  display_name text,
  avatar_url text,
  locale text,
  profile_status text
)
language plpgsql
security definer
set search_path = pg_catalog, auth, platform
as $$
declare
  current_session record;
  current_profile record;
begin
  if p_token_hash is null or btrim(p_token_hash) = '' then
    return;
  end if;

  select sessions.id, sessions.user_id, sessions.expires_at, sessions.last_seen_at,
         sessions.revoked_at
    into current_session
    from platform.platform_sessions as sessions
   where sessions.token_hash = p_token_hash
   for update;

  if not found
     or current_session.revoked_at is not null
     or current_session.expires_at <= now() then
    return;
  end if;

  select profiles.display_name, profiles.avatar_url, profiles.locale, profiles.status
    into current_profile
    from platform.profiles as profiles
   where profiles.id = current_session.user_id;

  if not found or current_profile.status <> 'active' then
    return;
  end if;

  if current_session.last_seen_at <= now() - interval '5 minutes' then
    update platform.platform_sessions
       set last_seen_at = now()
     where id = current_session.id;
  end if;

  return query
  select current_session.id,
         current_session.user_id,
         current_session.expires_at,
         current_profile.display_name,
         current_profile.avatar_url,
         current_profile.locale,
         current_profile.status;
end;
$$;

comment on function public.get_platform_session(text) is
  'Validates one Platform Session digest, returns minimal identity, and throttles last_seen_at updates.';

revoke all on function public.get_platform_session(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_platform_session(text)
  to anon, authenticated;

create or replace function public.revoke_platform_session(
  p_token_hash text,
  p_reason text default 'user_logout'
)
returns table (revoked boolean)
language plpgsql
security definer
set search_path = pg_catalog, auth, platform
as $$
begin
  if p_token_hash is null or btrim(p_token_hash) = '' then
    return query select false;
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception using
      errcode = '22023',
      message = 'A session revoke reason is required';
  end if;

  update platform.platform_sessions
     set revoked_at = coalesce(revoked_at, now()),
         revoked_reason = coalesce(revoked_reason, btrim(p_reason))
   where token_hash = p_token_hash
     and revoked_at is null;

  return query select found;
end;
$$;

comment on function public.revoke_platform_session(text, text) is
  'Revokes only the Platform Session matching one supplied digest; unknown digests are harmless.';

revoke all on function public.revoke_platform_session(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.revoke_platform_session(text, text)
  to anon, authenticated;

create or replace function public.revoke_all_platform_sessions(
  p_user_id uuid,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, auth, platform
as $$
declare
  caller_role text := coalesce(auth.jwt() ->> 'role', '');
  affected_rows integer;
begin
  if p_user_id is null or p_reason is null or btrim(p_reason) = '' then
    raise exception using
      errcode = '22023',
      message = 'A user and session revoke reason are required';
  end if;

  if caller_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id) then
    raise exception using
      errcode = '42501',
      message = 'Session revocation identity does not match the authenticated user';
  end if;

  update platform.platform_sessions
     set revoked_at = coalesce(revoked_at, now()),
         revoked_reason = coalesce(revoked_reason, btrim(p_reason))
   where user_id = p_user_id
     and revoked_at is null;

  get diagnostics affected_rows = row_count;
  return affected_rows;
end;
$$;

comment on function public.revoke_all_platform_sessions(uuid, text) is
  'Revokes every active Platform Session for a user; self-service or trusted service role only.';

revoke all on function public.revoke_all_platform_sessions(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.revoke_all_platform_sessions(uuid, text)
  to authenticated, service_role;
