begin;

select plan(38);

select has_table('platform', 'payments', 'payments table exists');
select has_table('platform', 'payment_events', 'payment events table exists');
select col_is_pk('platform', 'payments', 'id', 'payment id is the primary key');
select col_is_pk('platform', 'payment_events', 'id', 'payment event id is the primary key');
select col_not_null('platform', 'payments', 'order_id', 'payments require an order');
select col_not_null('platform', 'payments', 'provider', 'payments require a provider');
select col_not_null('platform', 'payment_events', 'order_id', 'payment events retain their order');
select col_not_null('platform', 'payment_events', 'payload_summary', 'payment events retain only a summary');
select ok((select relrowsecurity from pg_class where oid = 'platform.payments'::regclass), 'payments have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'platform.payment_events'::regclass), 'payment events have RLS enabled');
select has_index('platform', 'payments', 'payments_provider_external_id_key', 'payment identities are unique per provider');
select has_index('platform', 'payment_events', 'payment_events_provider_external_id_key', 'external events are unique per provider');
select has_index('platform', 'payment_events', 'payment_events_payment_created_idx', 'events are indexed by payment');
select ok(not has_table_privilege('service_role', 'platform.payments', 'INSERT'), 'direct payment inserts are denied');
select ok(not has_table_privilege('service_role', 'platform.payment_events', 'INSERT'), 'direct event inserts are denied');
select ok(not exists (
  select 1 from information_schema.columns
   where table_schema = 'platform'
     and table_name in ('payments', 'payment_events')
     and column_name in ('raw_payload', 'card_number', 'cvv', 'cvc', 'authorization', 'access_token', 'secret')
), 'payment tables expose no credential columns');

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '98400000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'commerce-payment-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.orders
      (id, order_no, customer_ref, currency, amount_total, channel)
    values
      ('98500000-0000-4000-8000-000000000001', 'AH-P5-PAYMENT-001', '98600000-0000-4000-8000-000000000001', 'USD', 1000, 'manual'),
      ('98500000-0000-4000-8000-000000000002', 'AH-P5-PAYMENT-002', '98600000-0000-4000-8000-000000000002', 'USD', 2000, 'manual');
    insert into platform.payments
      (id, order_id, provider, external_payment_id, currency, amount)
    values
      ('98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'manual', 'manual-pay-001', 'USD', 1000),
      ('98700000-0000-4000-8000-000000000002', '98500000-0000-4000-8000-000000000002', 'manual', 'manual-pay-002', 'USD', 2000);
    insert into platform.payment_events
      (id, payment_id, order_id, provider, external_event_id, event_type, currency, amount, payload_summary, occurred_at)
    values
      ('98800000-0000-4000-8000-000000000001', '98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'manual', 'manual-event-001', 'payment.succeeded', 'USD', 1000, '{"provider_status":"approved"}', now() - interval '1 minute');
  $$,
  'payment and minimized event fixtures can be created'
);

select is((select status from platform.payments where id = '98700000-0000-4000-8000-000000000001'), 'pending', 'payments default to pending');
select is((select status from platform.payment_events where id = '98800000-0000-4000-8000-000000000001'), 'received', 'events default to received');
select is((select payload_summary->>'provider_status' from platform.payment_events where id = '98800000-0000-4000-8000-000000000001'), 'approved', 'event payload is a safe summary');
select throws_ok($$insert into platform.payments (order_id, provider, currency, amount) values ('98500000-0000-4000-8000-000000000001', 'manual', 'USD', 999)$$, '23514', null, 'payment amount must match the order');
select throws_ok($$insert into platform.payments (order_id, provider, currency, amount) values ('98500000-0000-4000-8000-000000000001', 'manual', 'EUR', 1000)$$, '23514', null, 'payment currency must match the order');
select throws_ok($$insert into platform.payments (order_id, provider, currency, amount) values ('98500000-0000-4000-8000-000000000001', 'manual', 'USD', -1)$$, '23514', null, 'payment amount cannot be negative');
select throws_ok($$insert into platform.payments (order_id, provider, currency, amount) values ('98500000-0000-4000-8000-000000000001', 'Bad Provider', 'USD', 1000)$$, '23514', null, 'payment provider is normalized');
select throws_ok($$insert into platform.payments (order_id, provider, external_payment_id, currency, amount) values ('98500000-0000-4000-8000-000000000001', 'manual', 'manual-pay-001', 'USD', 1000)$$, '23505', null, 'provider payment identity is unique');
select throws_ok($$update platform.payments set amount = 999 where id = '98700000-0000-4000-8000-000000000001'$$, '23514', null, 'payment identity amount is immutable');
select throws_ok($$insert into platform.payments (order_id, provider, currency, amount, status) values ('98500000-0000-4000-8000-000000000001', 'manual', 'USD', 1000, 'unknown')$$, '23514', null, 'payment status is enumerated');
select throws_ok($$insert into platform.payment_events (payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at) values ('98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000002', 'manual', 'manual-event-cross-order', 'payment.succeeded', 'USD', 1000, now())$$, '23514', null, 'event order must match its payment');
select throws_ok($$insert into platform.payment_events (payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at) values ('98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'other_provider', 'other-event-001', 'payment.succeeded', 'USD', 1000, now())$$, '23514', null, 'event provider must match its payment');
select throws_ok($$insert into platform.payment_events (payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at) values ('98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'manual', 'manual-event-bad-amount', 'payment.succeeded', 'USD', 999, now())$$, '23514', null, 'event amount must match its payment');
select throws_ok($$insert into platform.payment_events (payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at) values ('98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'manual', 'manual-event-bad-currency', 'payment.succeeded', 'EUR', 1000, now())$$, '23514', null, 'event currency must match its payment');
select throws_ok($$insert into platform.payment_events (payment_id, order_id, provider, external_event_id, event_type, currency, amount, occurred_at) values ('98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'manual', 'manual-event-001', 'payment.succeeded', 'USD', 1000, now())$$, '23505', null, 'external event identity is unique');
select throws_ok($$insert into platform.payment_events (payment_id, order_id, provider, external_event_id, event_type, currency, amount, payload_summary, occurred_at) values ('98700000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'manual', 'manual-event-secret', 'payment.succeeded', 'USD', 1000, '{"nested":{"access_token":"must-not-persist"}}', now())$$, '23514', null, 'event summaries reject nested credentials');
select lives_ok($$update platform.payments set status = 'succeeded', paid_at = now() where id = '98700000-0000-4000-8000-000000000001'$$, 'pending payments can become succeeded with a timestamp');
select throws_ok($$update platform.payments set status = 'succeeded' where id = '98700000-0000-4000-8000-000000000002'$$, '23514', null, 'succeeded payments require paid_at');
select lives_ok($$update platform.payment_events set status = 'processed', processed_at = now() where id = '98800000-0000-4000-8000-000000000001'$$, 'received events can become processed');
select throws_ok($$update platform.payment_events set status = 'processed', processed_at = null where id = '98800000-0000-4000-8000-000000000001'$$, '23514', null, 'processed events require processed_at');
select throws_ok($$update platform.payment_events set order_id = '98500000-0000-4000-8000-000000000002' where id = '98800000-0000-4000-8000-000000000001'$$, '23514', null, 'event identity cannot be reassigned');

select * from finish();
rollback;
