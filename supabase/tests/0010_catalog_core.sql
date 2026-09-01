begin;

select plan(38);

select has_table('platform', 'features', 'feature registry exists');
select has_table('platform', 'products', 'product registry exists');
select has_table('platform', 'product_versions', 'product version registry exists');
select col_is_pk('platform', 'features', 'id', 'feature id is the primary key');
select col_is_pk('platform', 'products', 'id', 'product id is the primary key');
select col_is_pk('platform', 'product_versions', 'id', 'product version id is the primary key');
select has_index(
  'platform',
  'product_versions',
  'product_versions_product_version_key',
  'product versions are unique per product'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.features'::regclass),
  'features have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.products'::regclass),
  'products have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.product_versions'::regclass),
  'product versions have RLS enabled'
);
select ok(
  not has_table_privilege('anon', 'platform.features', 'SELECT'),
  'anon cannot read features directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.products', 'SELECT'),
  'authenticated cannot read products directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.product_versions', 'INSERT'),
  'service_role cannot insert product versions directly'
);
select ok(
  exists (
    select 1
    from platform.features
    where id = '22000000-0000-4000-8000-000000000001'
      and code = 'aisenlens.app.access'
      and value_type = 'boolean'
      and merge_strategy = 'any_true'
  ),
  'AisenLens access feature seed is deterministic'
);
select ok(
  exists (
    select 1
    from platform.features
    where id = '22000000-0000-4000-8000-000000000004'
      and app_id is null
      and code = 'hub.all_apps_access'
  ),
  'platform-wide feature seed is deterministic'
);
select ok(
  exists (
    select 1
    from platform.products
    where id = '23000000-0000-4000-8000-000000000001'
      and sku = 'AISENLENS_LIFETIME'
      and status = 'draft'
      and current_version_id is null
  ),
  'AisenLens product seed is a draft without a current version'
);
select ok(
  exists (
    select 1
    from platform.product_versions
    where id = '24000000-0000-4000-8000-000000000001'
      and product_id = '23000000-0000-4000-8000-000000000001'
      and version = 1
      and status = 'draft'
  ),
  'AisenLens version one seed is deterministic'
);
select ok(
  (select primary_feature_id from platform.platform_apps where slug = 'aisenlens')
    = '22000000-0000-4000-8000-000000000001'::uuid,
  'AisenLens points to its primary feature'
);
select throws_ok(
  $$
    insert into platform.features (code, name, value_type, merge_strategy)
    values ('test.invalid.boolean', 'Invalid boolean', 'boolean', 'latest');
  $$,
  '23514', null,
  'boolean features require any_true merge strategy'
);
select throws_ok(
  $$
    insert into platform.features (code, name, value_type, merge_strategy)
    values ('test.invalid.string', 'Invalid string', 'string', 'max');
  $$,
  '23514', null,
  'string features require latest merge strategy'
);
select throws_ok(
  $$
    insert into platform.features (code, name, value_type, merge_strategy)
    values ('Test.Uppercase', 'Invalid code', 'boolean', 'any_true');
  $$,
  '23514', null,
  'feature codes must use lowercase machine identifiers'
);
select throws_ok(
  $$
    insert into platform.products (sku, name, billing_type)
    values ('TEST_INVALID', 'Invalid product', 'monthly');
  $$,
  '23514', null,
  'unknown product billing types are rejected'
);
select throws_ok(
  $$
    insert into platform.products (sku, name, billing_type)
    values ('test_invalid', 'Invalid product', 'one_time');
  $$,
  '23514', null,
  'product SKUs must use uppercase machine identifiers'
);
select throws_ok(
  $$
    insert into platform.product_versions (product_id, version, sales_terms)
    values ('23000000-0000-4000-8000-000000000001', 0, '{}'::jsonb);
  $$,
  '23514', null,
  'product versions must use positive version numbers'
);
select throws_ok(
  $$
    insert into platform.product_versions (product_id, version, access_duration_days, sales_terms)
    values ('23000000-0000-4000-8000-000000000001', 2, 0, '{}'::jsonb);
  $$,
  '23514', null,
  'access duration must be positive when present'
);
select throws_ok(
  $$
    insert into platform.product_versions (product_id, version, sales_terms)
    values ('23000000-0000-4000-8000-000000000001', 2, '[]'::jsonb);
  $$,
  '23514', null,
  'sales terms must be a JSON object'
);
select throws_ok(
  $$
    insert into platform.products (sku, name, billing_type, status)
    values ('TEST_ACTIVE_WITHOUT_VERSION', 'Invalid active product', 'one_time', 'active');
  $$,
  '23514', null,
  'active products require a current version'
);
select lives_ok(
  $$
    insert into platform.products (id, sku, name, billing_type)
    values ('25000000-0000-4000-8000-000000000001', 'TEST_CATALOG_A', 'Catalog Test A', 'one_time');
    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values
      ('26000000-0000-4000-8000-000000000001', '25000000-0000-4000-8000-000000000001', 1, 'published', now(), '{"commitment":"test"}'::jsonb);
  $$,
  'a product and published version can be created'
);
select lives_ok(
  $$
    update platform.products
    set current_version_id = '26000000-0000-4000-8000-000000000001'
    where id = '25000000-0000-4000-8000-000000000001';
    update platform.products
    set status = 'active'
    where id = '25000000-0000-4000-8000-000000000001';
  $$,
  'current version must belong to the product and be published'
);
select lives_ok(
  $$
    insert into platform.products (id, sku, name, billing_type)
    values ('25000000-0000-4000-8000-000000000002', 'TEST_CATALOG_B', 'Catalog Test B', 'one_time');
    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values
      ('26000000-0000-4000-8000-000000000002', '25000000-0000-4000-8000-000000000002', 1, 'published', now(), '{}'::jsonb);
  $$,
  'a second product can have its own published version'
);
select throws_ok(
  $$
    update platform.products
    set current_version_id = '26000000-0000-4000-8000-000000000002'
    where id = '25000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'cross-product current versions are rejected'
);
select lives_ok(
  $$
    insert into platform.product_versions
      (id, product_id, version, status, sales_terms)
    values
      ('26000000-0000-4000-8000-000000000003', '25000000-0000-4000-8000-000000000001', 2, 'draft', '{}'::jsonb);
  $$,
  'draft versions can be prepared for a later controlled publication'
);
select throws_ok(
  $$
    update platform.products
    set current_version_id = '26000000-0000-4000-8000-000000000003'
    where id = '25000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'draft versions cannot become current'
);
select throws_ok(
  $$
    update platform.product_versions
    set sales_terms = '{"changed":true}'::jsonb
    where id = '26000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'published product versions are immutable'
);
select throws_ok(
  $$
    delete from platform.product_versions
    where id = '26000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'published product versions cannot be deleted'
);
select throws_ok(
  $$
    update platform.product_versions
    set status = 'retired'
    where id = '26000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'published version state changes require a controlled command'
);
select throws_ok(
  $$
    insert into platform.product_versions
      (product_id, version, status, published_at, sales_terms)
    values
      ('25000000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb);
  $$,
  '23505', null,
  'product version numbers are unique per product'
);
select throws_ok(
  $$
    insert into platform.features (app_id, code, name, value_type, merge_strategy)
    values ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'test.missing.app', 'Missing app', 'boolean', 'any_true');
  $$,
  '23503', null,
  'feature application references must exist'
);

select * from finish();
rollback;
