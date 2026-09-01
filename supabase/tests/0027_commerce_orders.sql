begin;

select plan(38);

select has_table('platform', 'orders', 'orders table exists');
select has_table('platform', 'order_items', 'order_items table exists');
select col_is_pk('platform', 'orders', 'id', 'order id is the primary key');
select col_is_pk('platform', 'order_items', 'id', 'order item id is the primary key');
select col_not_null('platform', 'orders', 'customer_ref', 'customer reference is required');
select col_not_null('platform', 'order_items', 'sku_snapshot', 'SKU snapshot is required');
select ok((select relrowsecurity from pg_class where oid = 'platform.orders'::regclass), 'orders have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'platform.order_items'::regclass), 'order items have RLS enabled');
select has_index('platform', 'orders', 'orders_user_status_idx', 'orders are indexed by user and status');
select has_index('platform', 'order_items', 'order_items_order_idx', 'order items are indexed by order');
select has_index('platform', 'orders', 'orders_order_no_key', 'order numbers are unique');
select ok(not has_table_privilege('service_role', 'platform.orders', 'INSERT'), 'direct order inserts are denied');

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '98000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'commerce-order-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    select set_config('app.catalog_command', 'publish', true);
    update platform.product_versions
       set status = 'published', published_at = now()
     where id = '24000000-0000-4000-8000-000000000001';
    select set_config('app.catalog_command', '', true);
    update platform.product_prices
       set amount_minor = 1000, status = 'active'
     where id = '27000000-0000-4000-8000-000000000001';
    select set_config('app.catalog_command', 'set_current', true);
    update platform.products
       set current_version_id = '24000000-0000-4000-8000-000000000001', status = 'active'
     where id = '23000000-0000-4000-8000-000000000001';
    select set_config('app.catalog_command', '', true);
    insert into platform.orders
      (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values
      ('98100000-0000-4000-8000-000000000001', 'AH-P5-ORDER-001',
       '98000000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001',
       'USD', 1000, 'manual');
    insert into platform.order_items
      (id, order_id, product_id, product_version_id, product_price_id, quantity,
       unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('98300000-0000-4000-8000-000000000001', '98100000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
       '27000000-0000-4000-8000-000000000001', 1, 1000, 1000,
       'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}'::jsonb);
  $$,
  'published catalog and pending order fixtures can be created'
);

select is((select status from platform.orders where id = '98100000-0000-4000-8000-000000000001'), 'pending', 'orders default to pending');
select is((select quantity from platform.order_items where id = '98300000-0000-4000-8000-000000000001'), 1, 'entitlement order quantity is one');
select is((select sales_terms->>'label' from platform.order_items where id = '98300000-0000-4000-8000-000000000001'), 'AisenLens Lifetime', 'sales terms are snapshotted');
select is((select sku_snapshot from platform.order_items where id = '98300000-0000-4000-8000-000000000001'), 'AISENLENS_LIFETIME', 'SKU is snapshotted');
select is((select product_name from platform.order_items where id = '98300000-0000-4000-8000-000000000001'), 'AisenLens Lifetime', 'product name is snapshotted');
select is((select unit_amount from platform.order_items where id = '98300000-0000-4000-8000-000000000001'), 1000::bigint, 'unit amount is snapshotted');
select throws_ok($$insert into platform.orders (order_no, currency, amount_total, channel) values ('AH-P5-BAD-CURRENCY', 'usd', 0, 'manual')$$, '23514', null, 'currency must be uppercase');
select throws_ok($$insert into platform.orders (order_no, currency, amount_total, channel) values ('AH-P5-BAD-AMOUNT', 'USD', -1, 'manual')$$, '23514', null, 'order totals cannot be negative');
select throws_ok($$insert into platform.orders (order_no, status, currency, amount_total, channel) values ('AH-P5-BAD-STATUS', 'unknown', 'USD', 0, 'manual')$$, '23514', null, 'order status is enumerated');
select throws_ok($$insert into platform.orders (order_no, currency, amount_total, channel) values ('AH-P5-BAD-CHANNEL', 'USD', 0, 'Bad Provider')$$, '23514', null, 'payment channel is normalized');
select throws_ok($$insert into platform.order_items (order_id, product_id, product_version_id, product_price_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms) values ('98100000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 2, 1000, 2000, 'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}')$$, '23514', null, 'entitlement order quantity cannot exceed one');
select throws_ok($$insert into platform.order_items (order_id, product_id, product_version_id, product_price_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms) values ('98100000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 1, 1000, 999, 'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}')$$, '23514', null, 'item total must equal unit amount times quantity');
select throws_ok($$insert into platform.order_items (order_id, product_id, product_version_id, product_price_id, quantity, unit_amount, total_amount, refunded_amount, product_name, sku_snapshot, sales_terms) values ('98100000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 1, 1000, 1000, 1001, 'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}')$$, '23514', null, 'refunded amount cannot exceed item total');
select throws_ok($$insert into platform.order_items (order_id, product_id, product_version_id, product_price_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms, fulfillment_status) values ('98100000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 1, 1000, 1000, 'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}', 'unknown')$$, '23514', null, 'fulfillment status is enumerated');
select throws_ok($$insert into platform.order_items (order_id, product_id, product_version_id, product_price_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms) values ('98100000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 1, 1000, 1000, 'Wrong Name', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}')$$, '23514', null, 'catalog name snapshot is validated');
select throws_ok($$insert into platform.order_items (order_id, product_id, product_version_id, product_price_id, quantity, unit_amount, total_amount, product_name, sku_snapshot, sales_terms) values ('98100000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 1, 999, 999, 'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}')$$, '23514', null, 'price and item amount must match');
select lives_ok($$update platform.orders set status = 'paid', paid_at = now() where id = '98100000-0000-4000-8000-000000000001'$$, 'a pending order can enter paid with a matching item sum');
select throws_ok($$update platform.order_items set product_name = 'Changed after purchase' where id = '98300000-0000-4000-8000-000000000001'$$, '23514', null, 'paid order snapshots cannot be edited');
select lives_ok($$update platform.order_items set fulfillment_status = 'granted' where id = '98300000-0000-4000-8000-000000000001'$$, 'paid order fulfillment state remains mutable');
select throws_ok($$delete from platform.order_items where id = '98300000-0000-4000-8000-000000000001'$$, '23514', null, 'paid order items cannot be deleted');
select lives_ok(
  $$
    insert into platform.orders (id, order_no, customer_ref, currency, amount_total, channel)
    values ('98100000-0000-4000-8000-000000000002', 'AH-P5-ORDER-002', '98200000-0000-4000-8000-000000000002', 'USD', 2000, 'manual');
    insert into platform.order_items (id, order_id, product_id, product_version_id, product_price_id, unit_amount, total_amount, product_name, sku_snapshot, sales_terms)
    values
      ('98300000-0000-4000-8000-000000000002', '98100000-0000-4000-8000-000000000002', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 1000, 1000, 'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}'),
      ('98300000-0000-4000-8000-000000000003', '98100000-0000-4000-8000-000000000002', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 1000, 1000, 'AisenLens Lifetime', 'AISENLENS_LIFETIME', '{"label":"AisenLens Lifetime"}');
    update platform.orders set status = 'paid', paid_at = now() where id = '98100000-0000-4000-8000-000000000002';
  $$,
  'multi-item order totals are checked before payment'
);
select throws_ok($$update platform.orders set amount_total = 3000 where id = '98100000-0000-4000-8000-000000000002'$$, '23514', null, 'paid order total remains equal to item sum');
select lives_ok(
  $$
    insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous)
    values ('98000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'commerce-anonymize.local@aisenhub.test', 'not-used-by-this-test', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);
    insert into platform.orders (id, order_no, user_id, customer_ref, currency, amount_total, channel)
    values ('98100000-0000-4000-8000-000000000003', 'AH-P5-ORDER-003', '98000000-0000-4000-8000-000000000002', '98200000-0000-4000-8000-000000000003', 'USD', 0, 'manual');
    delete from auth.users where id = '98000000-0000-4000-8000-000000000002';
  $$,
  'an order user can be anonymized without deleting order history'
);
select is((select user_id from platform.orders where id = '98100000-0000-4000-8000-000000000003'), null::uuid, 'anonymization clears the direct user link');
select is((select customer_ref from platform.orders where id = '98100000-0000-4000-8000-000000000003'), '98200000-0000-4000-8000-000000000003'::uuid, 'customer reference survives anonymization');

select * from finish();
rollback;
