begin;

select plan(33);

select has_table('platform', 'entitlement_grants', 'entitlement grant history exists');
select col_is_pk('platform', 'entitlement_grants', 'id', 'grant id is the primary key');
select has_index(
  'platform',
  'entitlement_grants',
  'entitlement_grants_source_key',
  'grant sources are unique'
);
select has_index(
  'platform',
  'entitlement_grants',
  'entitlement_grants_user_status_expiry_idx',
  'user status and expiry lookup exists'
);
select has_index(
  'platform',
  'entitlement_grants',
  'entitlement_grants_product_status_idx',
  'product status lookup exists'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.entitlement_grants'::regclass),
  'entitlement grants have RLS enabled'
);
select ok(
  not has_table_privilege('anon', 'platform.entitlement_grants', 'SELECT'),
  'anon cannot read entitlement grants directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.entitlement_grants', 'SELECT'),
  'authenticated cannot read entitlement grants directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.entitlement_grants', 'INSERT'),
  'service_role cannot insert entitlement grants directly'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'platform'
      and table_name = 'entitlement_grants'
      and column_name in ('is_pro', 'balance', 'usage', 'credits')
  ),
  'entitlement grants do not contain role, balance, or usage fields'
);
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('33000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'grant-user.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('33000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'grant-other.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);
  $$,
  'grant test users can be created'
);
select lives_ok(
  $$
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id)
    values
      ('34000000-0000-4000-8000-000000000001',
       '33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'admin', '35000000-0000-4000-8000-000000000001');
  $$,
  'an active snapshot grant can be stored'
);
select lives_ok(
  $$
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id)
    values
      ('34000000-0000-4000-8000-000000000005',
       '33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'order_item', '35000000-0000-4000-8000-000000000005');
  $$,
  'order item sources remain available for later Commerce validation'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'admin', '35000000-0000-4000-8000-000000000001');
  $$,
  '23505', null,
  'the same source cannot grant twice'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, resolution_mode, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'rolling', 'admin', '35000000-0000-4000-8000-000000000006');
  $$,
  '23514', null,
  'only snapshot resolution is accepted'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'role', '35000000-0000-4000-8000-000000000007');
  $$,
  '23514', null,
  'unknown grant source types are rejected'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, status, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'pending', 'admin', '35000000-0000-4000-8000-000000000008');
  $$,
  '23514', null,
  'unknown grant statuses are rejected'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, starts_at, expires_at, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       now(), now() - interval '1 minute', 'admin', '35000000-0000-4000-8000-000000000009');
  $$,
  '23514', null,
  'grant expiry must be after its start'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, revoked_at, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       now(), 'admin', '35000000-0000-4000-8000-000000000010');
  $$,
  '23514', null,
  'active grants cannot carry revocation fields'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, status, revoked_at, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'revoked', now(), 'admin', '35000000-0000-4000-8000-000000000011');
  $$,
  '23514', null,
  'revoked grants require a nonblank reason'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'admin_restore', '35000000-0000-4000-8000-000000000012');
  $$,
  '23514', null,
  'admin restores require an original grant link'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, source_type, source_id, restores_grant_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'admin', '35000000-0000-4000-8000-000000000013',
       '34000000-0000-4000-8000-000000000001');
  $$,
  '23514', null,
  'non-restore grants cannot carry restore links'
);
select lives_ok(
  $$
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id, status, revoked_at, revoke_reason)
    values
      ('34000000-0000-4000-8000-000000000002',
       '33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'redemption', '35000000-0000-4000-8000-000000000002',
       'revoked', now(), 'test correction');
  $$,
  'a revoked original grant can be retained'
);
select lives_ok(
  $$
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id, restores_grant_id)
    values
      ('34000000-0000-4000-8000-000000000003',
       '33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'admin_restore', '35000000-0000-4000-8000-000000000003',
       '34000000-0000-4000-8000-000000000002');
  $$,
  'a restore grant links to a matching revoked original'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, source_type, source_id, restores_grant_id)
    values
      ('33000000-0000-4000-8000-000000000002',
       '23000000-0000-4000-8000-000000000001',
       '24000000-0000-4000-8000-000000000001',
       'admin_restore', '35000000-0000-4000-8000-000000000014',
       '34000000-0000-4000-8000-000000000002');
  $$,
  '23514', null,
  'restore grants must match the original user and product snapshot'
);
select throws_ok(
  $$
    delete from platform.entitlement_grants
    where id = '34000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'entitlement grant history cannot be deleted'
);
select lives_ok(
  $$
    update platform.entitlement_grants
    set status = 'revoked', revoked_at = now(), revoke_reason = 'test revoke'
    where id = '34000000-0000-4000-8000-000000000001';
  $$,
  'active grants can transition to revoked exactly once'
);
select throws_ok(
  $$
    update platform.entitlement_grants
    set status = 'active', revoked_at = null, revoke_reason = null
    where id = '34000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'revoked grants cannot be revived'
);
select throws_ok(
  $$
    update platform.entitlement_grants
    set revoke_reason = 'changed reason'
    where id = '34000000-0000-4000-8000-000000000002';
  $$,
  '23514', null,
  'revoked grant history cannot be edited'
);
select throws_ok(
  $$
    update platform.entitlement_grants
    set starts_at = starts_at + interval '1 minute'
    where id = '34000000-0000-4000-8000-000000000005';
  $$,
  '23514', null,
  'grant terms and identity are immutable'
);
select lives_ok(
  $$
    insert into platform.products (id, sku, name, billing_type)
    values ('36000000-0000-4000-8000-000000000001', 'TEST_GRANT_PRODUCT', 'Grant Test Product', 'one_time');
    insert into platform.product_versions
      (id, product_id, version, status, sales_terms)
    values ('37000000-0000-4000-8000-000000000001', '36000000-0000-4000-8000-000000000001', 1, 'draft', '{}'::jsonb);
  $$,
  'a separate product/version exists for ownership validation'
);
select throws_ok(
  $$
    insert into platform.entitlement_grants
      (user_id, product_id, product_version_id, source_type, source_id)
    values
      ('33000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001',
       '37000000-0000-4000-8000-000000000001',
       'admin', '35000000-0000-4000-8000-000000000015');
  $$,
  '23503', null,
  'grant product and version ownership must match'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'platform.entitlement_grants'::regclass
      and conname = 'entitlement_grants_restore_not_self_check'
  ),
  'restore self-link constraint exists'
);

select * from finish();
rollback;
