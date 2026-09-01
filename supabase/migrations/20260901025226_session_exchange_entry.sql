-- Controlled session exchange entry. The Edge Function supplies only digests;
-- the raw cookie and CSRF values never enter PostgreSQL.

create or replace function public.create_platform_session(
  p_user_id uuid,
  p_token_hash text,
  p_csrf_hash text,
  p_expires_at timestamptz
)
returns table (
  session_id uuid,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, auth, platform
as $$
declare
  created_session_id uuid;
begin
  if auth.uid() is null or auth.uid() is distinct from p_user_id then
    raise exception using
      errcode = '42501',
      message = 'Session exchange identity does not match the authenticated user';
  end if;

  insert into platform.platform_sessions
    (user_id, token_hash, csrf_hash, expires_at, last_seen_at)
  values
    (p_user_id, p_token_hash, p_csrf_hash, p_expires_at, timezone('utc', now()))
  returning id into created_session_id;

  return query
    select sessions.id, sessions.expires_at
    from platform.platform_sessions as sessions
    where sessions.id = created_session_id;
end;
$$;

comment on function public.create_platform_session(uuid, text, text, timestamptz) is
  'Creates one hashed Platform Session only for the Auth identity in the request context.';

revoke all on function public.create_platform_session(uuid, text, text, timestamptz)
  from public, anon, service_role;
grant execute on function public.create_platform_session(uuid, text, text, timestamptz)
  to authenticated;
