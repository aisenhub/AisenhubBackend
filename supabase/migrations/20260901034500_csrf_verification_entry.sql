-- Controlled CSRF verification for credentialed Platform API mutations.
-- Both inputs are one-way digests; raw session and CSRF tokens stay in the request layer.

create or replace function public.verify_platform_csrf(
  p_token_hash text,
  p_csrf_hash text
)
returns table (valid boolean)
language plpgsql
security definer
set search_path = pg_catalog, auth, platform
as $$
declare
  stored_csrf_hash text;
  difference integer := 0;
  position integer;
begin
  if p_token_hash is null or p_csrf_hash is null
     or btrim(p_token_hash) = '' or btrim(p_csrf_hash) = '' then
    return query select false;
    return;
  end if;

  select sessions.csrf_hash
    into stored_csrf_hash
    from platform.platform_sessions as sessions
   where sessions.token_hash = p_token_hash
     and sessions.revoked_at is null
     and sessions.expires_at > now();

  if not found or length(stored_csrf_hash) <> length(p_csrf_hash) then
    return query select false;
    return;
  end if;

  -- Compare every character after the fixed-length digest check instead of
  -- allowing an early mismatch to determine the result.
  for position in 1..length(stored_csrf_hash) loop
    difference := difference |
      (ascii(substr(stored_csrf_hash, position, 1)) #
       ascii(substr(p_csrf_hash, position, 1)));
  end loop;

  return query select difference = 0;
end;
$$;

comment on function public.verify_platform_csrf(text, text) is
  'Constant-time compares a session-bound CSRF digest for a current, non-revoked Platform Session.';

revoke all on function public.verify_platform_csrf(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.verify_platform_csrf(text, text)
  to anon, authenticated;
