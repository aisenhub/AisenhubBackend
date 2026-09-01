begin;

select plan(37);

select has_function('public', 'publish_product_version', ARRAY['uuid'], 'publish command exists');
select has_function('public', 'retire_product_version', ARRAY['uuid'], 'retire command exists');
select has_function('public', 'set_current_product_version', ARRAY['uuid', 'uuid'], 'set-current command exists');
select ok(
  (select prosecdef from pg_proc where oid = 'public.publish_product_version(uuid)'::regprocedure),
  'publish command is SECURITY DEFINER'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.retire_product_version(uuid)'::regprocedure),
  'retire command is SECURITY DEFINER'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.set_current_product_version(uuid,uuid)'::regprocedure),
  'set-current command is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']
   from pg_proc
   where oid = 'public.publish_product_version(uuid)'::regprocedure),
  'publish command fixes its search_path'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']
   from pg_proc
   where oid = 'public.retire_product_version(uuid)'::regprocedure),
  'retire command fixes its search_path'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']
   from pg_proc
   where oid = 'public.set_current_product_version(uuid,uuid)'::regprocedure),
  'set-current command fixes its search_path'
);
select ok(
  not has_function_privilege('anon', 'public.publish_product_version(uuid)', 'EXECUTE'),
  'anon cannot invoke publish command'
);
select ok(
  not has_function_privilege('authenticated', 'public.retire_product_version(uuid)', 'EXECUTE'),
  'authenticated cannot invoke retire command directly'
);
select ok(
  has_function_privilege('service_role', 'public.set_current_product_version(uuid,uuid)', 'EXECUTE'),
  'service_role can invoke the backend set-current command'
);
select lives_ok(
  $$
    insert into platform.products
      (id, sku, name, billing_type)
    values
      ('30000000-0000-4000-8000-000000000001', 'TEST_COMMAND_PRODUCT', 'Command Test Product', 'one_time');
    insert into platform.product_versions
      (id, product_id, version, status, sales_terms)
    values
      ('31000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 1, 'draft', '{}'::jsonb);
  $$,
  'an incomplete draft is available for command tests'
);
select throws_ok(
  $$ select * from public.publish_product_version('31000000-0000-4000-8000-000000000001'); $$,
  '23514', null,
  'publication requires a feature snapshot'
);
select ok(
  (select status = 'draft'
   from platform.product_versions
   where id = '31000000-0000-4000-8000-000000000001'),
  'failed publication leaves the version in draft'
);
select lives_ok(
  $$
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('31000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'true'::jsonb);
  $$,
  'a valid feature snapshot can be added before publication'
);
select throws_ok(
  $$ select * from public.publish_product_version('31000000-0000-4000-8000-000000000001'); $$,
  '23514', null,
  'publication requires a price'
);
select lives_ok(
  $$
    insert into platform.product_prices
      (id, product_version_id, currency, amount_minor, channel, status)
    values
      ('32000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', 'USD', 100, 'manual', 'draft');
  $$,
  'a draft price can be prepared before publication'
);
select lives_ok(
  $$ select * from public.publish_product_version('31000000-0000-4000-8000-000000000001'); $$,
  'a complete draft version can be published'
);
select ok(
  (select status = 'published'
   from platform.product_versions
   where id = '31000000-0000-4000-8000-000000000001'),
  'publication changes the version status'
);
select ok(
  (select published_at is not null
   from platform.product_versions
   where id = '31000000-0000-4000-8000-000000000001'),
  'publication records a timestamp'
);
select lives_ok(
  $$
    update platform.product_prices
    set status = 'active'
    where id = '32000000-0000-4000-8000-000000000001';
  $$,
  'a price can be activated after publication'
);
select lives_ok(
  $$
    select * from public.set_current_product_version(
      '30000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001'
    );
  $$,
  'set-current accepts an owned published version with an active price'
);
select throws_ok(
  $$
    update platform.products
    set current_version_id = null
    where id = '30000000-0000-4000-8000-000000000001';
  $$,
  '42501', null,
  'direct current-version changes are rejected'
);
select lives_ok(
  $$
    insert into platform.product_versions
      (id, product_id, version, status, sales_terms)
    values
      ('31000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 2, 'draft', '{}'::jsonb);
  $$,
  'a second draft version can be prepared'
);
select throws_ok(
  $$
    update platform.product_versions
    set status = 'published', published_at = now()
    where id = '31000000-0000-4000-8000-000000000002';
  $$,
  '23514', null,
  'direct publication status changes are rejected'
);
select throws_ok(
  $$
    select * from public.set_current_product_version(
      '30000000-0000-4000-8000-000000000001',
      '24000000-0000-4000-8000-000000000001'
    );
  $$,
  '23514', null,
  'set-current rejects a version owned by another product'
);
select throws_ok(
  $$ select * from public.publish_product_version('31000000-0000-4000-8000-000000000001'); $$,
  '23514', null,
  'published versions cannot be published again'
);
select lives_ok(
  $$
    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values
      ('31000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', 3, 'published', now(), '{}'::jsonb);
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values
      ('31000000-0000-4000-8000-000000000003', '22000000-0000-4000-8000-000000000001', 'true'::jsonb);
    insert into platform.product_prices
      (id, product_version_id, currency, amount_minor, channel, status)
    values
      ('32000000-0000-4000-8000-000000000003', '31000000-0000-4000-8000-000000000003', 'USD', 200, 'manual', 'active');
  $$,
  'a second published version can be prepared for a current-version switch'
);
select lives_ok(
  $$
    select * from public.set_current_product_version(
      '30000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000003'
    );
  $$,
  'set-current switches to another published version atomically'
);
select lives_ok(
  $$
    update platform.products
    set status = 'active'
    where id = '30000000-0000-4000-8000-000000000001';
  $$,
  'a product can become active once it has a current version'
);
select throws_ok(
  $$ select * from public.retire_product_version('31000000-0000-4000-8000-000000000003'); $$,
  '23514', null,
  'the current version cannot be retired'
);
select lives_ok(
  $$ select * from public.retire_product_version('31000000-0000-4000-8000-000000000001'); $$,
  'a non-current published version can be retired'
);
select ok(
  (select status = 'retired'
   from platform.product_versions
   where id = '31000000-0000-4000-8000-000000000001'),
  'retirement changes the version status'
);
select ok(
  (select status = 'retired'
   from platform.product_prices
   where id = '32000000-0000-4000-8000-000000000001'),
  'retirement retires active prices atomically'
);
select throws_ok(
  $$ select * from public.retire_product_version('31000000-0000-4000-8000-000000000001'); $$,
  '23514', null,
  'retired versions cannot be retired again'
);
select throws_ok(
  $$ select * from public.set_current_product_version(
    '30000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  ); $$,
  '23514', null,
  'retired versions cannot become current'
);

select * from finish();
rollback;
