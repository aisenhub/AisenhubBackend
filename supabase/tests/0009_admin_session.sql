begin;

select plan(16);

select ok(
  to_regprocedure('public.get_admin_session(text)') is not null,
  'Admin Session entrypoint exists'
);
select ok(
  has_function_privilege('anon', 'public.get_admin_session(text)', 'EXECUTE'),
  'anon can invoke the opaque Admin Session entrypoint'
);
select ok(
  has_function_privilege('authenticated', 'public.get_admin_session(text)', 'EXECUTE'),
  'authenticated can invoke the opaque Admin Session entrypoint'
);
select ok(
  not has_function_privilege('service_role', 'public.get_admin_session(text)', 'EXECUTE'),
  'service_role has no direct Admin Session entrypoint grant'
);
select ok(
  exists (
    select 1
      from pg_proc
     where oid = 'public.get_admin_session(text)'::regprocedure
       and prosecdef
       and proconfig @> array['search_path=pg_catalog, auth, platform']::text[]
  ),
  'Admin Session entrypoint is SECURITY DEFINER with a fixed search_path'
);
select ok(
  not exists (
    select 1
      from information_schema.columns
     where table_schema = 'platform'
       and table_name = 'platform_sessions'
       and column_name in ('token', 'csrf_token')
  ),
  'Admin Session storage has no raw token columns'
);

insert into auth.users (id, email)
values
  ('90000000-0000-4000-0000-000000000009', 'admin-session.local@aisenhub.test'),
  ('90000000-0000-4000-0000-000000000010', 'admin-session-user.local@aisenhub.test');

insert into platform.admin_members (user_id, role, status, disabled_at)
values
  ('90000000-0000-4000-0000-000000000009', 'admin', 'active', null),
  ('90000000-0000-4000-0000-000000000010', 'support', 'disabled', now());

insert into platform.platform_sessions
  (user_id, token_hash, csrf_hash, expires_at, last_seen_at, created_at)
values
  ('90000000-0000-4000-0000-000000000009', 'admin-session-active', 'admin-csrf-active', now() + interval '1 day', now(), now()),
  ('90000000-0000-4000-0000-000000000009', 'admin-session-expired', 'admin-csrf-expired', now() - interval '1 minute', now() - interval '2 minutes', now() - interval '2 minutes'),
  ('90000000-0000-4000-0000-000000000009', 'admin-session-revoked', 'admin-csrf-revoked', now() + interval '1 day', now(), now()),
  ('90000000-0000-4000-0000-000000000010', 'admin-session-disabled', 'admin-csrf-disabled', now() + interval '1 day', now(), now());

update platform.platform_sessions
   set revoked_at = now(), revoked_reason = 'test_setup'
 where token_hash = 'admin-session-revoked';

set local role anon;
select is(
  (select count(*)::integer from public.get_admin_session('admin-session-active')),
  1,
  'active Admin membership returns one minimal session'
);
select is(
  (select role from public.get_admin_session('admin-session-active')),
  'admin',
  'Admin role comes from the controlled membership table'
);
select is(
  (select aal from public.get_admin_session('admin-session-active')),
  'aal1',
  'current Local Auth assurance is reported as AAL1'
);
select is(
  (select mfa_state from public.get_admin_session('admin-session-active')),
  'required',
  'Admin MFA elevation is required before high-risk actions'
);
select ok(
  (select expires_at < now() + interval '16 minutes' from public.get_admin_session('admin-session-active')),
  'Admin Session exposes a short effective expiry'
);
select is(
  (select count(*)::integer from public.get_admin_session('admin-session-expired')),
  0,
  'expired Platform Sessions cannot enter Admin'
);
select is(
  (select count(*)::integer from public.get_admin_session('admin-session-revoked')),
  0,
  'revoked Platform Sessions cannot enter Admin'
);
select is(
  (select count(*)::integer from public.get_admin_session('admin-session-disabled')),
  0,
  'disabled Admin memberships cannot enter Admin'
);
select is(
  (select count(*)::integer from public.get_admin_session('unknown-admin-session')),
  0,
  'unknown session digests are indistinguishable from denied Admin access'
);
select is(
  (select count(*)::integer from public.get_admin_session(null)),
  0,
  'blank Admin session digests return no identity'
);

select * from finish();
rollback;
