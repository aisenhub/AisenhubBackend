begin;

select plan(16);

select has_column('platform', 'orders', 'application_id', 'orders retain application context');
select has_column('platform', 'entitlement_grants', 'application_id', 'entitlement grants retain application context');
select has_column('platform', 'redemptions', 'application_id', 'redemptions retain application context');
select has_function('platform', 'application_owns_product_version', array['uuid', 'uuid'], 'product-version ownership helper exists');
select has_function('public', 'redeem_application_code', array['text', 'uuid', 'uuid', 'text', 'text', 'text'], 'application redemption command exists');
select is(
  (select prosecdef from pg_proc where oid = 'public.redeem_application_code(text,uuid,uuid,text,text,text)'::regprocedure),
  true, 'application redemption command is SECURITY DEFINER'
);
select ok(has_function_privilege('service_role', 'public.redeem_application_code(text,uuid,uuid,text,text,text)', 'EXECUTE'), 'service_role can execute application redemption');
select ok(not has_function_privilege('anon', 'public.redeem_application_code(text,uuid,uuid,text,text,text)', 'EXECUTE'), 'anon cannot execute application redemption directly');

set local role postgres;
select lives_ok($$
  insert into auth.users (id, email) values ('99000000-0000-4000-8000-000000000001', 'scoped-commerce@aisenhub.test');
  insert into platform.platform_apps (id, slug, name, category, status, membership_policy)
  values
    ('99000000-0000-4000-8000-000000000101', 'commerce-app-a', 'Commerce App A', 'test', 'active', 'explicit'),
    ('99000000-0000-4000-8000-000000000102', 'commerce-app-b', 'Commerce App B', 'test', 'active', 'explicit');
  insert into platform.application_memberships (id, application_id, user_id, status, created_source, activated_at)
  values
    ('99000000-0000-4000-8000-000000000201', '99000000-0000-4000-8000-000000000101', '99000000-0000-4000-8000-000000000001', 'active', 'test', now()),
    ('99000000-0000-4000-8000-000000000202', '99000000-0000-4000-8000-000000000102', '99000000-0000-4000-8000-000000000001', 'active', 'test', now());
  insert into platform.features (id, app_id, code, name, value_type, merge_strategy)
  values
    ('99000000-0000-4000-8000-000000000301', '99000000-0000-4000-8000-000000000101', 'commerce.app.a', 'Commerce App A', 'boolean', 'any_true'),
    ('99000000-0000-4000-8000-000000000302', '99000000-0000-4000-8000-000000000102', 'commerce.app.b', 'Commerce App B', 'boolean', 'any_true');
  insert into platform.products (id, sku, name, billing_type, status)
  values ('99000000-0000-4000-8000-000000000401', 'COMMERCE_APP_B_PRODUCT', 'Commerce App B Product', 'one_time', 'draft');
  insert into platform.product_versions (id, product_id, version, status, published_at)
  values ('99000000-0000-4000-8000-000000000402', '99000000-0000-4000-8000-000000000401', 1, 'published', now());
  insert into platform.product_version_features (product_version_id, feature_id, value)
  values ('99000000-0000-4000-8000-000000000402', '99000000-0000-4000-8000-000000000302', 'true'::jsonb);
  insert into platform.redemption_batches (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, status, source, created_by)
  values ('99000000-0000-4000-8000-000000000501', 'App B Codes', '99000000-0000-4000-8000-000000000401', '99000000-0000-4000-8000-000000000402', 'APPB', 1, 1, 'active', 'test', '99000000-0000-4000-8000-000000000001');
  insert into platform.redemption_codes (id, batch_id, code_hash, code_hint, pepper_version)
  values ('99000000-0000-4000-8000-000000000502', '99000000-0000-4000-8000-000000000501', repeat('b', 64), 'APPB-****', 1);
$$, 'application commerce fixtures can be created');

select throws_ok($$ select public.redeem_application_code(
  repeat('b', 64), '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000101',
  'scoped-redemption-cross-app', 'scoped-redemption-cross-app-hash', null); $$,
  'P0001', null, 'an App A context cannot redeem an App B product code');
select is((select status from platform.redemption_codes where id = '99000000-0000-4000-8000-000000000502'), 'issued', 'cross-app rejection leaves the code issued');
select lives_ok($$ select public.redeem_application_code(
  repeat('b', 64), '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000102',
  'scoped-redemption-app-b', 'scoped-redemption-app-b-hash', null); $$,
  'the owning application can redeem the code');
select is((select application_id from platform.redemptions where code_id = '99000000-0000-4000-8000-000000000502'), '99000000-0000-4000-8000-000000000102', 'redemption records retain the resolved application');
select is((select application_id from platform.entitlement_grants where id = (select grant_id from platform.redemptions where code_id = '99000000-0000-4000-8000-000000000502')), '99000000-0000-4000-8000-000000000102', 'redemption grants retain the resolved application');
select lives_ok($$ select public.redeem_application_code(
  repeat('b', 64), '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000102',
  'scoped-redemption-app-b', 'scoped-redemption-app-b-hash', null); $$,
  'application redemption preserves the existing idempotent replay');
select throws_ok($$
  insert into platform.orders (id, order_no, user_id, application_id, status, currency, amount_total, channel)
  values ('99000000-0000-4000-8000-000000000601', 'SCOPED-ORDER-1', '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000101', 'pending', 'USD', 0, 'manual');
  insert into platform.order_items (order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
  values ('99000000-0000-4000-8000-000000000601', '99000000-0000-4000-8000-000000000401', '99000000-0000-4000-8000-000000000402', 1, 0, 0, 'Commerce App B Product', 'COMMERCE_APP_B_PRODUCT', '{}'::jsonb);
$$, '23514', null, 'an App A order cannot contain an App B product version');

select * from finish();
rollback;
