begin;

select plan(19);

select is(
  to_regprocedure('public.get_platform_session(text)') is not null,
  true,
  'session read function exists'
);
select is(
  to_regprocedure('public.revoke_platform_session(text, text)') is not null,
  true,
  'single revoke function exists'
);
select is(
  to_regprocedure('public.revoke_all_platform_sessions(uuid, text)') is not null,
  true,
  'revoke-all function exists'
);
select is(
  has_function_privilege('anon', 'public.get_platform_session(text)', 'EXECUTE'),
  true,
  'anon can invoke the opaque session read entrypoint'
);
select is(
  has_function_privilege('anon', 'public.revoke_platform_session(text, text)', 'EXECUTE'),
  true,
  'anon can invoke the opaque single-session revoke entrypoint'
);
select is(
  has_function_privilege('anon', 'public.revoke_all_platform_sessions(uuid, text)', 'EXECUTE'),
  false,
  'anon cannot invoke revoke-all'
);
select is(
  has_function_privilege('authenticated', 'public.revoke_all_platform_sessions(uuid, text)', 'EXECUTE'),
  true,
  'authenticated can invoke self revoke-all'
);
select is(
  has_function_privilege('service_role', 'public.revoke_all_platform_sessions(uuid, text)', 'EXECUTE'),
  true,
  'service_role can invoke trusted revoke-all'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.get_platform_session(text)'::regprocedure),
  true,
  'session read is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.get_platform_session(text)'::regprocedure),
  array['search_path=pg_catalog, auth, platform']::text[],
  'session read pins search_path'
);

insert into auth.users (id, email)
values ('60000000-0000-4000-0000-000000000006', 'lifecycle.local@aisenhub.test');

insert into platform.platform_sessions
  (user_id, token_hash, csrf_hash, expires_at, last_seen_at, created_at)
values
  ('60000000-0000-4000-0000-000000000006', 'lifecycle-active-old', 'csrf-lifecycle-1', now() + interval '1 day', now() - interval '10 minutes', now() - interval '20 minutes'),
  ('60000000-0000-4000-0000-000000000006', 'lifecycle-active-new', 'csrf-lifecycle-2', now() + interval '1 day', now(), now()),
  ('60000000-0000-4000-0000-000000000006', 'lifecycle-expired', 'csrf-lifecycle-3', now() - interval '1 minute', now() - interval '10 minutes', now() - interval '20 minutes'),
  ('60000000-0000-4000-0000-000000000006', 'lifecycle-revoked', 'csrf-lifecycle-4', now() + interval '1 day', now(), now());

update platform.platform_sessions
   set revoked_at = now(), revoked_reason = 'test_setup'
 where token_hash = 'lifecycle-revoked';

set local role anon;
select is(
  (select count(*)::integer from public.get_platform_session('lifecycle-active-old')),
  1,
  'active session is readable with an opaque digest'
);
select is(
  (select count(*)::integer from public.get_platform_session('lifecycle-expired')),
  0,
  'expired session is not readable'
);
select is(
  (select count(*)::integer from public.get_platform_session('lifecycle-revoked')),
  0,
  'revoked session is not readable'
);
select is(
  (select count(*)::integer from public.get_platform_session('unknown-session-digest')),
  0,
  'unknown digest is indistinguishable from an invalid session'
);
set local role postgres;
select is(
  (select count(*)::integer
     from platform.platform_sessions
    where token_hash = 'lifecycle-active-old'
      and last_seen_at > now() - interval '1 minute'),
  1,
  'stale last_seen_at is refreshed by session validation'
);
set local role anon;
select is(
  (select revoked from public.revoke_platform_session('lifecycle-active-old', 'single_logout')),
  true,
  'single logout revokes the matching session'
);
set local role postgres;
select is(
  (select count(*)::integer
    from platform.platform_sessions
    where user_id = '60000000-0000-4000-0000-000000000006'
      and revoked_at is null
      and expires_at > now()),
  1,
  'single logout leaves the other active session untouched'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"60000000-0000-4000-0000-000000000006","role":"authenticated"}';
select is(
  public.revoke_all_platform_sessions('60000000-0000-4000-0000-000000000006', 'logout_all'),
  2,
  'self revoke-all revokes every remaining non-revoked session'
);
set local role postgres;
select is(
  (select count(*)::integer
    from platform.platform_sessions
    where user_id = '60000000-0000-4000-0000-000000000006'
      and revoked_at is null
      and expires_at > now()),
  0,
  'revoke-all leaves no active session for the user'
);

select * from finish();
rollback;
