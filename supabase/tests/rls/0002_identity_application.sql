begin;

select plan(16);

select ok(
  exists (
    select 1
    from pg_proc
    where oid = 'public.current_profile()'::regprocedure
      and prosecdef
  ),
  'current profile projection exists as a security-definer function'
);
select ok(
  has_function_privilege('authenticated', 'public.current_profile()', 'EXECUTE'),
  'authenticated can execute the approved profile projection'
);
select ok(
  not has_function_privilege('anon', 'public.current_profile()', 'EXECUTE'),
  'anon cannot execute the profile projection'
);
select ok(
  not has_function_privilege('service_role', 'public.current_profile()', 'EXECUTE'),
  'service_role is not granted direct projection execution'
);
select ok(
  not has_table_privilege('authenticated', 'platform.profiles', 'SELECT'),
  'authenticated cannot bypass the projection to read profiles'
);
select ok(
  not has_table_privilege('authenticated', 'platform.platform_apps', 'SELECT'),
  'authenticated cannot read the application registry directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.platform_sessions', 'SELECT'),
  'authenticated cannot read Platform Sessions directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.admin_members', 'SELECT'),
  'authenticated cannot read Admin memberships directly'
);
select ok(
  exists (
    select 1
    from pg_proc
    where oid = 'public.current_profile()'::regprocedure
      and proconfig @> array['search_path=pg_catalog, auth, platform']::text[]
  ),
  'profile projection uses a fixed search path'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('50000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'rls-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('50000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'rls-other.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);
  $$,
  'RLS projection users can be created'
);
select lives_ok(
  $$
    update platform.profiles
    set display_name = 'RLS Owner', avatar_url = 'https://cdn.example.test/avatar.png', locale = 'zh-CN'
    where id = '50000000-0000-4000-8000-000000000001';
  $$,
  'profile fixture can be prepared by the database test owner'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-4000-8000-000000000001', true);
select is(
  (select count(*)::integer from public.current_profile()),
  1,
  'authenticated user sees exactly one own profile'
);
select is(
  (select display_name from public.current_profile()),
  'RLS Owner',
  'authenticated user sees own profile fields'
);
select ok(
  not exists (
    select 1 from public.current_profile()
    where id = '50000000-0000-4000-8000-000000000002'
  ),
  'authenticated user cannot see another profile'
);

set local role anon;
select set_config('request.jwt.claim.sub', '50000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select count(*) from public.current_profile(); $$,
  '42501',
  null,
  'anon cannot query the profile projection'
);

set local role service_role;
select set_config('request.jwt.claim.sub', '50000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select count(*) from public.current_profile(); $$,
  '42501',
  null,
  'service_role cannot query the profile projection directly'
);

select * from finish();
rollback;
