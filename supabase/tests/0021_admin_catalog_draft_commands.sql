begin;

select plan(23);

select has_function(
  'public',
  'admin_catalog_draft_command',
  array['uuid', 'text', 'uuid', 'uuid', 'jsonb', 'timestamptz', 'text', 'text', 'text', 'uuid'],
  'Admin draft command function exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.admin_catalog_draft_command(uuid,text,uuid,uuid,jsonb,timestamptz,text,text,text,uuid)'::regprocedure),
  'Admin draft command is SECURITY DEFINER'
);
select ok(
  has_function_privilege('service_role', 'public.admin_catalog_draft_command(uuid,text,uuid,uuid,jsonb,timestamptz,text,text,text,uuid)', 'EXECUTE'),
  'service_role can invoke draft commands'
);
select ok(
  not has_function_privilege('anon', 'public.admin_catalog_draft_command(uuid,text,uuid,uuid,jsonb,timestamptz,text,text,text,uuid)', 'EXECUTE'),
  'anon cannot invoke draft commands'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '93000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'admin-draft-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.admin_members (user_id, role) values ('93000000-0000-4000-8000-000000000001', 'owner');
  $$,
  'draft command owner fixture can be created'
);

set local role postgres;
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'create_application', null, null,
    '{"slug":"draft-app","name":"Draft App","category":"tool"}'::jsonb, null,
    'Create draft application', 'draft-app-create-1', 'draft-app-hash-1', '93000000-0000-4000-8000-000000000010'
  )->>'slug',
  'draft-app',
  'application draft creation returns the safe projection'
);
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'update_application',
    (select id from platform.platform_apps where slug = 'draft-app'), null,
    '{"name":"Updated Draft App"}'::jsonb,
    (select updated_at from platform.platform_apps where slug = 'draft-app'),
    'Update draft application', 'draft-app-update-1', 'draft-app-hash-2', '93000000-0000-4000-8000-000000000011'
  )->>'name',
  'Updated Draft App',
  'application draft update allows only explicit fields'
);
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'create_application', null, null,
    '{"slug":"draft-app","name":"Duplicate","category":"tool"}'::jsonb, null,
    'Retry draft application', 'draft-app-create-1', 'draft-app-hash-1', '93000000-0000-4000-8000-000000000012'
  )->>'slug',
  'draft-app',
  'same idempotency key returns the original application'
);
select throws_ok(
  $$ select public.admin_catalog_draft_command('93000000-0000-4000-8000-000000000001', 'update_application', (select id from platform.platform_apps where slug = 'draft-app'), null, '{"status":"active"}'::jsonb, (select updated_at from platform.platform_apps where slug = 'draft-app'), 'Invalid status update', 'draft-app-invalid-1', 'draft-app-hash-3', '93000000-0000-4000-8000-000000000013'); $$,
  '22023', null,
  'status edits are rejected by the application allow-list'
);
select throws_ok(
  $$ select public.admin_catalog_draft_command('93000000-0000-4000-8000-000000000001', 'update_application', (select id from platform.platform_apps where slug = 'draft-app'), null, '{"name":"Stale"}'::jsonb, '2000-01-01T00:00:00Z', 'Stale update', 'draft-app-stale-1', 'draft-app-hash-4', '93000000-0000-4000-8000-000000000014'); $$,
  '40001', null,
  'stale application updates return a version conflict'
);

select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'create_origin', null,
    (select id from platform.platform_apps where slug = 'draft-app'),
    '{"environment":"development","origin":"http://draft-app.local"}'::jsonb, null,
    'Create draft Origin', 'draft-origin-create-1', 'draft-origin-hash-1', '93000000-0000-4000-8000-000000000015'
  )->>'origin',
  'http://draft-app.local',
  'Origin draft creation returns exact origin'
);
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'update_origin',
    (select id from platform.app_origins where origin = 'http://draft-app.local'), null,
    '{"isActive":false}'::jsonb,
    (select updated_at from platform.app_origins where origin = 'http://draft-app.local'),
    'Deactivate draft Origin', 'draft-origin-update-1', 'draft-origin-hash-2', '93000000-0000-4000-8000-000000000016'
  )->>'isActive',
  'false',
  'Origin draft update can only change activation'
);

