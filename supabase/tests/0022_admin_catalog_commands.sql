begin;

select plan(25);

select has_function(
  'public',
  'admin_catalog_command',
  array['uuid', 'text', 'uuid', 'jsonb', 'text', 'text', 'text', 'uuid'],
  'Admin Catalog command wrapper exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.admin_catalog_command(uuid,text,uuid,jsonb,text,text,text,uuid)'::regprocedure),
  'Admin Catalog command wrapper is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']::text[] from pg_proc where oid = 'public.admin_catalog_command(uuid,text,uuid,jsonb,text,text,text,uuid)'::regprocedure),
  'Admin Catalog command wrapper fixes its search_path'
);
select ok(
  has_function_privilege('service_role', 'public.admin_catalog_command(uuid,text,uuid,jsonb,text,text,text,uuid)', 'EXECUTE'),
  'service_role can invoke high-risk Catalog commands'
);
select ok(
  not has_function_privilege('anon', 'public.admin_catalog_command(uuid,text,uuid,jsonb,text,text,text,uuid)', 'EXECUTE'),
  'anon cannot invoke high-risk Catalog commands'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '93000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'catalog-command-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.admin_members (user_id, role) values ('93000000-0000-4000-8000-000000000001', 'owner');
  $$,
  'Catalog command owner fixture can be created'
);

set local role service_role;
select is(
  public.admin_catalog_command(
    '93000000-0000-4000-8000-000000000001', 'publish_product_version',
    '24000000-0000-4000-8000-000000000001', '{}'::jsonb, 'publish local catalog',
    'catalog-publish-1', repeat('a', 64), '93000000-0000-4000-8000-000000000101'
  )->>'status',
  'published',
  'publish command delegates to the domain state function'
);
set local role postgres;
select is(
  (select count(*)::integer from platform.audit_logs where request_id = '93000000-0000-4000-8000-000000000101'),
  1,
  'publish command writes one authoritative audit row'
);
set local role service_role;
select is(
  public.admin_catalog_command(
    '93000000-0000-4000-8000-000000000001', 'publish_product_version',
    '24000000-0000-4000-8000-000000000001', '{}'::jsonb, 'publish local catalog',
    'catalog-publish-1', repeat('a', 64), '93000000-0000-0000-0000-000000000102'
  )->>'status',
  'published',
  'same publish idempotency key returns the stored result'
);
set local role postgres;
select is(
  (select count(*)::integer from platform.idempotency_records
    where scope = 'admin.catalog.command' and idempotency_key = 'catalog-publish-1'),
  1,
  'same publish idempotency key does not create a second record'
);

select lives_ok(
  $$
    update platform.product_prices
       set status = 'active'
     where id = '27000000-0000-4000-8000-000000000001';
  $$,
  'published version price can be activated for set-current'
);
set local role service_role;
select is(
  public.admin_catalog_command(
    '93000000-0000-4000-8000-000000000001', 'set_current_product_version',
    '23000000-0000-4000-8000-000000000001',
    '{"productVersionId":"24000000-0000-4000-8000-000000000001"}'::jsonb,
    'make local version current', 'catalog-current-1', repeat('b', 64),
    '93000000-0000-0000-0000-000000000103'
  )->>'currentVersionId',
  '24000000-0000-4000-8000-000000000001',
  'set-current command delegates to the product state function'
);
set local role postgres;
select is(
  (select current_version_id::text from platform.products where id = '23000000-0000-4000-8000-000000000001'),
  '24000000-0000-4000-8000-000000000001',
  'set-current updates the product atomically'
);

