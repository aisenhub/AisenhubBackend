begin;

select plan(59);

select has_function(
  'public',
  'fulfill_paid_order',
  array['uuid'],
  'paid-order fulfillment function is part of the internal domain boundary'
);
select ok(
  coalesce((select prosecdef from pg_proc where oid = to_regprocedure('public.fulfill_paid_order(uuid)')), false),
  'paid-order fulfillment is SECURITY DEFINER'
);
select ok(
  coalesce((select proconfig @> array['search_path=pg_catalog, platform']::text[] from pg_proc where oid = to_regprocedure('public.fulfill_paid_order(uuid)')), false),
  'paid-order fulfillment fixes its search_path'
);
select ok(not coalesce((select has_function_privilege('anon', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.fulfill_paid_order(uuid)')), false), 'anon cannot invoke fulfillment directly');
select ok(not coalesce((select has_function_privilege('authenticated', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.fulfill_paid_order(uuid)')), false), 'authenticated cannot invoke fulfillment directly');
select ok(coalesce((select has_function_privilege('service_role', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.fulfill_paid_order(uuid)')), false), 'service_role can invoke fulfillment through the server boundary');
select has_function('public', 'refund_order_item', array['uuid', 'bigint', 'text', 'text'], 'refund function targets one order item');
select has_function('public', 'chargeback_order', array['uuid', 'text'], 'chargeback function targets one order');
select has_function('public', 'record_paid_after_cancelled_order', array['uuid', 'text'], 'late payment exception function is available');
select ok(coalesce((select has_function_privilege('service_role', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.chargeback_order(uuid, text)')), false), 'service_role can invoke chargeback through the server boundary');
select ok(not coalesce((select has_function_privilege('anon', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.chargeback_order(uuid, text)')), false), 'anon cannot invoke chargeback directly');
select ok(not coalesce((select has_function_privilege('authenticated', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.chargeback_order(uuid, text)')), false), 'authenticated cannot invoke chargeback directly');
select ok(coalesce((select has_function_privilege('service_role', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.record_paid_after_cancelled_order(uuid, text)')), false), 'service_role can record payment exceptions through the server boundary');
select ok(not coalesce((select has_function_privilege('anon', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.record_paid_after_cancelled_order(uuid, text)')), false), 'anon cannot record payment exceptions directly');
select ok(not coalesce((select has_function_privilege('authenticated', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.record_paid_after_cancelled_order(uuid, text)')), false), 'authenticated cannot record payment exceptions directly');

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('98900000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'commerce-state-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('98900000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'commerce-state-other.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);
    insert into platform.admin_members (user_id, role, status)
    values ('98900000-0000-4000-8000-000000000001', 'owner', 'active');
    insert into platform.products (id, sku, name, billing_type)
    values ('99000000-0000-4000-8000-000000000001', 'COMMERCE_STATE_PRODUCT', 'Commerce State Product', 'one_time');
    insert into platform.product_versions (id, product_id, version, status, published_at, sales_terms)
    values ('99100000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001', 1, 'published', now(), '{"support":"standard"}');
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('99200000-0000-4000-8000-000000000001', 'AH-P5-STATE-001', '98900000-0000-4000-8000-000000000001', '99300000-0000-4000-8000-000000000001', 'USD', 2000, 'manual');
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('99400000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce State Product', 'COMMERCE_STATE_PRODUCT', '{"support":"standard"}'),
      ('99400000-0000-4000-8000-000000000002', '99200000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce State Product', 'COMMERCE_STATE_PRODUCT', '{"support":"standard"}');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('99500000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001', 'manual', 'state-payment-001', 'USD', 2000);
    insert into platform.payment_events
      (id, payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at)
    values ('99600000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001', 'manual', 'state-event-001', 'payment.succeeded', 'USD', 2000, now() - interval '1 minute');
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel, status, cancelled_at)
    values ('99200000-0000-4000-8000-000000000002', 'AH-P5-STATE-002', '98900000-0000-4000-8000-000000000002', '99300000-0000-4000-8000-000000000002', 'USD', 0, 'manual', 'cancelled', now());
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('99500000-0000-4000-8000-000000000002', '99200000-0000-4000-8000-000000000002', 'manual', 'state-payment-002', 'USD', 0);
    insert into platform.payment_events
      (id, payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at)
    values ('99600000-0000-4000-8000-000000000002', '99500000-0000-4000-8000-000000000002', '99200000-0000-4000-8000-000000000002', 'manual', 'state-event-002', 'payment.succeeded', 'USD', 0, now() - interval '1 minute');
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('99200000-0000-4000-8000-000000000003', 'AH-P5-STATE-003', '98900000-0000-4000-8000-000000000001', '99300000-0000-4000-8000-000000000003', 'USD', 2000, 'manual');
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('99400000-0000-4000-8000-000000000003', '99200000-0000-4000-8000-000000000003', '99000000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce State Product', 'COMMERCE_STATE_PRODUCT', '{"support":"standard"}'),
      ('99400000-0000-4000-8000-000000000004', '99200000-0000-4000-8000-000000000003', '99000000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce State Product', 'COMMERCE_STATE_PRODUCT', '{"support":"standard"}');
    update platform.order_items
       set fulfillment_status = 'revoked'
     where id = '99400000-0000-4000-8000-000000000004';
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('99500000-0000-4000-8000-000000000003', '99200000-0000-4000-8000-000000000003', 'manual', 'state-payment-003', 'USD', 2000);
    insert into platform.payment_events
      (id, payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at)
    values ('99600000-0000-4000-8000-000000000003', '99500000-0000-4000-8000-000000000003', '99200000-0000-4000-8000-000000000003', 'manual', 'state-event-003', 'payment.succeeded', 'USD', 2000, now() - interval '1 minute');
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('99200000-0000-4000-8000-000000000004', 'AH-P5-STATE-004', '98900000-0000-4000-8000-000000000001', '99300000-0000-4000-8000-000000000004', 'USD', 1000, 'manual');
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('99400000-0000-4000-8000-000000000005', '99200000-0000-4000-8000-000000000004', '99000000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce State Product', 'COMMERCE_STATE_PRODUCT', '{"support":"standard"}');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('99500000-0000-4000-8000-000000000004', '99200000-0000-4000-8000-000000000004', 'manual', 'state-payment-004', 'USD', 1000);
    insert into platform.payment_events
      (id, payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at)
    values ('99600000-0000-4000-8000-000000000004', '99500000-0000-4000-8000-000000000004', '99200000-0000-4000-8000-000000000004', 'manual', 'state-event-004', 'payment.succeeded', 'USD', 1000, now() - interval '1 minute');
  $$,
  'state-machine fixtures can be created'
);

set local role service_role;
select lives_ok($$select public.fulfill_paid_order('99600000-0000-4000-8000-000000000001')$$, 'paid event fulfills every order item atomically');
set local role postgres;
select is((select status from platform.orders where id = '99200000-0000-4000-8000-000000000001'), 'fulfilled', 'successful fulfillment completes the order');
select is((select status from platform.payments where id = '99500000-0000-4000-8000-000000000001'), 'succeeded', 'successful fulfillment completes the payment');
select is((select count(*)::integer from platform.order_items where order_id = '99200000-0000-4000-8000-000000000001' and fulfillment_status = 'granted'), 2, 'every order item is granted');
select is((select count(*)::integer from platform.entitlement_grants where source_type = 'order_item'), 2, 'one grant is created per order item');
select is((select count(*)::integer from platform.entitlement_grants where source_type = 'order_item' and source_id in ('99400000-0000-4000-8000-000000000001', '99400000-0000-4000-8000-000000000002')), 2, 'grant sources are the order item ids');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.fulfill_paid_order'), 1, 'fulfillment writes one audit event');
set local role service_role;
select lives_ok($$select public.fulfill_paid_order('99600000-0000-4000-8000-000000000001')$$, 'duplicate payment events are idempotent');
set local role postgres;
select is((select count(*)::integer from platform.entitlement_grants where source_type = 'order_item'), 2, 'duplicate fulfillment creates no extra grants');
select throws_ok($$select public.fulfill_paid_order('99600000-0000-4000-8000-000000000002')$$, 'P0001', null, 'cancelled orders reject delayed payment fulfillment');
select is((select status from platform.orders where id = '99200000-0000-4000-8000-000000000002'), 'cancelled', 'delayed payment leaves cancelled order unchanged');
select is((select count(*)::integer from platform.entitlement_grants where user_id = '98900000-0000-4000-8000-000000000002'), 0, 'delayed payment creates no grant');
select throws_ok($$select public.fulfill_paid_order('99600000-0000-4000-8000-000000000003')$$, 'P0001', null, 'a revoked item rolls back the whole multi-item fulfillment');
select is((select status from platform.orders where id = '99200000-0000-4000-8000-000000000003'), 'pending', 'failed fulfillment leaves the order pending');
select is((select status from platform.payments where id = '99500000-0000-4000-8000-000000000003'), 'pending', 'failed fulfillment leaves the payment pending');
select is((select status from platform.payment_events where id = '99600000-0000-4000-8000-000000000003'), 'received', 'failed fulfillment leaves the event received');
select is((select fulfillment_status from platform.order_items where id = '99400000-0000-4000-8000-000000000003'), 'pending', 'failed fulfillment rolls back earlier item grants');
select is((select count(*)::integer from platform.entitlement_grants where source_id in ('99400000-0000-4000-8000-000000000003', '99400000-0000-4000-8000-000000000004')), 0, 'failed fulfillment creates no order item grants');
set local role service_role;
select lives_ok($$select public.refund_order_item('99400000-0000-4000-8000-000000000001', 250, 'compensation', 'partial service credit')$$, 'partial compensation targets one order item');
set local role postgres;
select is((select refunded_amount from platform.order_items where id = '99400000-0000-4000-8000-000000000001'), 250::bigint, 'partial compensation is tracked on the item');
select is((select fulfillment_status from platform.order_items where id = '99400000-0000-4000-8000-000000000001'), 'granted', 'partial compensation retains the entitlement');
set local role service_role;
select lives_ok($$select public.refund_order_item('99400000-0000-4000-8000-000000000001', 750, 'return', 'full item refund')$$, 'full item refund can complete the item refund');
set local role postgres;
select is((select refunded_amount from platform.order_items where id = '99400000-0000-4000-8000-000000000001'), 1000::bigint, 'full refund reaches the item total');
select is((select fulfillment_status from platform.order_items where id = '99400000-0000-4000-8000-000000000001'), 'revoked', 'full item refund revokes the sourced grant');
select ok(
  (public.admin_refund_order_item(
    '98900000-0000-4000-8000-000000000001',
    '99400000-0000-4000-8000-000000000002',
    1000,
    'return',
    'return second item',
    'refund-item-001',
    repeat('a', 64),
    '99700000-0000-4000-8000-000000000001'
  ))->>'orderStatus' = 'refunded',
  'Admin refund command completes the remaining OrderItem'
);
select ok(
  (public.admin_refund_order_item(
    '98900000-0000-4000-8000-000000000001',
    '99400000-0000-4000-8000-000000000002',
    1000,
    'return',
    'retry second item',
    'refund-item-001',
    repeat('a', 64),
    '99700000-0000-4000-8000-000000000002'
  ))->>'idempotent' = 'true',
  'Admin refund command retries idempotently'
);
select is((select status from platform.orders where id = '99200000-0000-4000-8000-000000000001'), 'refunded', 'all fully refunded items transition the Order to refunded');
select is((select status from platform.payments where id = '99500000-0000-4000-8000-000000000001'), 'refunded', 'all fully refunded items transition the Payment to refunded');
select is((select fulfillment_status from platform.order_items where id = '99400000-0000-4000-8000-000000000002'), 'revoked', 'full return revokes only the returned item grant');
select is((select count(*)::integer from platform.audit_logs where action = 'order_items.refund'), 1, 'idempotent Admin refund retry writes one Admin audit event');
set local role service_role;
select lives_ok($$select public.fulfill_paid_order('99600000-0000-4000-8000-000000000004')$$, 'a paid Order can be prepared for chargeback');
select lives_ok($$select public.chargeback_order('99200000-0000-4000-8000-000000000004', 'provider dispute')$$, 'chargeback transition revokes the affected grants');
set local role postgres;
select is((select status from platform.orders where id = '99200000-0000-4000-8000-000000000004'), 'chargeback', 'chargeback transitions the Order');
select is((select status from platform.payments where id = '99500000-0000-4000-8000-000000000004'), 'disputed', 'chargeback transitions the Payment');
select is((select fulfillment_status from platform.order_items where id = '99400000-0000-4000-8000-000000000005'), 'revoked', 'chargeback revokes every affected item Grant');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.chargeback_order' and target_id = '99200000-0000-4000-8000-000000000004'), 1, 'chargeback writes an audit event');
set local role service_role;
select lives_ok($$select public.record_paid_after_cancelled_order('99600000-0000-4000-8000-000000000002', 'late payment after cancellation')$$, 'late payment becomes an exception without fulfillment');
set local role postgres;
select is((select status from platform.orders where id = '99200000-0000-4000-8000-000000000002'), 'cancelled', 'late payment leaves the cancelled Order unchanged');
select is((select status from platform.payments where id = '99500000-0000-4000-8000-000000000002'), 'pending', 'late payment leaves the Payment pending for manual handling');
select is((select status from platform.payment_events where id = '99600000-0000-4000-8000-000000000002'), 'ignored', 'late payment event is ignored');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.payment_exception' and target_id = '99200000-0000-4000-8000-000000000002'), 1, 'late payment exception is audited');
select throws_ok($$select public.refund_order_item('99400000-0000-4000-8000-000000000001', 1, 'return', 'over refund')$$, 'P0001', null, 'item refunds cannot exceed the item total');
select throws_ok($$select public.chargeback_order('99200000-0000-4000-8000-000000000001', 'provider dispute')$$, 'P0001', null, 'chargeback transition is explicit and audited');

select * from finish();
rollback;
