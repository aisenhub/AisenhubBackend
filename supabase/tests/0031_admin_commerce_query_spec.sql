begin;

select plan(21);

select has_function('public', 'admin_query_commerce_resource', array['uuid', 'text', 'text', 'integer', 'text', 'text', 'text', 'text'], 'Commerce list projection exists');
select has_function('public', 'admin_order_overview', array['uuid', 'uuid'], 'Order 360 projection exists');
select ok(coalesce((select prosecdef from pg_proc where oid = to_regprocedure('public.admin_query_commerce_resource(uuid, text, text, integer, text, text, text, text)')), false), 'Commerce list projection is SECURITY DEFINER');
select ok(coalesce((select prosecdef from pg_proc where oid = to_regprocedure('public.admin_order_overview(uuid, uuid)')), false), 'Order 360 projection is SECURITY DEFINER');
select ok(not coalesce((select has_function_privilege('anon', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.admin_query_commerce_resource(uuid, text, text, integer, text, text, text, text)')), false), 'anon cannot invoke Commerce list projection');
select ok(not coalesce((select has_function_privilege('authenticated', oid, 'EXECUTE') from pg_proc where oid = to_regprocedure('public.admin_order_overview(uuid, uuid)')), false), 'authenticated cannot invoke Order 360 projection');

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('9b000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'commerce-query-owner.local@aisenhub.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), false),
      ('9b000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'commerce-query-finance.local@aisenhub.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), false);
    insert into platform.admin_members (user_id, role, status)
    values
      ('9b000000-0000-4000-8000-000000000001', 'admin', 'active'),
      ('9b000000-0000-4000-8000-000000000002', 'finance', 'active');
    insert into platform.products (id, sku, name, billing_type)
    values ('9b100000-0000-4000-8000-000000000001', 'COMMERCE_QUERY_PRODUCT', 'Commerce Query Product', 'one_time');
    insert into platform.product_versions (id, product_id, version, status, published_at, sales_terms)
    values ('9b200000-0000-4000-8000-000000000001', '9b100000-0000-4000-8000-000000000001', 1, 'published', now(), '{"support":"standard"}');
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('9b300000-0000-4000-8000-000000000001', 'AH-P5-QUERY-001', '9b000000-0000-4000-8000-000000000001', '9b400000-0000-4000-8000-000000000001', 'USD', 2000, 'local');
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms, fulfillment_status, refunded_amount)
    values
      ('9b500000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001', '9b100000-0000-4000-8000-000000000001', '9b200000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce Query Product', 'COMMERCE_QUERY_PRODUCT', '{"support":"standard"}', 'granted', 0),
      ('9b500000-0000-4000-8000-000000000002', '9b300000-0000-4000-8000-000000000001', '9b100000-0000-4000-8000-000000000001', '9b200000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Commerce Query Product', 'COMMERCE_QUERY_PRODUCT', '{"support":"standard"}', 'granted', 250);
    update platform.orders
       set status = 'fulfilled', paid_at = now(), fulfilled_at = now()
     where id = '9b300000-0000-4000-8000-000000000001';
    insert into platform.payments
      (id, order_id, provider, external_payment_id, status, currency, amount, paid_at)
    values ('9b600000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001', 'local', 'local-query-payment-001', 'succeeded', 'USD', 2000, now());
    insert into platform.payment_events
      (id, payment_id, order_id, provider, external_event_id, event_type, status, currency, amount, occurred_at, processed_at)
    values ('9b700000-0000-4000-8000-000000000001', '9b600000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001', 'local', 'local-query-event-001', 'payment.succeeded', 'processed', 'USD', 2000, now() - interval '1 minute', now());
  $$,
  'Commerce query fixtures can be created'
);

set local role service_role;
select lives_ok($$select * from public.grant_entitlement('9b000000-0000-4000-8000-000000000001', '9b200000-0000-4000-8000-000000000001', 'order_item', '9b500000-0000-4000-8000-000000000001', now() - interval '1 hour', null, 'system', null, 'query fixture grant', null, null)$$, 'fixture grant can be created through the domain function');
set local role postgres;
insert into platform.audit_logs (id, actor_type, action, target_type, target_id, request_id, reason, before_summary, after_summary)
values
  ('9b800000-0000-4000-8000-000000000001', 'admin', 'order_items.refund', 'order_item', '9b500000-0000-4000-8000-000000000002', null, 'partial service credit', '{}', '{"refundedAmount":250,"mode":"compensation"}'),
  ('9b800000-0000-4000-8000-000000000002', 'webhook', 'commerce.payment_exception', 'order', '9b300000-0000-4000-8000-000000000001', '9b700000-0000-4000-8000-000000000001', 'late payment exception', '{"paymentStatus":"pending"}', '{"exceptionType":"late_payment_after_cancel","paymentEventId":"9b700000-0000-4000-8000-000000000001"}')
  on conflict (id) do nothing;

set local role service_role;
select lives_ok($$select public.admin_query_commerce_resource('9b000000-0000-4000-8000-000000000001', 'orders', null, 10, 'QUERY-001', null, 'orderNo', 'asc')$$, 'Admin Order query supports search and sort');
select is((public.admin_query_commerce_resource('9b000000-0000-4000-8000-000000000001', 'orders', null, 10, 'QUERY-001', null, 'orderNo', 'asc')->'items'->0->>'orderNo'), 'AH-P5-QUERY-001', 'Order query returns the matching order');
select lives_ok($$select public.admin_query_commerce_resource('9b000000-0000-4000-8000-000000000002', 'orders', null, 10, null, 'fulfilled', 'createdAt', 'desc')$$, 'Finance can query Orders');
select is((public.admin_query_commerce_resource('9b000000-0000-4000-8000-000000000002', 'orders', null, 10, null, 'fulfilled', 'createdAt', 'desc')->'items'->0->>'userId'), null, 'Finance Order list redacts the direct user ID');
select lives_ok($$select public.admin_query_commerce_resource('9b000000-0000-4000-8000-000000000001', 'payments', null, 10, 'local', null, 'amount', 'desc')$$, 'Admin can query Payments');
select is((jsonb_array_length(public.admin_query_commerce_resource('9b000000-0000-4000-8000-000000000001', 'payments', null, 10, null, null, 'createdAt', 'desc')->'items')), 1, 'Payment query returns one safe payment summary');
select lives_ok($$select public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')$$, 'Admin can read one Order 360 aggregate');
select is((jsonb_array_length((public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')->'items'))), 2, 'Order 360 returns every OrderItem');
select ok((public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')->'items'->0->>'grantId') is not null, 'Order 360 links an item to its Grant');
select is((jsonb_array_length((public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')->'refunds'))), 1, 'Order 360 includes the item refund projection');
select is((jsonb_array_length((public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')->'exceptions'))), 1, 'Order 360 includes the payment exception projection');
select is((jsonb_array_length((public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')->'auditTimeline'))), 2, 'Order 360 includes order and item audit history');
select ok(not (public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')::text ilike '%payload_summary%' or public.admin_order_overview('9b000000-0000-4000-8000-000000000001', '9b300000-0000-4000-8000-000000000001')::text ilike '%external_payment_id%'), 'Order 360 excludes raw payment fields and payloads');

select * from finish();
rollback;
