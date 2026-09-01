begin;

select plan(17);

select has_table('platform', 'profiles', 'profiles table exists');
select col_is_pk('platform', 'profiles', 'id', 'profile id is the primary key');
select col_not_null('platform', 'profiles', 'status', 'profile status is required');
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'platform.profiles'::regclass
      and conname = 'profiles_status_check'
  ),
  'profile status has an allow-list constraint'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.profiles'::regclass),
  'profiles has RLS enabled as defense in depth'
);
select ok(
  not has_table_privilege('anon', 'platform.profiles', 'SELECT'),
  'anon cannot read the private profiles table directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.profiles', 'SELECT'),
  'authenticated cannot read the private profiles table directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.profiles', 'SELECT'),
  'service_role cannot read the private profiles table directly'
);
select ok(
  not has_function_privilege('anon', 'platform.handle_new_auth_user()', 'EXECUTE'),
  'anon cannot execute the Auth profile trigger function'
);
select ok(
  not has_function_privilege('authenticated', 'platform.handle_new_auth_user()', 'EXECUTE'),
  'authenticated cannot execute the Auth profile trigger function'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '30000000-0000-4000-8000-000000000001',
      'authenticated',
      'authenticated',
      'profile-test.local@aisenhub.test',
      'not-used-by-this-test',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false
    );
  $$,
  'a new Auth user creates a profile through the controlled trigger'
);
select ok(
  exists (
    select 1 from platform.profiles
    where id = '30000000-0000-4000-8000-000000000001'
      and status = 'active'
  ),
  'new Auth user has an active profile'
);
select throws_ok(
  $$
    update platform.profiles
    set status = 'not-a-profile-status'
    where id = '30000000-0000-4000-8000-000000000001';
  $$,
  '23514',
  null,
  'invalid profile status is rejected'
);
select throws_ok(
  $$
    update platform.profiles
    set status = 'deleted', deleted_at = null
    where id = '30000000-0000-4000-8000-000000000001';
  $$,
  '23514',
  null,
  'deleted profile requires a deletion timestamp'
);
select throws_ok(
  $$
    update platform.profiles
    set id = '30000000-0000-4000-8000-000000000002'
    where id = '30000000-0000-4000-8000-000000000001';
  $$,
  '23514',
  null,
  'profile identity cannot be changed'
);
select lives_ok(
  $$
    delete from auth.users
    where id = '30000000-0000-4000-8000-000000000001';
  $$,
  'deleting an Auth user cascades its profile'
);
select ok(
  not exists (
    select 1 from platform.profiles
    where id = '30000000-0000-4000-8000-000000000001'
  ),
  'profile is removed with its Auth identity'
);

select * from finish();
rollback;
