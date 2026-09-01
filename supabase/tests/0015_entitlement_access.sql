begin;

select plan(31);

select has_function(
  'public',
  'check_access',
  ARRAY['uuid', 'text', 'text'],
  'server-side checkAccess entry exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.check_access(uuid,text,text)'::regprocedure),
  'checkAccess is SECURITY DEFINER'
);
select ok(
  (select provolatile = 'v' from pg_proc where oid = 'public.check_access(uuid,text,text)'::regprocedure),
  'checkAccess remains volatile because each decision receives a fresh ID'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']::text[]
   from pg_proc
   where oid = 'public.check_access(uuid,text,text)'::regprocedure),
  'checkAccess fixes its search_path'
);
select ok(
  not has_function_privilege('anon', 'public.check_access(uuid,text,text)', 'EXECUTE'),
  'anon cannot invoke checkAccess directly'
);
select ok(
  not has_function_privilege('authenticated', 'public.check_access(uuid,text,text)', 'EXECUTE'),
  'authenticated cannot invoke checkAccess directly'
);
select ok(
  has_function_privilege('service_role', 'public.check_access(uuid,text,text)', 'EXECUTE'),
  'service_role can invoke checkAccess through the server API'
);
select ok(
  not has_table_privilege('service_role', 'platform.entitlement_grants', 'SELECT'),
  'service_role cannot bypass the access resolver to read grants'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('51000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'access-user.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('51000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'access-empty.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('51000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
       'access-retired.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);

    insert into platform.features
      (id, app_id, code, name, value_type, merge_strategy)
    values
      ('55000000-0000-4000-8000-000000000001', null, 'test.access.sum', 'Test access sum', 'integer', 'sum'),
      ('55000000-0000-4000-8000-000000000002', null, 'test.access.max', 'Test access max', 'integer', 'max'),
      ('55000000-0000-4000-8000-000000000003', null, 'test.access.min', 'Test access min', 'integer', 'min'),
      ('55000000-0000-4000-8000-000000000004', null, 'test.access.latest', 'Test access latest', 'integer', 'latest'),
      ('55000000-0000-4000-8000-000000000005', null, 'test.access.label', 'Test access label', 'string', 'latest'),
      ('55000000-0000-4000-8000-000000000006', null, 'test.access.payload', 'Test access payload', 'json', 'latest');

    insert into platform.products (id, sku, name, billing_type)
    values
      ('52000000-0000-4000-8000-000000000001', 'ACCESS_SUM_A', 'Access Sum A', 'one_time'),
      ('52000000-0000-4000-8000-000000000002', 'ACCESS_SUM_B', 'Access Sum B', 'one_time'),
      ('52000000-0000-4000-8000-000000000003', 'ACCESS_SUM_C', 'Access Sum C', 'one_time'),
      ('52000000-0000-4000-8000-000000000004', 'ACCESS_MAX_A', 'Access Max A', 'one_time'),
      ('52000000-0000-4000-8000-000000000005', 'ACCESS_MAX_B', 'Access Max B', 'one_time'),
      ('52000000-0000-4000-8000-000000000006', 'ACCESS_MIN_A', 'Access Min A', 'one_time'),
      ('52000000-0000-4000-8000-000000000007', 'ACCESS_MIN_B', 'Access Min B', 'one_time'),
      ('52000000-0000-4000-8000-000000000008', 'ACCESS_LATEST_A', 'Access Latest A', 'one_time'),
      ('52000000-0000-4000-8000-000000000009', 'ACCESS_LATEST_B', 'Access Latest B', 'one_time'),
      ('52000000-0000-4000-8000-000000000010', 'ACCESS_LABEL_OLD', 'Access Label Old', 'one_time'),
      ('52000000-0000-4000-8000-000000000011', 'ACCESS_LABEL_NEW', 'Access Label New', 'one_time'),
      ('52000000-0000-4000-8000-000000000012', 'ACCESS_PAYLOAD_OLD', 'Access Payload Old', 'one_time'),
      ('52000000-0000-4000-8000-000000000013', 'ACCESS_PAYLOAD_NEW', 'Access Payload New', 'one_time'),
      ('52000000-0000-4000-8000-000000000014', 'ACCESS_RETIRED', 'Access Retired', 'one_time'),
      ('52000000-0000-4000-8000-000000000015', 'ACCESS_DIRECT', 'Access Direct', 'one_time'),
      ('52000000-0000-4000-8000-000000000016', 'ACCESS_ALL_APPS', 'Access All Apps', 'one_time');

    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values
      ('53000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000002', '52000000-0000-4000-8000-000000000002', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000003', '52000000-0000-4000-8000-000000000003', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000004', '52000000-0000-4000-8000-000000000004', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000005', '52000000-0000-4000-8000-000000000005', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000006', '52000000-0000-4000-8000-000000000006', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000007', '52000000-0000-4000-8000-000000000007', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000008', '52000000-0000-4000-8000-000000000008', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000009', '52000000-0000-4000-8000-000000000009', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000010', '52000000-0000-4000-8000-000000000010', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000011', '52000000-0000-4000-8000-000000000011', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000012', '52000000-0000-4000-8000-000000000012', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000013', '52000000-0000-4000-8000-000000000013', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000014', '52000000-0000-4000-8000-000000000014', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000015', '52000000-0000-4000-8000-000000000014', 2, 'retired', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000016', '52000000-0000-4000-8000-000000000015', 1, 'published', now(), '{}'::jsonb),
      ('53000000-0000-4000-8000-000000000017', '52000000-0000-4000-8000-000000000016', 1, 'published', now(), '{}'::jsonb);

    select set_config('app.catalog_command', 'set_current', true);
    update platform.products
    set status = 'active', current_version_id = '53000000-0000-4000-8000-000000000014'
    where id = '52000000-0000-4000-8000-000000000014';
    select set_config('app.catalog_command', '', true);
  $$,
  'access resolver fixtures can be created'
);

select lives_ok(
  $$
    insert into platform.product_version_features (product_version_id, feature_id, value)
    values
      ('53000000-0000-4000-8000-000000000001', '55000000-0000-4000-8000-000000000001', '2'::jsonb),
      ('53000000-0000-4000-8000-000000000002', '55000000-0000-4000-8000-000000000001', '3'::jsonb),
      ('53000000-0000-4000-8000-000000000003', '55000000-0000-4000-8000-000000000001', '5'::jsonb),
      ('53000000-0000-4000-8000-000000000004', '55000000-0000-4000-8000-000000000002', '2'::jsonb),
      ('53000000-0000-4000-8000-000000000005', '55000000-0000-4000-8000-000000000002', '9'::jsonb),
      ('53000000-0000-4000-8000-000000000006', '55000000-0000-4000-8000-000000000003', '7'::jsonb),
      ('53000000-0000-4000-8000-000000000007', '55000000-0000-4000-8000-000000000003', '3'::jsonb),
      ('53000000-0000-4000-8000-000000000008', '55000000-0000-4000-8000-000000000004', '3'::jsonb),
      ('53000000-0000-4000-8000-000000000009', '55000000-0000-4000-8000-000000000004', '9'::jsonb),
      ('53000000-0000-4000-8000-000000000010', '55000000-0000-4000-8000-000000000005', '"old"'::jsonb),
      ('53000000-0000-4000-8000-000000000011', '55000000-0000-4000-8000-000000000005', '"new"'::jsonb),
      ('53000000-0000-4000-8000-000000000012', '55000000-0000-4000-8000-000000000006', '{"tier":"old"}'::jsonb),
      ('53000000-0000-4000-8000-000000000013', '55000000-0000-4000-8000-000000000006', '{"tier":"new"}'::jsonb),
      ('53000000-0000-4000-8000-000000000014', '22000000-0000-4000-8000-000000000001', 'true'::jsonb),
      ('53000000-0000-4000-8000-000000000015', '22000000-0000-4000-8000-000000000001', 'true'::jsonb),
      ('53000000-0000-4000-8000-000000000016', '22000000-0000-4000-8000-000000000001', 'false'::jsonb),
      ('53000000-0000-4000-8000-000000000017', '22000000-0000-4000-8000-000000000004', 'true'::jsonb);
  $$,
  'access resolver snapshots can be created'
);

select lives_ok(
  $$
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id, expires_at, created_at)
    values
      ('54000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000001', '53000000-0000-4000-8000-000000000001', 'admin', '56000000-0000-4000-8000-000000000001', now() + interval '30 days', now()),
      ('54000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000002', '53000000-0000-4000-8000-000000000002', 'admin', '56000000-0000-4000-8000-000000000002', null, now()),
      ('54000000-0000-4000-8000-000000000003', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000003', '53000000-0000-4000-8000-000000000003', 'admin', '56000000-0000-4000-8000-000000000003', null, now()),
      ('54000000-0000-4000-8000-000000000004', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000004', '53000000-0000-4000-8000-000000000004', 'admin', '56000000-0000-4000-8000-000000000004', null, now()),
      ('54000000-0000-4000-8000-000000000005', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000005', '53000000-0000-4000-8000-000000000005', 'admin', '56000000-0000-4000-8000-000000000005', null, now()),
      ('54000000-0000-4000-8000-000000000006', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000006', '53000000-0000-4000-8000-000000000006', 'admin', '56000000-0000-4000-8000-000000000006', null, now()),
      ('54000000-0000-4000-8000-000000000007', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000007', '53000000-0000-4000-8000-000000000007', 'admin', '56000000-0000-4000-8000-000000000007', null, now()),
      ('54000000-0000-4000-8000-000000000008', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000008', '53000000-0000-4000-8000-000000000008', 'admin', '56000000-0000-4000-8000-000000000008', null, timestamp '2026-01-01 00:00:00'),
      ('54000000-0000-4000-8000-000000000009', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000009', '53000000-0000-4000-8000-000000000009', 'admin', '56000000-0000-4000-8000-000000000009', null, timestamp '2026-01-01 00:00:00'),
      ('54000000-0000-4000-8000-000000000010', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000010', '53000000-0000-4000-8000-000000000010', 'admin', '56000000-0000-4000-8000-000000000010', null, now()),
      ('54000000-0000-4000-8000-000000000011', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000011', '53000000-0000-4000-8000-000000000011', 'admin', '56000000-0000-4000-8000-000000000011', null, now()),
      ('54000000-0000-4000-8000-000000000012', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000012', '53000000-0000-4000-8000-000000000012', 'admin', '56000000-0000-4000-8000-000000000012', null, now()),
      ('54000000-0000-4000-8000-000000000013', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000013', '53000000-0000-4000-8000-000000000013', 'admin', '56000000-0000-4000-8000-000000000013', null, now()),
      ('54000000-0000-4000-8000-000000000014', '51000000-0000-4000-8000-000000000003', '52000000-0000-4000-8000-000000000014', '53000000-0000-4000-8000-000000000015', 'admin', '56000000-0000-4000-8000-000000000014', null, now()),
      ('54000000-0000-4000-8000-000000000015', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000015', '53000000-0000-4000-8000-000000000016', 'admin', '56000000-0000-4000-8000-000000000015', null, now()),
      ('54000000-0000-4000-8000-000000000018', '51000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000016', '53000000-0000-4000-8000-000000000017', 'admin', '56000000-0000-4000-8000-000000000018', null, now()),
      ('54000000-0000-4000-8000-000000000017', '51000000-0000-4000-8000-000000000002', '52000000-0000-4000-8000-000000000002', '53000000-0000-4000-8000-000000000002', 'admin', '56000000-0000-4000-8000-000000000017', null, now());

    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id, starts_at, expires_at)
    values
      ('54000000-0000-4000-8000-000000000016', '51000000-0000-4000-8000-000000000002', '52000000-0000-4000-8000-000000000001', '53000000-0000-4000-8000-000000000001', 'admin', '56000000-0000-4000-8000-000000000016', now() - interval '2 days', now() - interval '1 day');

    update platform.entitlement_grants
    set status = 'revoked', revoked_at = now(), revoke_reason = 'access test revoke'
    where id = '54000000-0000-4000-8000-000000000017';
  $$,
  'active, historical, expired, and revoked grant fixtures can be created'
);

set local role service_role;
select is(
  (select allowed from public.check_access('51000000-0000-4000-8000-000000000002', 'aisenlens', 'test.access.sum')),
  false,
  'no active nonexpired grant denies access'
);
select is(
  (select allowed from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'aisenlens.app.access')),
  true,
  'direct boolean feature grant allows access'
);
select is(
  (select value from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'aisenlens.app.access')),
  'true'::jsonb,
  'boolean any_true resolves to true'
);
select is(
  (select source_product from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'aisenlens.app.access')),
  'ACCESS_ALL_APPS,ACCESS_DIRECT',
  'all-apps and direct grants are reported in deterministic SKU order'
);
select is(
  (select allowed from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.sum')),
  true,
  'integer sum feature allows access'
);
select is(
  (select value from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.sum')),
  '10'::jsonb,
  'integer sum merges all active grants'
);
select is(
  (select source_product from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.sum')),
  'ACCESS_SUM_A,ACCESS_SUM_B,ACCESS_SUM_C',
  'integer sum reports all source products deterministically'
);
select ok(
  (select expires_at > now() + interval '29 days' from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.sum')),
  'access reports the earliest finite expiry'
);
select is(
  (select value from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.max')),
  '9'::jsonb,
  'integer max resolves the maximum value'
);
select is(
  (select value from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.min')),
  '3'::jsonb,
  'integer min resolves the minimum value'
);
select is(
  (select value from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.latest')),
  '9'::jsonb,
  'latest integer uses created_at then grant_id descending'
);
select is(
  (select value from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.label')),
  '"new"'::jsonb,
  'latest string returns the newest snapshot'
);
select is(
  (select value from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'test.access.payload')),
  '{"tier":"new"}'::jsonb,
  'latest JSON returns the newest snapshot'
);
select is(
  (select allowed from public.check_access('51000000-0000-4000-8000-000000000003', 'aisenlens', 'aisenlens.app.access')),
  true,
  'retired historical snapshots continue to resolve'
);
select is(
  (select source_product from public.check_access('51000000-0000-4000-8000-000000000003', 'aisenlens', 'aisenlens.app.access')),
  'ACCESS_RETIRED',
  'historical access resolves from its fixed product version'
);
select is(
  (select allowed from public.check_access('51000000-0000-4000-8000-000000000001', 'aisenlens', 'unknown.feature')),
  false,
  'unknown features deny access'
);
select is(
  (select allowed from public.check_access('51000000-0000-4000-8000-000000000001', 'missing-app', 'test.access.sum')),
  false,
  'unknown applications deny access'
);
select is(
  (select allowed from public.check_access(null, 'aisenlens', 'test.access.sum')),
  false,
  'null users deny access'
);
set local role postgres;
select lives_ok(
  $$
    insert into platform.platform_apps (id, slug, name, category, status, primary_feature_id)
    values ('57000000-0000-4000-8000-000000000001', 'inactive-access-test', 'Inactive Access Test', 'tool', 'suspended', '22000000-0000-4000-8000-000000000004');
  $$,
  'inactive app fixture can be created'
);
set local role service_role;
select is(
  (select allowed from public.check_access('51000000-0000-4000-8000-000000000001', 'inactive-access-test', 'hub.all_apps_access')),
  false,
  'inactive applications deny even with an all-apps grant'
);
select * from finish();
rollback;
