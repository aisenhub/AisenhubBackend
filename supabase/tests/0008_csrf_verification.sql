begin;

select plan(10);

select ok(
  to_regprocedure('public.verify_platform_csrf(text, text)') is not null,
  'CSRF verification function exists'
);
select ok(
  has_function_privilege('anon', 'public.verify_platform_csrf(text, text)', 'EXECUTE'),
  'anon can invoke CSRF verification without reading session rows'
);
select ok(
  not has_function_privilege('service_role', 'public.verify_platform_csrf(text, text)', 'EXECUTE'),
  'service_role does not receive direct CSRF verification execution'
);
select ok(
  exists (
    select 1
      from pg_proc
     where oid = 'public.verify_platform_csrf(text, text)'::regprocedure
       and prosecdef
       and proconfig @> array['search_path=pg_catalog, auth, platform']::text[]
  ),
  'CSRF verification uses SECURITY DEFINER with a fixed search_path'
);

insert into auth.users (id, email)
values ('80000000-0000-4000-0000-000000000008', 'csrf.local@aisenhub.test');

insert into platform.platform_sessions
  (user_id, token_hash, csrf_hash, expires_at, last_seen_at, created_at)
values
  ('80000000-0000-4000-0000-000000000008', 'csrf-session-1', 'csrf-digest-1', now() + interval '1 day', now(), now()),
  ('80000000-0000-4000-0000-000000000008', 'csrf-session-2', 'csrf-digest-2', now() + interval '1 day', now(), now()),
  ('80000000-0000-4000-0000-000000000008', 'csrf-session-expired', 'csrf-digest-expired', now() - interval '1 minute', now() - interval '2 minutes', now() - interval '3 minutes');

set local role anon;
select is(
  (select valid from public.verify_platform_csrf('csrf-session-1', 'csrf-digest-1')),
  true,
  'the matching CSRF digest is accepted'
);
select is(
  (select valid from public.verify_platform_csrf('csrf-session-1', 'csrf-digest-2')),
  false,
  'a CSRF digest from another session is rejected'
);
select is(
  (select valid from public.verify_platform_csrf('csrf-session-1', 'wrong-digest')),
  false,
  'a wrong CSRF digest is rejected'
);
select is(
  (select valid from public.verify_platform_csrf('unknown-session', 'csrf-digest-1')),
  false,
  'an unknown session is rejected'
);
select is(
  (select valid from public.verify_platform_csrf('csrf-session-expired', 'csrf-digest-expired')),
  false,
  'an expired session is rejected'
);

set local role postgres;
update platform.platform_sessions
   set revoked_at = now(), revoked_reason = 'test_revoke'
 where token_hash = 'csrf-session-2';
set local role anon;
select is(
  (select valid from public.verify_platform_csrf('csrf-session-2', 'csrf-digest-2')),
  false,
  'a revoked session is rejected'
);

select * from finish();
rollback;
