begin;

select plan(22);

select has_function(
  'public',
  'receive_payment_webhook_event',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'bigint', 'jsonb', 'timestamp with time zone'],
  'webhook intake function is part of the internal domain boundary'
);
select ok(
  coalesce((select prosecdef from pg_proc where oid = to_regprocedure('public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)')), false),
  'webhook intake is SECURITY DEFINER'
);
select ok(
  coalesce((select proconfig @> array['search_path=pg_catalog, platform']::text[] from pg_proc where oid = to_regprocedure('public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)')), false),
  'webhook intake fixes its search_path'
);
select ok(not coalesce((select has_function_privilege('anon', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)')), false), 'anon cannot invoke webhook intake directly');
select ok(not coalesce((select has_function_privilege('authenticated', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)')), false), 'authenticated cannot invoke webhook intake directly');
select ok(coalesce((select has_function_privilege('service_role', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)')), false), 'service_role can invoke webhook intake');

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '9a000000-0000-4000-8000-000000000001'::uuid, 'authenticated', 'authenticated',
       'commerce-webhook-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.products (id, sku, name, billing_type)
    values ('9a100000-0000-4000-8000-000000000001', 'COMMERCE_WEBHOOK_PRODUCT', 'Commerce Webhook Product', 'one_time');
    insert into platform.product_versions (id, product_id, version, status, published_at, sales_terms)
    values ('9a200000-0000-4000-8000-000000000001', '9a100000-0000-4000-8000-000000000001', 1, 'published', now(), '{"support":"standard"}');
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('9a300000-0000-4000-8000-000000000001', 'AH-P5-WEBHOOK-001', '9a000000-0000-4000-8000-000000000001', '9a400000-0000-4000-8000-000000000001', 'USD', 1000, 'local');
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('9a500000-0000-4000-8000-000000000001', '9a300000-0000-4000-8000-000000000001', '9a100000-0000-4000-8000-000000000001', '9a200000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce Webhook Product', 'COMMERCE_WEBHOOK_PRODUCT', '{"support":"standard"}');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('9a600000-0000-4000-8000-000000000001', '9a300000-0000-4000-8000-000000000001', 'local', 'local-payment-001', 'USD', 1000);
  $$,
  'webhook fixtures can be created'
);

set local role service_role;
select lives_ok(
  $$select public.receive_payment_webhook_event(
    '9a600000-0000-4000-8000-000000000001', '9a300000-0000-4000-8000-000000000001',
    'local', 'local-event-001', 'payment.succeeded', 'USD', 1000,
    '{"providerStatus":"approved"}'::jsonb, '2026-09-01T11:00:00Z'::timestamptz
  )$$,
  'valid payment webhook atomically fulfills the order'
);
set local role postgres;
select is((select status from platform.orders where id = '9a300000-0000-4000-8000-000000000001'), 'fulfilled', 'webhook fulfillment completes the order');
select is((select status from platform.payments where id = '9a600000-0000-4000-8000-000000000001'), 'succeeded', 'webhook fulfillment completes the payment');
select is((select status from platform.payment_events where external_event_id = 'local-event-001'), 'processed', 'webhook event is processed');
select is((select count(*)::integer from platform.entitlement_grants where source_id = '9a500000-0000-4000-8000-000000000001'), 1, 'webhook creates one order item grant');

set local role service_role;
select ok(
  (public.receive_payment_webhook_event(
    '9a600000-0000-4000-8000-000000000001', '9a300000-0000-4000-8000-000000000001',
    'local', 'local-event-001', 'payment.succeeded', 'USD', 1000,
    '{"providerStatus":"approved"}'::jsonb, '2026-09-01T11:00:00Z'::timestamptz
  ))->>'idempotent' = 'true',
  'duplicate webhook event is idempotent'
);
set local role postgres;
select is((select count(*)::integer from platform.entitlement_grants where source_id = '9a500000-0000-4000-8000-000000000001'), 1, 'duplicate webhook creates no extra grant');
set local role service_role;
select throws_ok(
  $$select public.receive_payment_webhook_event(
    '9a600000-0000-4000-8000-000000000001', '9a300000-0000-4000-8000-000000000001',
    'local', 'local-event-001', 'payment.succeeded', 'USD', 999,
    '{"providerStatus":"approved"}'::jsonb, '2026-09-01T11:00:00Z'::timestamptz
  )$$,
  '23514', null, 'duplicate event with different facts is rejected'
);

set local role postgres;
select lives_ok(
  $$
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('9a300000-0000-4000-8000-000000000002', 'AH-P5-WEBHOOK-002', '9a000000-0000-4000-8000-000000000001', '9a400000-0000-4000-8000-000000000002', 'USD', 0, 'local');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values ('9a600000-0000-4000-8000-000000000002', '9a300000-0000-4000-8000-000000000002', 'local', 'local-payment-002', 'USD', 0);
  $$,
  'out-of-order webhook fixtures can be created'
);
set local role service_role;
select lives_ok(
  $$select public.receive_payment_webhook_event(
    '9a600000-0000-4000-8000-000000000002', '9a300000-0000-4000-8000-000000000002',
    'local', 'local-event-002-failed', 'payment.failed', 'USD', 0,
    '{"providerStatus":"declined"}'::jsonb, '2026-09-01T11:01:00Z'::timestamptz
  )$$,
  'unsupported earlier event is safely ignored'
);
select lives_ok(
  $$select public.receive_payment_webhook_event(
    '9a600000-0000-4000-8000-000000000002', '9a300000-0000-4000-8000-000000000002',
    'local', 'local-event-002-succeeded', 'payment.succeeded', 'USD', 0,
    '{"providerStatus":"approved"}'::jsonb, '2026-09-01T11:02:00Z'::timestamptz
  )$$,
  'later success event can fulfill after an earlier ignored event'
);
set local role postgres;
select is((select status from platform.orders where id = '9a300000-0000-4000-8000-000000000002'), 'fulfilled', 'later success wins without a stale event reverting state');
select is((select status from platform.payment_events where external_event_id = 'local-event-002-failed'), 'ignored', 'earlier failed event remains ignored');
select is((select count(*)::integer from platform.audit_logs where action = 'commerce.payment_event_ignored' and target_id = '9a300000-0000-4000-8000-000000000002'), 1, 'ignored event writes an audit record');
select ok(
  not exists (
    select 1 from platform.audit_logs
     where action = 'commerce.payment_event_ignored'
       and (reason ilike '%secret%' or reason ilike '%token%')
  ),
  'ignored event audit does not contain secret material'
);

select * from finish();
rollback;
