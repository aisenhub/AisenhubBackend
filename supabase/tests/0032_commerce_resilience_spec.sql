begin;

select plan(37);

select has_function(
  'public',
  'receive_payment_webhook_event',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'bigint', 'jsonb', 'timestamp with time zone'],
  'resilience flow uses the signed webhook domain boundary'
);
select has_function('public', 'chargeback_order', array['uuid', 'text'], 'resilience flow includes chargeback');
select ok(
  coalesce((select has_function_privilege('service_role', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)')), false),
  'service_role can dispatch a webhook event'
);
select ok(
  not coalesce((select has_function_privilege('anon', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.chargeback_order(uuid, text)')), false),
  'anon cannot dispatch chargeback'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '9c000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'commerce-resilience.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.products (id, sku, name, billing_type)
    values ('9c100000-0000-4000-8000-000000000001', 'COMMERCE_RESILIENCE_PRODUCT', 'Commerce Resilience Product', 'one_time');
    insert into platform.product_versions (id, product_id, version, status, published_at, sales_terms)
    values ('9c200000-0000-4000-8000-000000000001', '9c100000-0000-4000-8000-000000000001', 1, 'published', now(), '{"support":"standard"}'::jsonb);
    insert into platform.orders
      (id, order_no, user_id, customer_ref, currency, amount_total, channel, status, cancelled_at)
    values
      ('9c300000-0000-4000-8000-000000000001', 'AH-P5-RESILIENCE-001', '9c000000-0000-4000-8000-000000000001', '9c400000-0000-4000-8000-000000000001', 'USD', 2000, 'local', 'pending', null),
      ('9c300000-0000-4000-8000-000000000002', 'AH-P5-RESILIENCE-002', '9c000000-0000-4000-8000-000000000001', '9c400000-0000-4000-8000-000000000002', 'USD', 1000, 'local', 'pending', null),
      ('9c300000-0000-4000-8000-000000000003', 'AH-P5-RESILIENCE-003', '9c000000-0000-4000-8000-000000000001', '9c400000-0000-4000-8000-000000000003', 'USD', 0, 'local', 'pending', null),
      ('9c300000-0000-4000-8000-000000000004', 'AH-P5-RESILIENCE-004', '9c000000-0000-4000-8000-000000000001', '9c400000-0000-4000-8000-000000000004', 'USD', 0, 'local', 'cancelled', now());
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('9c500000-0000-4000-8000-000000000001', '9c300000-0000-4000-8000-000000000001', '9c100000-0000-4000-8000-000000000001', '9c200000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce Resilience Product', 'COMMERCE_RESILIENCE_PRODUCT', '{"support":"standard"}'::jsonb),
      ('9c500000-0000-4000-8000-000000000002', '9c300000-0000-4000-8000-000000000001', '9c100000-0000-4000-8000-000000000001', '9c200000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce Resilience Product', 'COMMERCE_RESILIENCE_PRODUCT', '{"support":"standard"}'::jsonb),
      ('9c500000-0000-4000-8000-000000000003', '9c300000-0000-4000-8000-000000000002', '9c100000-0000-4000-8000-000000000001', '9c200000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce Resilience Product', 'COMMERCE_RESILIENCE_PRODUCT', '{"support":"standard"}'::jsonb),
      ('9c500000-0000-4000-8000-000000000004', '9c300000-0000-4000-8000-000000000004', '9c100000-0000-4000-8000-000000000001', '9c200000-0000-4000-8000-000000000001', 1, 0, 0, 'Commerce Resilience Product', 'COMMERCE_RESILIENCE_PRODUCT', '{"support":"standard"}'::jsonb);
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values
      ('9c600000-0000-4000-8000-000000000001', '9c300000-0000-4000-8000-000000000001', 'local', 'resilience-payment-001', 'USD', 2000),
      ('9c600000-0000-4000-8000-000000000002', '9c300000-0000-4000-8000-000000000002', 'local', 'resilience-payment-002', 'USD', 1000),
      ('9c600000-0000-4000-8000-000000000003', '9c300000-0000-4000-8000-000000000003', 'local', 'resilience-payment-003', 'USD', 0),
      ('9c600000-0000-4000-8000-000000000004', '9c300000-0000-4000-8000-000000000004', 'local', 'resilience-payment-004', 'USD', 0);
  $$,
  'resilience fixtures create multi-item, chargeback, out-of-order, and late-payment orders'
);

set local role service_role;
select lives_ok(
  $$select public.receive_payment_webhook_event(
    '9c600000-0000-4000-8000-000000000001', '9c300000-0000-4000-8000-000000000001',
    'local', 'resilience-event-001', 'payment.succeeded', 'USD', 2000,
    '{"providerStatus":"approved","channel":"local"}'::jsonb, '2026-09-01T11:00:00Z'::timestamptz
  )$$,
  'signed payment event fulfills the multi-item order'
);
set local role postgres;
select is((select status from platform.orders where id = '9c300000-0000-4000-8000-000000000001'), 'fulfilled', 'multi-item order becomes fulfilled');
select is((select status from platform.payments where id = '9c600000-0000-4000-8000-000000000001'), 'succeeded', 'multi-item payment becomes succeeded');
select is((select count(*)::integer from platform.entitlement_grants where source_type = 'order_item' and source_id in ('9c500000-0000-4000-8000-000000000001', '9c500000-0000-4000-8000-000000000002')), 2, 'one Grant is created for each item');
set local role service_role;
select ok((public.receive_payment_webhook_event(
  '9c600000-0000-4000-8000-000000000001', '9c300000-0000-4000-8000-000000000001',
  'local', 'resilience-event-001', 'payment.succeeded', 'USD', 2000,
  '{"providerStatus":"approved","channel":"local"}'::jsonb, '2026-09-01T11:00:00Z'::timestamptz
))->>'idempotent' = 'true', 'duplicate payment event is idempotent');
set local role postgres;
select is((select count(*)::integer from platform.entitlement_grants where source_type = 'order_item' and source_id in ('9c500000-0000-4000-8000-000000000001', '9c500000-0000-4000-8000-000000000002')), 2, 'duplicate payment event creates no extra Grant');

set local role service_role;
select lives_ok($$select public.refund_order_item('9c500000-0000-4000-8000-000000000001', 250, 'compensation', 'resilience partial compensation')$$, 'partial compensation succeeds');
set local role postgres;
select is((select refunded_amount from platform.order_items where id = '9c500000-0000-4000-8000-000000000001'), 250::bigint, 'partial refund amount is exact');
select is((select fulfillment_status from platform.order_items where id = '9c500000-0000-4000-8000-000000000001'), 'granted', 'partial compensation retains the Grant');
set local role service_role;
select lives_ok($$select public.refund_order_item('9c500000-0000-4000-8000-000000000001', 750, 'return', 'resilience full item return')$$, 'full product return succeeds');
set local role postgres;
select is((select fulfillment_status from platform.order_items where id = '9c500000-0000-4000-8000-000000000001'), 'revoked', 'full product return revokes only its Grant');
set local role service_role;
select lives_ok($$select public.refund_order_item('9c500000-0000-4000-8000-000000000002', 1000, 'return', 'resilience remaining item return')$$, 'remaining item return succeeds');
set local role postgres;
select is((select status from platform.orders where id = '9c300000-0000-4000-8000-000000000001'), 'refunded', 'all item returns complete the Order');
select is((select status from platform.payments where id = '9c600000-0000-4000-8000-000000000001'), 'refunded', 'all item returns complete the Payment');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.refund_order_item' and target_type = 'order_item' and target_id in ('9c500000-0000-4000-8000-000000000001', '9c500000-0000-4000-8000-000000000002')), 3, 'partial and complete refunds retain an exact audit trace');

set local role service_role;
select lives_ok($$select public.receive_payment_webhook_event(
  '9c600000-0000-4000-8000-000000000002', '9c300000-0000-4000-8000-000000000002',
  'local', 'resilience-event-002', 'payment.succeeded', 'USD', 1000,
  '{"providerStatus":"approved"}'::jsonb, '2026-09-01T11:05:00Z'::timestamptz
)$$, 'chargeback order is first fulfilled through the webhook boundary');
select lives_ok($$select public.chargeback_order('9c300000-0000-4000-8000-000000000002', 'resilience provider dispute')$$, 'chargeback succeeds after fulfillment');
set local role postgres;
select is((select status from platform.orders where id = '9c300000-0000-4000-8000-000000000002'), 'chargeback', 'chargeback transitions the Order');
select is((select status from platform.payments where id = '9c600000-0000-4000-8000-000000000002'), 'disputed', 'chargeback disputes the Payment');
select is((select fulfillment_status from platform.order_items where id = '9c500000-0000-4000-8000-000000000003'), 'revoked', 'chargeback revokes the item fulfillment');
select is((select status from platform.payment_events where external_event_id = 'resilience-event-002'), 'processed', 'chargeback source event remains processed');
select is((select count(*)::integer from platform.entitlement_grants where source_id = '9c500000-0000-4000-8000-000000000003' and status = 'revoked'), 1, 'chargeback leaves one revoked Grant trace');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.chargeback_order' and target_id = '9c300000-0000-4000-8000-000000000002'), 1, 'chargeback writes one audit event');

set local role service_role;
select lives_ok($$select public.receive_payment_webhook_event(
  '9c600000-0000-4000-8000-000000000003', '9c300000-0000-4000-8000-000000000003',
  'local', 'resilience-event-003-failed', 'payment.failed', 'USD', 0,
  '{"providerStatus":"declined"}'::jsonb, '2026-09-01T11:10:00Z'::timestamptz
)$$, 'out-of-order failed event is safely ignored');
select lives_ok($$select public.receive_payment_webhook_event(
  '9c600000-0000-4000-8000-000000000003', '9c300000-0000-4000-8000-000000000003',
  'local', 'resilience-event-003-succeeded', 'payment.succeeded', 'USD', 0,
  '{"providerStatus":"approved"}'::jsonb, '2026-09-01T11:11:00Z'::timestamptz
)$$, 'later success event fulfills after the ignored event');
set local role postgres;
select is((select status from platform.orders where id = '9c300000-0000-4000-8000-000000000003'), 'fulfilled', 'later success determines the final Order state');
select is((select status from platform.payment_events where external_event_id = 'resilience-event-003-failed'), 'ignored', 'stale failed event remains ignored');

set local role service_role;
select lives_ok($$select public.receive_payment_webhook_event(
  '9c600000-0000-4000-8000-000000000004', '9c300000-0000-4000-8000-000000000004',
  'local', 'resilience-event-004-late', 'payment.succeeded', 'USD', 0,
  '{"providerStatus":"approved"}'::jsonb, '2026-09-01T11:12:00Z'::timestamptz
)$$, 'late success event is recorded as an exception');
set local role postgres;
select is((select status from platform.orders where id = '9c300000-0000-4000-8000-000000000004'), 'cancelled', 'late payment leaves the cancelled Order unchanged');
select is((select status from platform.payment_events where external_event_id = 'resilience-event-004-late'), 'ignored', 'late success event is ignored after audit');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.payment_exception' and target_id = '9c300000-0000-4000-8000-000000000004'), 1, 'late payment writes one exception audit');
select ok(
  not exists (
    select 1 from platform.audit_logs
     where target_id in ('9c300000-0000-4000-8000-000000000001', '9c300000-0000-4000-8000-000000000002', '9c300000-0000-4000-8000-000000000003', '9c300000-0000-4000-8000-000000000004')
       and (reason ilike '%token%' or reason ilike '%secret%' or before_summary::text ilike '%credential%' or after_summary::text ilike '%credential%')
  ),
  'resilience audits contain no credential material'
);

select * from finish();
rollback;
