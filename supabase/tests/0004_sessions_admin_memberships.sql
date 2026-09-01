begin;

select plan(29);

select has_table('platform', 'platform_sessions', 'Platform Session table exists');
select has_table('platform', 'admin_members', 'Admin membership table exists');
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'platform'
      and table_name = 'platform_sessions'
      and column_name in ('token', 'csrf_token')
  ),
  'raw session and CSRF token columns do not exist'
);
select has_index(
  'platform',
  'platform_sessions',
  'platform_sessions_token_hash_key',
  'session token hashes are unique'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.platform_sessions'::regclass),
  'Platform Sessions have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.admin_members'::regclass),
  'Admin memberships have RLS enabled'
);
select ok(
  not has_table_privilege('anon', 'platform.platform_sessions', 'SELECT'),
  'anon cannot read Platform Sessions directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.admin_members', 'SELECT'),
  'authenticated cannot read Admin memberships directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.admin_members', 'INSERT'),
  'service_role cannot insert Admin memberships directly'
);
select ok(
  not has_function_privilege('anon', 'platform.prevent_session_identity_change()', 'EXECUTE'),
  'anon cannot execute the session identity trigger directly'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'platform.admin_members'::regclass
      and conname = 'admin_members_role_check'
  ),
  'Admin role constraint exists'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('40000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'session-admin.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('40000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'session-user.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('40000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
       'session-support.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);
  $$,
  'session and Admin test Auth users can be created'
);
select lives_ok(
  $$
    insert into platform.platform_sessions
      (id, user_id, token_hash, csrf_hash, expires_at, last_seen_at)
    values
      ('41000000-0000-4000-8000-000000000001',
       '40000000-0000-4000-8000-000000000002',
       'token-hash-session-1', 'csrf-hash-session-1',
       now() + interval '30 days', now());
  $$,
  'a Platform Session stores hashes for a user'
);
select lives_ok(
  $$
    update platform.platform_sessions
    set revoked_at = now(), revoked_reason = 'test logout'
    where id = '41000000-0000-4000-8000-000000000001';
  $$,
  'session revocation fields are mutable'
);
select throws_ok(
  $$
    insert into platform.platform_sessions
      (user_id, token_hash, csrf_hash, expires_at, last_seen_at)
    values
      ('40000000-0000-4000-8000-000000000002', '', 'csrf-hash-session-2', now() + interval '1 day', now());
  $$,
  '23514', null,
  'blank session token hashes are rejected'
);
select throws_ok(
  $$
    insert into platform.platform_sessions
      (user_id, token_hash, csrf_hash, expires_at, last_seen_at, created_at)
    values
      ('40000000-0000-4000-8000-000000000002', 'token-hash-session-2', 'csrf-hash-session-2', now(), now(), now());
  $$,
  '23514', null,
  'expired-at-creation sessions are rejected'
);
select throws_ok(
  $$
    insert into platform.platform_sessions
      (user_id, token_hash, csrf_hash, expires_at, last_seen_at)
    values
      ('40000000-0000-4000-8000-000000000002', 'token-hash-session-1', 'csrf-hash-session-3', now() + interval '1 day', now());
  $$,
  '23505', null,
  'duplicate session token hashes are rejected'
);
select throws_ok(
  $$
    update platform.platform_sessions
    set token_hash = 'changed-token-hash'
    where id = '41000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'session token hash identity cannot change'
);
select lives_ok(
  $$
    insert into platform.idempotency_records
      (id, scope, actor_key, idempotency_key, request_hash, expires_at)
    values
      ('42000000-0000-4000-8000-000000000001', 'session.exchange', '40000000-0000-4000-8000-000000000002', 'test-idempotency-1', 'hash-1', now() + interval '1 day');
    insert into platform.platform_sessions
      (id, user_id, token_hash, csrf_hash, expires_at, last_seen_at, idempotency_record_id)
    values
      ('41000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000001', 'token-hash-session-2', 'csrf-hash-session-4', now() + interval '30 days', now(), '42000000-0000-4000-8000-000000000001');
  $$,
  'a session can link one idempotency record'
);
select throws_ok(
  $$
    insert into platform.platform_sessions
      (user_id, token_hash, csrf_hash, expires_at, last_seen_at, idempotency_record_id)
    values
      ('40000000-0000-4000-8000-000000000003', 'token-hash-session-3', 'csrf-hash-session-5', now() + interval '30 days', now(), '42000000-0000-4000-8000-000000000001');
  $$,
  '23505', null,
  'an idempotency record can link to only one session'
);

select lives_ok(
  $$
    insert into platform.admin_members (user_id, role)
    values ('40000000-0000-4000-8000-000000000001', 'owner');
    insert into platform.admin_members (user_id, role, created_by)
    values ('40000000-0000-4000-8000-000000000003', 'support', '40000000-0000-4000-8000-000000000001');
  $$,
  'owner and support Admin memberships use the fixed role set'
);
select ok(
  not exists (
    select 1 from platform.admin_members
    where user_id = '40000000-0000-4000-8000-000000000002'
  ),
  'normal test user has no Admin membership'
);
select throws_ok(
  $$
    insert into platform.admin_members (user_id, role)
    values ('40000000-0000-4000-8000-000000000002', 'operator');
  $$,
  '23514', null,
  'unapproved Admin roles are rejected'
);
select throws_ok(
  $$
    insert into platform.admin_members (user_id, role, status)
    values ('40000000-0000-4000-8000-000000000002', 'finance', 'pending');
  $$,
  '23514', null,
  'unapproved Admin statuses are rejected'
);
select throws_ok(
  $$
    insert into platform.admin_members (user_id, role, status)
    values ('40000000-0000-4000-8000-000000000002', 'finance', 'disabled');
  $$,
  '23514', null,
  'disabled Admin memberships require a timestamp'
);
select throws_ok(
  $$
    insert into platform.admin_members (user_id, role)
    values ('40000000-0000-4000-8000-000000000001', 'admin');
  $$,
  '23505', null,
  'a user can have at most one Admin membership'
);
select throws_ok(
  $$
    update platform.admin_members
    set user_id = '40000000-0000-4000-8000-000000000002'
    where user_id = '40000000-0000-4000-8000-000000000003';
  $$,
  '23514', null,
  'Admin membership identity cannot change'
);
select lives_ok(
  $$
    update platform.admin_members
    set status = 'disabled', disabled_at = now()
    where user_id = '40000000-0000-4000-8000-000000000003';
  $$,
  'Admin membership can be disabled with a timestamp'
);
select throws_ok(
  $$
    delete from auth.users
    where id = '40000000-0000-4000-8000-000000000001';
  $$,
  '23503', null,
  'Auth deletion cannot bypass an Admin membership'
);

select * from finish();
rollback;
