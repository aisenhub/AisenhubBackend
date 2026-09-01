begin;

select plan(23);

select has_function(
  'public',
  'admin_query_catalog_resource',
  array['uuid', 'text', 'text', 'integer', 'text', 'text', 'text', 'text'],
  'Admin Catalog resource query projection exists'
);
select has_function('public', 'admin_product_overview', array['uuid', 'uuid'], 'Product overview projection exists');
select ok(
  (select prosecdef from pg_proc where oid = 'public.admin_query_catalog_resource(uuid,text,text,integer,text,text,text,text)'::regprocedure),
  'Admin Catalog projection is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']::text[] from pg_proc where oid = 'public.admin_product_overview(uuid,uuid)'::regprocedure),
  'Product overview fixes its search_path'
);
select ok(
  has_function_privilege('service_role', 'public.admin_query_catalog_resource(uuid,text,text,integer,text,text,text,text)', 'EXECUTE'),
  'service_role can invoke Catalog projections'
);
select ok(
  not has_function_privilege('anon', 'public.admin_product_overview(uuid,uuid)', 'EXECUTE'),
  'anon cannot invoke Product overview'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '92000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'admin-catalog-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.admin_members (user_id, role) values ('92000000-0000-4000-8000-000000000001', 'owner');
  $$,
  'Catalog query owner fixture can be created'
);

set local role postgres;
select lives_ok(
  $$
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, status, starts_at, source, created_by)
    values
      ('92000000-0000-4000-8000-000000000010', 'Catalog Query Batch', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'AH-QUERY', 1, 1, 'draft', now(), 'test', '92000000-0000-4000-8000-000000000001');
    insert into platform.redemption_codes
      (id, batch_id, code_hash, code_hint, pepper_version, status)
    values
      ('92000000-0000-4000-8000-000000000011', '92000000-0000-4000-8000-000000000010', repeat('e', 64), 'AH-QUERY-****-0001', 1, 'issued');
  $$,
  'Catalog query redemption fixtures can be created'
);

set local role service_role;
select is(
  public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'origins', null, 10, 'localhost', null, 'origin', 'asc')->'items'->0->>'appSlug',
  'account',
  'owner can read exact Origin projections'
);
select is(
  public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'features', null, 10, 'aisenlens.app.access', 'active', 'code', 'asc')->'items'->0->>'valueType',
  'boolean',
  'feature projection returns typed metadata'
);
select is(
  public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'product-versions', null, 10, 'AISENLENS_LIFETIME', 'draft', 'version', 'desc')->'items'->0->>'productSku',
  'AISENLENS_LIFETIME',
  'product version projection resolves its product'
);
select is(
  public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'prices', null, 10, 'AISENLENS_LIFETIME', 'draft', 'createdAt', 'desc')->'items'->0->>'currency',
  'USD',
  'price projection exposes currency without payment secrets'
);
select is(
  public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'redemption-batches', null, 10, 'Catalog Query', 'draft', 'name', 'asc')->'items'->0->>'productSku',
  'AISENLENS_LIFETIME',
  'batch projection resolves product identity'
);
select is(
  public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'redemption-codes', null, 10, 'AH-QUERY', 'issued', 'createdAt', 'asc')->'items'->0->>'codeHint',
  'AH-QUERY-****-0001',
  'code projection returns only a safe hint'
);
select ok(
  not (public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'redemption-codes', null, 10, null, null, 'createdAt', 'asc')->'items'->0 ? 'codeHash'),
  'code projection excludes plaintext and hash fields'
);
select is(
  public.admin_product_overview('92000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001')->'product'->>'sku',
  'AISENLENS_LIFETIME',
  'Product overview resolves the product'
);
select is(jsonb_array_length(public.admin_product_overview('92000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001')->'versions'), 1, 'Product overview includes versions');
select is(jsonb_array_length(public.admin_product_overview('92000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001')->'prices'), 1, 'Product overview includes prices');
select is(jsonb_array_length(public.admin_product_overview('92000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001')->'featureSnapshots'), 2, 'Product overview includes feature snapshots');
select is(jsonb_array_length(public.admin_product_overview('92000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001')->'redemptionBatches'), 1, 'Product overview includes redemption batches');
select public.admin_catalog_resource_detail('92000000-0000-4000-8000-000000000001', 'origins', '21000000-0000-4000-8000-000000000001')->>'origin' = 'http://localhost:5173' as "Origin detail returns explicit origin";
select public.admin_catalog_resource_detail('92000000-0000-4000-8000-000000000001', 'redemption-codes', '92000000-0000-4000-8000-000000000011') ? 'codeHint' as "Code detail returns hint";
select not (public.admin_catalog_resource_detail('92000000-0000-4000-8000-000000000001', 'redemption-codes', '92000000-0000-4000-8000-000000000011') ? 'codeHash') as "Code detail excludes hash";
select has_function('public', 'admin_catalog_resource_detail', array['uuid', 'text', 'uuid'], 'Catalog detail function exists');
select throws_ok(
  $$ select public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'products;drop', null, 10, null, null, 'createdAt', 'desc'); $$,
  '22023', null,
  'unknown Catalog resources are rejected'
);
select throws_ok(
  $$ select public.admin_query_catalog_resource('92000000-0000-4000-8000-000000000001', 'prices', null, 10, null, null, 'amountSql', 'desc'); $$,
  '22023', null,
  'unknown Catalog sort fields are rejected'
);

set local role postgres;
select * from finish();
rollback;