set local role postgres;
select lives_ok(
  $$
    insert into platform.app_origins (id, app_id, environment, origin)
    values ('93000000-0000-0000-0000-000000000110', '20000000-0000-4000-8000-000000000002', 'staging', 'https://staging.account.example.com');
  $$,
  'production Origin command anchor can be created'
);
set local role service_role;
select is(
  public.admin_catalog_command(
    '93000000-0000-4000-8000-000000000001', 'change_production_origin',
    '93000000-0000-0000-0000-000000000110',
    '{"origin":"https://account.example.com","appSlug":"account"}'::jsonb,
    'switch local production Origin', 'catalog-origin-1', repeat('c', 64),
    '93000000-0000-0000-0000-000000000104'
  )->>'environment',
  'production',
  'production Origin command creates a production exact Origin'
);
set local role postgres;
select is(
  (select count(*)::integer from platform.app_origins
    where app_id = '20000000-0000-4000-8000-000000000002' and environment = 'production' and is_active),
  1,
  'production Origin command leaves one active production Origin'
);
select is(
  (select count(*)::integer from platform.audit_logs where request_id = '93000000-0000-0000-0000-000000000104'),
  1,
  'production Origin command is audited'
);

set local role postgres;
select lives_ok(
  $$
    insert into platform.product_versions (id, product_id, version, sales_terms)
    values ('93000000-0000-0000-0000-000000000120', '23000000-0000-4000-8000-000000000001', 2, '{"label":"Second"}'::jsonb);
    insert into platform.product_version_features (product_version_id, feature_id, value)
    values ('93000000-0000-0000-0000-000000000120', '22000000-0000-4000-8000-000000000001', 'true'::jsonb);
    insert into platform.product_prices (id, product_version_id, currency, amount_minor, channel, status)
    values ('93000000-0000-0000-0000-000000000121', '93000000-0000-0000-0000-000000000120', 'USD', 100, 'manual', 'draft');
  $$,
  'second draft version fixture can be created'
);
set local role service_role;
select is(
  public.admin_catalog_command(
    '93000000-0000-4000-8000-000000000001', 'publish_product_version',
    '93000000-0000-0000-0000-000000000120', '{}'::jsonb, 'publish replacement',
    'catalog-publish-2', repeat('d', 64), '93000000-0000-0000-0000-000000000105'
  )->>'status',
  'published',
  'replacement version publishes through the same command'
);
set local role postgres;
select lives_ok(
  $$ update platform.product_prices set status = 'active' where id = '93000000-0000-0000-0000-000000000121'; $$,
  'replacement version price can be activated'
);
set local role service_role;
select lives_ok(
  $$
    select public.admin_catalog_command(
      '93000000-0000-4000-8000-000000000001', 'set_current_product_version',
      '23000000-0000-4000-8000-000000000001',
      '{"productVersionId":"93000000-0000-0000-0000-000000000120"}'::jsonb,
      'move current to replacement', 'catalog-current-2', repeat('e', 64),
      '93000000-0000-0000-0000-000000000106'
    );
  $$,
  'replacement version becomes current through the named command'
);
select is(
  public.admin_catalog_command(
    '93000000-0000-4000-8000-000000000001', 'retire_product_version',
    '24000000-0000-4000-8000-000000000001', '{}'::jsonb, 'retire old version',
    'catalog-retire-1', repeat('f', 64), '93000000-0000-0000-0000-000000000107'
  )->>'status',
  'retired',
  'retire command delegates to the domain state function'
);
set local role postgres;
select is(
  (select status from platform.product_prices where id = '27000000-0000-4000-8000-000000000001'),
  'retired',
  'retire command retires active prices atomically'
);
set local role service_role;
select throws_ok(
  $$
    select public.admin_catalog_command(
      '93000000-0000-4000-8000-000000000001', 'retire_product_version',
      '24000000-0000-4000-8000-000000000001', '{}'::jsonb, 'different request',
      'catalog-publish-1', repeat('9', 64), '93000000-0000-0000-0000-000000000108'
    );
  $$,
  'P0001', null,
  'same idempotency key with a different request is rejected'
);
set local role postgres;
select is(
  (select count(*)::integer from platform.audit_logs where action like 'catalog.%'),
  6,
  'every successful high-risk Catalog command is audited'
);

select * from finish();
rollback;
