begin;

select plan(30);

select has_table('platform', 'product_version_features', 'product version feature snapshots exist');
select has_table('platform', 'product_prices', 'product prices exist');
select has_index(
  'platform',
  'product_version_features',
  'product_version_features_pkey',
  'version feature snapshots use a composite primary key'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.product_version_features'::regclass),
  'version feature snapshots have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.product_prices'::regclass),
  'product prices have RLS enabled'
);
select ok(
  not has_table_privilege('anon', 'platform.product_version_features', 'SELECT'),
  'anon cannot read version feature snapshots directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.product_prices', 'SELECT'),
  'authenticated cannot read product prices directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.product_prices', 'INSERT'),
  'service_role cannot insert product prices directly'
);
select ok(
  (select count(*) from platform.product_version_features) = 2,
  'AisenLens draft version has two deterministic feature snapshots'
);
select ok(
  exists (
    select 1
    from platform.product_prices
    where id = '27000000-0000-4000-8000-000000000001'
      and currency = 'USD'
      and status = 'draft'
  ),
  'AisenLens draft price seed is deterministic'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'platform'
      and table_name = 'product_versions'
      and column_name in ('price', 'amount_minor', 'currency')
  ),
  'product versions do not store price fields'
);
select lives_ok(
  $$
    insert into platform.features (id, code, name, value_type, merge_strategy)
    values
      ('28000000-0000-4000-8000-000000000001', 'test.integer.limit', 'Integer limit', 'integer', 'max'),
      ('28000000-0000-4000-8000-000000000002', 'test.string.plan', 'String plan', 'string', 'latest');
  $$,
  'integer and string feature definitions can be created'
);
select lives_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000003', 'false'::jsonb);
  $$,
  'boolean feature values are validated and accepted'
);
select throws_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000003', '"not-a-boolean"'::jsonb);
  $$,
  '23514', null,
  'boolean feature values reject JSON strings'
);
select lives_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000001', '10'::jsonb);
  $$,
  'whole JSON numbers are accepted for integer features'
);
select throws_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000001', '1.5'::jsonb);
  $$,
  '23514', null,
  'integer feature values reject fractional numbers'
);
select lives_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000002', '"pro"'::jsonb);
  $$,
  'JSON strings are accepted for string features'
);
select throws_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000002', 'true'::jsonb);
  $$,
  '23514', null,
  'string feature values reject JSON booleans'
);
select throws_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'true'::jsonb);
  $$,
  '23505', null,
  'duplicate feature snapshots are rejected'
);
select throws_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('24000000-0000-4000-8000-000000000001', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'true'::jsonb);
  $$,
  '23503', null,
  'feature snapshots require an existing feature'
);
select lives_ok(
  $$
    insert into platform.products (id, sku, name, billing_type)
    values ('29000000-0000-4000-8000-000000000001', 'TEST_PRICE_PRODUCT', 'Price Test Product', 'one_time');
    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values
      ('2a000000-0000-4000-8000-000000000001', '29000000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb);
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('2a000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000001', '5'::jsonb);
  $$,
  'published versions can carry validated feature snapshots'
);
select throws_ok(
  $$
    insert into platform.product_prices
      (product_version_id, currency, amount_minor, channel)
    values ('2a000000-0000-4000-8000-000000000001', 'usd', 100, 'manual');
  $$,
  '23514', null,
  'currencies must use three uppercase letters'
);
select throws_ok(
  $$
    insert into platform.product_prices
      (product_version_id, currency, amount_minor, channel)
    values ('2a000000-0000-4000-8000-000000000001', 'USD', -1, 'manual');
  $$,
  '23514', null,
  'negative price amounts are rejected'
);
select throws_ok(
  $$
    insert into platform.product_prices
      (product_version_id, currency, amount_minor, channel)
    values ('2a000000-0000-4000-8000-000000000001', 'USD', 100, 'Stripe Checkout');
  $$,
  '23514', null,
  'price channels must use stable machine identifiers'
);
select throws_ok(
  $$
    insert into platform.product_prices
      (product_version_id, currency, amount_minor, channel, valid_from, valid_until)
    values ('2a000000-0000-4000-8000-000000000001', 'USD', 100, 'manual', now(), now() - interval '1 minute');
  $$,
  '23514', null,
  'price validity windows must move forward'
);
select throws_ok(
  $$
    insert into platform.product_prices
      (product_version_id, currency, amount_minor, channel, status)
    values ('24000000-0000-4000-8000-000000000001', 'USD', 100, 'manual', 'active');
  $$,
  '23514', null,
  'active prices require a published version'
);
select lives_ok(
  $$
    insert into platform.product_prices
      (id, product_version_id, currency, amount_minor, channel, external_price_id, status)
    values ('2b000000-0000-4000-8000-000000000001', '2a000000-0000-4000-8000-000000000001', 'USD', 100, 'manual', 'provider-price-1', 'active');
  $$,
  'active prices can reference published versions'
);
select throws_ok(
  $$
    insert into platform.product_prices
      (product_version_id, currency, amount_minor, channel, external_price_id)
    values ('2a000000-0000-4000-8000-000000000001', 'USD', 200, 'manual', 'provider-price-1');
  $$,
  '23505', null,
  'external price identifiers are unique within a channel'
);
select throws_ok(
  $$
    update platform.product_version_features
    set value = '99'::jsonb
    where product_version_id = '2a000000-0000-4000-8000-000000000001'
      and feature_id = '28000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'published feature snapshots are immutable'
);
select throws_ok(
  $$
    delete from platform.product_version_features
    where product_version_id = '2a000000-0000-4000-8000-000000000001'
      and feature_id = '28000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'published feature snapshots cannot be deleted'
);

select * from finish();
rollback;
