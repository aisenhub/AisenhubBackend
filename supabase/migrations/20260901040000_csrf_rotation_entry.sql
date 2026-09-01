-- Rotate the in-memory CSRF token during an authenticated session bootstrap.

create or replace function platform.prevent_session_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.user_id is distinct from old.user_id
     or new.token_hash is distinct from old.token_hash
     or new.idempotency_record_id is distinct from old.idempotency_record_id then
    raise exception using
      errcode = '23514',
      message = 'Platform Session identity fields cannot change';
  end if;
  return new;
end;
$$;

create or replace function public.rotate_platform_csrf(
  p_token_hash text,
  p_csrf_hash text
)
returns table (issued boolean)
language plpgsql
security definer
set search_path = pg_catalog, auth, platform
as $$
begin
  if p_token_hash is null or p_csrf_hash is null
     or btrim(p_token_hash) = '' or btrim(p_csrf_hash) = '' then
    return query select false;
    return;
  end if;

  update platform.platform_sessions
     set csrf_hash = p_csrf_hash
   where token_hash = p_token_hash
     and revoked_at is null
     and expires_at > now();

  return query select found;
end;
$$;

comment on function public.rotate_platform_csrf(text, text) is
  'Replaces the CSRF digest for a current Platform Session; only the raw token is returned by the API layer.';

revoke all on function public.rotate_platform_csrf(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.rotate_platform_csrf(text, text)
  to anon, authenticated;
