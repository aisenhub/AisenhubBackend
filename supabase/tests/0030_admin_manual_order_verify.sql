begin;

select plan(24);

select has_function(
  'public',
  'admin_verify_order',
  array['uuid', 'uuid', 'text', 'bigint', 'text', 'text', 'text', 'text', 'uuid'],
  'manual order verification function exists'
);
select ok(
  coalesce((select prosecdef from pg_proc where oid = to_regprocedure(
    'public.admin_verify_order(uuid,uuid,text,bigint,text,text,text,text,uuid)')), false),
  'manual order verification is SECURITY DEFINER'
);
select ok(
  coalesce((select proconfig @> array['search_path=pg_catalog, platform']::text[] from pg_proc where oid = to_regprocedure(
    'public.admin_verify_order(uuid,uuid,text,bigint,text,text,text,text,uuid)')), false),
  'manual order verification fixes its search_path'
);
select ok(
  coalesce((select has_function_privilege('service_role', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure(
    'public.admin_verify_order(uuid,uuid,text,bigint,text,text,text,text,uuid)')), false),
  'service_role can invoke manual order verification'
);
select ok(
  not coalesce((select has_function_privilege('anon', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure(
    'public.admin_verify_order(uuid,uuid,text,bigint,text,text,text,text,uuid)')), false),
  'anon cannot invoke manual order verification directly'
);
select ok(
  not coalesce((select has_function_privilege('authenticated', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure(
    'public.admin_verify_order(uuid,uuid,text,bigint,text,text,text,text,uuid)')), false),
  'authenticated cannot invoke manual order verification directly'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('99700000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'manual-verify-owner.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
      ('99700000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'manual-verify-finance.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
      ('99700000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
       'manual-verify-support.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
      ('99700000-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
       'manual-verify-customer.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
      ('99700000-0000-4000-8000-000000000005', 'authenticated', 'authenticated',
       'manual-verify-other.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false);
    insert into platform.admin_members (user_id, role) values
      ('99700000-0000-4000-8000-000000000001', 'owner'),
      ('99700000-0000-4000-8000-000000000002', 'finance'),
      ('99700000-0000-4000-8000-000000000003', 'support');
    insert into platform.products (id, sku, name, billing_type)
    values ('99700000-0000-4000-8000-000000000010', 'MANUAL_VERIFY_PRODUCT', 'Manual Verify Product', 'one_time');
    insert into platform.product_versions (id, product_id, version, status, published_at, sales_terms)
    values ('99700000-0000-4000-8000-000000000011', '99700000-0000-4000-8000-000000000010', 1, 'published', now(), '{"support":"standard"}');
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('99700000-0000-4000-8000-000000000020', 'AH-P5-MANUAL-001', '99700000-0000-4000-8000-000000000004',
            '99700000-0000-4000-8000-000000000030', 'USD', 2000, 'manual');
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('99700000-0000-4000-8000-000000000021', '99700000-0000-4000-8000-000000000020',
       '99700000-0000-4000-8000-000000000010', '99700000-0000-4000-8000-000000000011',
       1, 1000, 1000, 'Manual Verify Product', 'MANUAL_VERIFY_PRODUCT', '{"support":"standard"}'),
      ('99700000-0000-4000-8000-000000000022', '99700000-0000-4000-8000-000000000020',
       '99700000-0000-4000-8000-000000000010', '99700000-0000-4000-8000-000000000011',
       1, 1000, 1000, 'Manual Verify Product', 'MANUAL_VERIFY_PRODUCT', '{"support":"standard"}');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('99700000-0000-4000-8000-000000000023', '99700000-0000-4000-8000-000000000020',
            'manual', 'manual-proof-001', 'USD', 2000);
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('99700000-0000-4000-8000-000000000040', 'AH-P5-MANUAL-002', '99700000-0000-4000-8000-000000000005',
            '99700000-0000-4000-8000-000000000041', 'USD', 1000, 'manual');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('99700000-0000-4000-8000-000000000042', '99700000-0000-4000-8000-000000000040',
            'manual', 'manual-proof-002', 'USD', 1000);
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('99700000-0000-4000-8000-000000000050', 'AH-P5-CODE-001', '99700000-0000-4000-8000-000000000005',
            '99700000-0000-4000-8000-000000000051', 'USD', 0, 'code_sale');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('99700000-0000-4000-8000-000000000052', '99700000-0000-4000-8000-000000000050',
            'manual', 'manual-proof-003', 'USD', 0);
  $$,
  'manual verification fixtures can be created'
);

set local role service_role;
select ok(
  (public.admin_verify_order(
    '99700000-0000-4000-8000-000000000002',
    '99700000-0000-4000-8000-000000000020',
    'manual-proof-001', 2000, 'USD', 'cash receipt matched', 'manual-verify-001', repeat('a', 64),
    '99700000-0000-4000-8000-000000000060'
  )) ? 'grantIds',
  'Finance can manually verify a manual order through fulfillment'
);
set local role postgres;
select is((select status from platform.orders where id = '99700000-0000-4000-8000-000000000020'), 'fulfilled', 'manual verification fulfills the order');
select is((select status from platform.payments where id = '99700000-0000-4000-8000-000000000023'), 'succeeded', 'manual verification succeeds the payment');
select is((select count(*)::integer from platform.payment_events where order_id = '99700000-0000-4000-8000-000000000020' and status = 'processed'), 1, 'manual verification records one processed payment event');
select is((select count(*)::integer from platform.entitlement_grants where source_id in ('99700000-0000-4000-8000-000000000021', '99700000-0000-4000-8000-000000000022')), 2, 'manual verification grants every order item independently');
select is((select count(*)::integer from platform.audit_logs where action = 'orders.verify' and target_id = '99700000-0000-4000-8000-000000000020'), 1, 'manual verification writes an Admin audit event');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.fulfill_paid_order' and target_id = '99700000-0000-4000-8000-000000000020'), 1, 'manual verification reuses the fulfillment audit path');
select ok(
  (public.admin_verify_order(
    '99700000-0000-4000-8000-000000000002',
    '99700000-0000-4000-8000-000000000020',
    'manual-proof-001', 2000, 'USD', 'retry', 'manual-verify-001', repeat('a', 64),
    '99700000-0000-4000-8000-000000000061'
  )) ? 'idempotent',
  'same manual verification key replays the original result'
);
select is((select count(*)::integer from platform.entitlement_grants where source_id in ('99700000-0000-4000-8000-000000000021', '99700000-0000-4000-8000-000000000022')), 2, 'manual verification retry creates no extra grants');
select is((select count(*)::integer from platform.payment_events where order_id = '99700000-0000-4000-8000-000000000020'), 1, 'manual verification retry creates no extra event');
select throws_ok($$select public.admin_verify_order(
  '99700000-0000-4000-8000-000000000002', '99700000-0000-4000-8000-000000000020',
  'manual-proof-001', 2000, 'USD', 'different request', 'manual-verify-001', repeat('b', 64),
  '99700000-0000-4000-8000-000000000062')$$,
  'P0001', null, 'same verification key cannot change its request hash'
);
select throws_ok($$select public.admin_verify_order(
  '99700000-0000-4000-8000-000000000003', '99700000-0000-4000-8000-000000000040',
  'manual-proof-002', 1000, 'USD', 'support attempt', 'manual-verify-002', repeat('c', 64),
  '99700000-0000-4000-8000-000000000063')$$,
  '42501', null, 'Support cannot manually verify an order'
);
select throws_ok($$select public.admin_verify_order(
  '99700000-0000-4000-8000-000000000002', '99700000-0000-4000-8000-000000000040',
  'manual-proof-002', 999, 'USD', 'wrong amount', 'manual-verify-003', repeat('d', 64),
  '99700000-0000-4000-8000-000000000064')$$,
  'P0003', null, 'manual verification rejects an amount mismatch'
);
select throws_ok($$select public.admin_verify_order(
  '99700000-0000-4000-8000-000000000002', '99700000-0000-4000-8000-000000000040',
  'manual-proof-002', 1000, 'usd', 'wrong currency', 'manual-verify-004', repeat('e', 64),
  '99700000-0000-4000-8000-000000000065')$$,
  '22023', null, 'manual verification rejects an invalid currency'
);
select throws_ok($$select public.admin_verify_order(
  '99700000-0000-4000-8000-000000000002', '99700000-0000-4000-8000-000000000050',
  'manual-proof-003', 0, 'USD', 'wrong channel', 'manual-verify-005', repeat('f', 64),
  '99700000-0000-4000-8000-000000000066')$$,
  'P0004', null, 'manual verification rejects non-manual orders'
);
select is((select status from platform.orders where id = '99700000-0000-4000-8000-000000000040'), 'pending', 'failed manual verification leaves the order unchanged');
select is((select count(*)::integer from platform.payment_events where order_id = '99700000-0000-4000-8000-000000000040'), 0, 'failed manual verification leaves no orphan event');

select * from finish();
rollback;
