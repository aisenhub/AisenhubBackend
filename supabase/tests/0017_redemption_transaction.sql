begin;

select plan(36);

select has_function(
  'public',
  'redeem_code',
  ARRAY['text', 'uuid', 'text', 'text', 'text'],
  'atomic redemption function exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.redeem_code(text,uuid,text,text,text)'::regprocedure),
  'redemption function is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']::text[]
   from pg_proc
   where oid = 'public.redeem_code(text,uuid,text,text,text)'::regprocedure),
  'redemption function fixes its search_path'
);
select ok(
  not has_function_privilege('anon', 'public.redeem_code(text,uuid,text,text,text)', 'EXECUTE'),
  'anon cannot invoke redemption directly'
);
select ok(
  not has_function_privilege('authenticated', 'public.redeem_code(text,uuid,text,text,text)', 'EXECUTE'),
  'authenticated cannot invoke redemption directly'
);
select ok(
  has_function_privilege('service_role', 'public.redeem_code(text,uuid,text,text,text)', 'EXECUTE'),
  'service_role can invoke redemption through the server API'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('71000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'redemption-tx-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('71000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'redemption-tx-other.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);

    insert into platform.products (id, sku, name, billing_type)
    values ('72000000-0000-4000-8000-000000000001', 'REDEEM_TX_PRODUCT', 'Redemption Transaction Product', 'one_time');
    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values ('73000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb);

    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, status, starts_at, expires_at, source, created_by)
    values
      ('74000000-0000-4000-8000-000000000001', 'Active Batch', '72000000-0000-4000-8000-000000000001', '73000000-0000-4000-8000-000000000001', 'AH-TX', 10, 2, 'active', now() - interval '1 hour', null, 'test', '71000000-0000-4000-8000-000000000001'),
      ('74000000-0000-4000-8000-000000000002', 'Paused Batch', '72000000-0000-4000-8000-000000000001', '73000000-0000-4000-8000-000000000001', 'AH-PAUSED', 1, 1, 'paused', now() - interval '1 hour', null, 'test', '71000000-0000-4000-8000-000000000001'),
      ('74000000-0000-4000-8000-000000000003', 'Closed Batch', '72000000-0000-4000-8000-000000000001', '73000000-0000-4000-8000-000000000001', 'AH-CLOSED', 1, 1, 'closed', now() - interval '1 hour', null, 'test', '71000000-0000-4000-8000-000000000001'),
      ('74000000-0000-4000-8000-000000000004', 'Future Batch', '72000000-0000-4000-8000-000000000001', '73000000-0000-4000-8000-000000000001', 'AH-FUTURE', 1, 1, 'active', now() + interval '1 hour', null, 'test', '71000000-0000-4000-8000-000000000001'),
      ('74000000-0000-4000-8000-000000000005', 'Expired Batch', '72000000-0000-4000-8000-000000000001', '73000000-0000-4000-8000-000000000001', 'AH-EXPIRED', 1, 1, 'active', now() - interval '2 hours', now() - interval '1 hour', 'test', '71000000-0000-4000-8000-000000000001'),
      ('74000000-0000-4000-8000-000000000006', 'Limit Batch', '72000000-0000-4000-8000-000000000001', '73000000-0000-4000-8000-000000000001', 'AH-LIMIT', 2, 1, 'active', now() - interval '1 hour', null, 'test', '71000000-0000-4000-8000-000000000001');

    insert into platform.redemption_codes (id, batch_id, code_hash, code_hint, pepper_version)
    values
      ('75000000-0000-4000-8000-000000000001', '74000000-0000-4000-8000-000000000001', repeat('a', 64), 'AH-TX-AAAA', 1),
      ('75000000-0000-4000-8000-000000000002', '74000000-0000-4000-8000-000000000001', repeat('b', 64), 'AH-TX-BBBB', 1),
      ('75000000-0000-4000-8000-000000000003', '74000000-0000-4000-8000-000000000002', repeat('c', 64), 'AH-PAUSED-CCCC', 1),
      ('75000000-0000-4000-8000-000000000004', '74000000-0000-4000-8000-000000000003', repeat('d', 64), 'AH-CLOSED-DDDD', 1),
      ('75000000-0000-4000-8000-000000000005', '74000000-0000-4000-8000-000000000004', repeat('e', 64), 'AH-FUTURE-EEEE', 1),
      ('75000000-0000-4000-8000-000000000006', '74000000-0000-4000-8000-000000000005', repeat('f', 64), 'AH-EXPIRED-FFFF', 1),
      ('75000000-0000-4000-8000-000000000007', '74000000-0000-4000-8000-000000000006', repeat('1', 64), 'AH-LIMIT-1111', 1),
      ('75000000-0000-4000-8000-000000000008', '74000000-0000-4000-8000-000000000006', repeat('2', 64), 'AH-LIMIT-2222', 1);
  $$,
  'redemption transaction fixtures can be created'
);

set local role service_role;
select lives_ok(
  $$
    create temporary table redemption_first on commit drop as
    select * from public.redeem_code(
      repeat('a', 64),
      '71000000-0000-4000-8000-000000000001',
      'tx-request-1',
      'tx-payload-1',
      'ip-hash-1'
    );
  $$,
  'a valid code is redeemed atomically'
);
select is(
  (select status from redemption_first),
  'redeemed',
  'successful redemption returns redeemed status'
);
set local role postgres;
select is(
  (select status from platform.redemption_codes where id = '75000000-0000-4000-8000-000000000001'),
  'redeemed',
  'successful redemption marks the code redeemed'
);
select is(
  (select count(*)::integer from platform.redemptions where code_id = '75000000-0000-4000-8000-000000000001'),
  1,
  'one redemption receipt is created'
);
select is(
  (select count(*)::integer from platform.entitlement_grants where source_type = 'redemption'),
  1,
  'one redemption entitlement grant is created'
);
select is(
  (select count(*)::integer from platform.audit_logs where action = 'redemptions.redeem'),
  1,
  'successful redemption writes an audit event'
);
select is(
  (select count(*)::integer from platform.idempotency_records where status = 'completed'),
  1,
  'successful redemption completes its idempotency record'
);

set local role service_role;
select lives_ok(
  $$
    create temporary table redemption_retry on commit drop as
    select * from public.redeem_code(repeat('a', 64), '71000000-0000-4000-8000-000000000001', 'tx-request-1', 'tx-payload-1');
  $$,
  'same request retry returns the saved result'
);
select is(
  (select redemption_id from redemption_retry),
  (select redemption_id from redemption_first),
  'same request retry returns the same redemption'
);
select lives_ok(
  $$
    create temporary table redemption_same_code_retry on commit drop as
    select * from public.redeem_code(repeat('a', 64), '71000000-0000-4000-8000-000000000001', 'tx-request-2', 'tx-payload-2');
  $$,
  'same user can safely resubmit a redeemed code'
);
select is(
  (select grant_id from redemption_same_code_retry),
  (select grant_id from redemption_first),
  'same user code retry does not create a second grant'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('b', 64), '71000000-0000-4000-8000-000000000001', 'tx-request-1', 'different-payload'); $$,
  '23505', null,
  'same idempotency key with a different request hash is rejected'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('a', 64), '71000000-0000-4000-8000-000000000002', 'tx-other-user', 'tx-other-payload'); $$,
  'P0001', null,
  'a redeemed code is unavailable to another user'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('c', 64), '71000000-0000-4000-8000-000000000001', 'tx-paused', 'tx-paused-payload'); $$,
  'P0001', null,
  'paused batches cannot be redeemed'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('d', 64), '71000000-0000-4000-8000-000000000001', 'tx-closed', 'tx-closed-payload'); $$,
  'P0001', null,
  'closed batches cannot be redeemed'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('e', 64), '71000000-0000-4000-8000-000000000001', 'tx-future', 'tx-future-payload'); $$,
  'P0001', null,
  'future batches cannot be redeemed'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('f', 64), '71000000-0000-4000-8000-000000000001', 'tx-expired', 'tx-expired-payload'); $$,
  'P0001', null,
  'expired batches cannot be redeemed'
);
select lives_ok(
  $$ select * from public.redeem_code(repeat('1', 64), '71000000-0000-4000-8000-000000000001', 'tx-limit-1', 'tx-limit-payload-1'); $$,
  'the first redemption within a user limit succeeds'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('2', 64), '71000000-0000-4000-8000-000000000001', 'tx-limit-2', 'tx-limit-payload-2'); $$,
  'P0001', null,
  'per-user redemption limits are enforced'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('9', 64), '71000000-0000-4000-8000-000000000001', 'tx-missing', 'tx-missing-payload'); $$,
  'P0002', null,
  'unknown code hashes are unavailable'
);
select throws_ok(
  $$ select * from public.redeem_code('not-a-hash', '71000000-0000-4000-8000-000000000001', 'tx-invalid', 'tx-invalid-payload'); $$,
  '23514', null,
  'invalid code hashes are rejected without lookup'
);
select throws_ok(
  $$ select * from public.redeem_code(repeat('a', 64), null, 'tx-null-user', 'tx-null-user-payload'); $$,
  '23514', null,
  'null users are rejected'
);

set local role postgres;
select is(
  (select count(*)::integer from platform.redemptions),
  2,
  'failed claims leave no extra redemption receipts'
);
select is(
  (select count(*)::integer from platform.entitlement_grants where source_type = 'redemption'),
  2,
  'failed claims leave no orphan entitlement grants'
);
select is(
  (select count(*)::integer from platform.audit_logs where action = 'redemptions.redeem'),
  2,
  'failed claims leave no orphan redemption audits'
);
select is(
  (select count(*)::integer from platform.idempotency_records where status = 'completed'),
  3,
  'only successful or replayed claims complete idempotency records'
);
select is(
  (select status from platform.redemption_codes where id = '75000000-0000-4000-8000-000000000002'),
  'issued',
  'failed idempotent retry leaves the unused code issued'
);
select is(
  (select status from platform.redemption_codes where id = '75000000-0000-4000-8000-000000000003'),
  'issued',
  'paused batch failure leaves its code issued'
);
select is(
  (select status from platform.redemption_codes where id = '75000000-0000-4000-8000-000000000008'),
  'issued',
  'per-user limit failure leaves its second code issued'
);

select * from finish();
rollback;