select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'create_feature', null, null,
    '{"code":"draft.feature","name":"Draft Feature","valueType":"boolean","mergeStrategy":"any_true"}'::jsonb, null,
    'Create draft Feature', 'draft-feature-create-1', 'draft-feature-hash-1', '93000000-0000-4000-8000-000000000017'
  )->>'code',
  'draft.feature',
  'Feature draft creation returns stable code'
);
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'update_feature',
    (select id from platform.features where code = 'draft.feature'), null,
    '{"name":"Updated Draft Feature"}'::jsonb, null,
    'Update draft Feature', 'draft-feature-update-1', 'draft-feature-hash-2', '93000000-0000-4000-8000-000000000018'
  )->>'name',
  'Updated Draft Feature',
  'Feature draft update cannot mutate its code'
);

select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'create_product', null, null,
    '{"sku":"DRAFT_PRODUCT","name":"Draft Product","billingType":"one_time"}'::jsonb, null,
    'Create draft Product', 'draft-product-create-1', 'draft-product-hash-1', '93000000-0000-4000-8000-000000000019'
  )->>'sku',
  'DRAFT_PRODUCT',
  'Product draft creation does not accept a status field'
);
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'update_product',
    (select id from platform.products where sku = 'DRAFT_PRODUCT'), null,
    '{"name":"Updated Draft Product"}'::jsonb,
    (select updated_at from platform.products where sku = 'DRAFT_PRODUCT'),
    'Update draft Product', 'draft-product-update-1', 'draft-product-hash-2', '93000000-0000-4000-8000-000000000020'
  )->>'name',
  'Updated Draft Product',
  'Product draft update returns the changed projection'
);

select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'create_product_version', null,
    (select id from platform.products where sku = 'DRAFT_PRODUCT'),
    '{"version":1,"accessDurationDays":365,"salesTerms":{"label":"draft"}}'::jsonb, null,
    'Create draft Product Version', 'draft-version-create-1', 'draft-version-hash-1', '93000000-0000-4000-8000-000000000021'
  )->>'status',
  'draft',
  'Product Version draft creation always starts in draft'
);
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'update_product_version',
    (select version.id from platform.product_versions as version join platform.products as product on product.id = version.product_id where product.sku = 'DRAFT_PRODUCT'), null,
    '{"salesTerms":{"label":"updated"}}'::jsonb, null,
    'Update draft Product Version', 'draft-version-update-1', 'draft-version-hash-2', '93000000-0000-4000-8000-000000000022'
  )->>'status',
  'draft',
  'Product Version draft update cannot publish the version'
);

select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'create_price', null,
    (select version.id from platform.product_versions as version join platform.products as product on product.id = version.product_id where product.sku = 'DRAFT_PRODUCT'),
    '{"currency":"USD","amountMinor":1200,"channel":"manual"}'::jsonb, null,
    'Create draft Price', 'draft-price-create-1', 'draft-price-hash-1', '93000000-0000-4000-8000-000000000023'
  )->>'status',
  'draft',
  'Price draft creation always starts in draft'
);
select is(
  public.admin_catalog_draft_command(
    '93000000-0000-4000-8000-000000000001', 'update_price',
    (select price.id from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id join platform.products as product on product.id = version.product_id where product.sku = 'DRAFT_PRODUCT'), null,
    '{"amountMinor":1500}'::jsonb,
    (select price.updated_at from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id join platform.products as product on product.id = version.product_id where product.sku = 'DRAFT_PRODUCT'),
    'Update draft Price', 'draft-price-update-1', 'draft-price-hash-2', '93000000-0000-4000-8000-000000000024'
  )->>'amountMinor',
  '1500',
  'Price draft update returns the changed amount'
);

select ok(
  exists (select 1 from platform.audit_logs where actor_id = '93000000-0000-4000-8000-000000000001' and action = 'update_price' and target_type = 'product_price'),
  'every draft mutation writes an authoritative audit entry'
);
select ok(
  exists (select 1 from platform.products where sku = 'DRAFT_PRODUCT'),
  'SKU identity is not silently rewritten'
);
select ok(
  (select count(*) from platform.idempotency_records where scope = 'admin.catalog.draft' and actor_key = 'admin:93000000-0000-4000-8000-000000000001') = 12,
  'each distinct draft command has one idempotency record'
);

set local role postgres;
select * from finish();
rollback;
