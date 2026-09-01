begin;

select plan(10);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_platform_session(uuid, text, text, timestamptz)',
    'EXECUTE'
  ),
  'authenticated can execute the session exchange entry'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.create_platform_session(uuid, text, text, timestamptz)',
    'EXECUTE'
  ),
  'anon cannot execute the session exchange entry'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.create_platform_session(uuid, text, text, timestamptz)',
    'EXECUTE'
  ),
  'service_role is not granted direct session exchange execution'
);
select ok(
  exists (
    select 1
    from pg_proc
    where oid = 'public.create_platform_session(uuid, text, text, timestamptz)'::regprocedure
      and prosecdef
      and proconfig @> array['search_path=pg_catalog, auth, platform']::text[]
  ),
  'session exchange entry uses a fixed search path'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'platform'
      and table_name = 'platform_sessions'
      and column_name in ('token', 'csrf_token')
  ),
  'session exchange storage has no raw token columns'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '60000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'exchange.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
  $$,
  'session exchange test user can be created'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
select is(
  (select count(*)::integer
   from public.create_platform_session(
     '60000000-0000-4000-8000-000000000001',
     'sha256-token-digest-1',
     'sha256-csrf-digest-1',
     now() + interval '30 days'
   )),
  1,
  'authenticated user can create one Platform Session through the entry'
);
set local role postgres;
select is(
  (select count(*)::integer
   from platform.platform_sessions
   where user_id = '60000000-0000-4000-8000-000000000001'
     and token_hash = 'sha256-token-digest-1'
     and csrf_hash = 'sha256-csrf-digest-1'),
  1,
  'session exchange stores only supplied digests'
);
set local role authenticated;
select throws_ok(
  $$
    select * from public.create_platform_session(
      '60000000-0000-4000-8000-000000000002',
      'sha256-token-digest-2',
      'sha256-csrf-digest-2',
      now() + interval '30 days'
    );
  $$,
  '42501', null,
  'session exchange rejects an identity different from auth.uid'
);
select throws_ok(
  $$
    select * from public.create_platform_session(
      '60000000-0000-4000-8000-000000000001',
      'sha256-token-digest-3',
      'sha256-csrf-digest-3',
      now() - interval '1 minute'
    );
  $$,
  '23514', null,
  'session exchange rejects an already expired session'
);

select * from finish();
rollback;
