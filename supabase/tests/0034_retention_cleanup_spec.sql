begin;

select plan(25);

select has_function(
  'public',
  'run_retention_cleanup',
  array['timestamp with time zone', 'timestamp with time zone', 'timestamp with time zone', 'integer', 'boolean'],
  'retention cleanup function exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.run_retention_cleanup(timestamptz,timestamptz,timestamptz,integer,boolean)'::regprocedure),
  true,
  'retention cleanup is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.run_retention_cleanup(timestamptz,timestamptz,timestamptz,integer,boolean)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[],
  'retention cleanup pins search_path'
);
select ok(
  has_function_privilege('service_role', 'public.run_retention_cleanup(timestamptz,timestamptz,timestamptz,integer,boolean)', 'EXECUTE'),
  'service_role can run retention cleanup'
);
select ok(
  not has_function_privilege('anon', 'public.run_retention_cleanup(timestamptz,timestamptz,timestamptz,integer,boolean)', 'EXECUTE'),
  'anon cannot run retention cleanup'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '9e000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'retention-cleanup.local@aisenhub.test', 'not-used', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.products (id, sku, name, billing_type, status)
    values ('9e010000-0000-4000-8000-000000000001', 'RETENTION_CLEANUP_PRODUCT', 'Retention Cleanup Product', 'one_time', 'draft');
    insert into platform.product_versions (id, product_id, version, status, published_at, sales_terms)
    values ('9e020000-0000-4000-8000-000000000001', '9e010000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb);
    insert into platform.orders
      (id, order_no, user_id, customer_ref, currency, amount_total, channel, status)
    values
      ('9e030000-0000-4000-8000-000000000001', 'AH-P6-RETENTION-001', '9e000000-0000-4000-8000-000000000001',
       '9e040000-0000-4000-8000-000000000001', 'USD', 0, 'local', 'pending');
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id, status)
    values
      ('9e050000-0000-4000-8000-000000000001', '9e000000-0000-4000-8000-000000000001',
       '9e010000-0000-4000-8000-000000000001', '9e020000-0000-4000-8000-000000000001',
       'admin', '9e060000-0000-4000-8000-000000000001', 'active');
    insert into platform.idempotency_records
      (id, scope, actor_key, idempotency_key, request_hash, status, response_status, response_body, expires_at, created_at)
    values
      ('9e080000-0000-4000-8000-000000000001', 'retention.test', 'user:retention', 'expired-free', 'hash-free', 'completed', 200,
       '{"email":"must be scrubbed"}'::jsonb, now() - interval '2 days', now() - interval '3 days'),
      ('9e080000-0000-4000-8000-000000000002', 'retention.test', 'user:retention', 'expired-referenced', 'hash-referenced', 'completed', 200,
       '{"email":"must be scrubbed too"}'::jsonb, now() - interval '2 days', now() - interval '3 days'),
      ('9e080000-0000-4000-8000-000000000003', 'retention.test', 'user:retention', 'fresh', 'hash-fresh', 'completed', 200,
       '{"email":"must remain"}'::jsonb, now() + interval '2 days', now());
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, source, created_by, status)
    values
      ('9e090000-0000-4000-8000-000000000001', 'Retention Cleanup Batch',
       '9e010000-0000-4000-8000-000000000001', '9e020000-0000-4000-8000-000000000001',
       'RETENTION', 1, 'local', '9e000000-0000-4000-8000-000000000001', 'active');
    insert into platform.redemption_codes
      (id, batch_id, code_hash, code_hint, pepper_version, status, redeemed_at)
    values
      ('9e0a0000-0000-4000-8000-000000000001', '9e090000-0000-4000-8000-000000000001',
       'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 'RETENTION-****', 1, 'redeemed', now() - interval '2 days');
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id, status)
    values
      ('9e0b0000-0000-4000-8000-000000000001', '9e000000-0000-4000-8000-000000000001',
       '9e010000-0000-4000-8000-000000000001', '9e020000-0000-4000-8000-000000000001',
       'redemption', '9e0c0000-0000-4000-8000-000000000001', 'active');
    insert into platform.redemptions
      (id, code_id, batch_id, user_id, grant_id, idempotency_record_id, ip_hash, redeemed_at)
    values
      ('9e0c0000-0000-4000-8000-000000000001', '9e0a0000-0000-4000-8000-000000000001',
       '9e090000-0000-4000-8000-000000000001', '9e000000-0000-4000-8000-000000000001',
       '9e0b0000-0000-4000-8000-000000000001', '9e080000-0000-4000-8000-000000000002',
       'expired-redemption-ip', now() - interval '2 days');
    insert into platform.audit_logs
      (id, actor_type, actor_id, action, target_type, target_id, reason, ip_hash, before_summary, after_summary, created_at)
    values
      ('9e0d0000-0000-4000-8000-000000000001', 'user', '9e000000-0000-4000-8000-000000000001',
       'retention.old.context', 'user', '9e000000-0000-4000-8000-000000000001', 'old context', 'expired-audit-ip', '{}'::jsonb, '{}'::jsonb,
       now() - interval '2 days'),
      ('9e0d0000-0000-4000-8000-000000000002', 'user', '9e000000-0000-4000-8000-000000000001',
       'retention.fresh.context', 'user', '9e000000-0000-4000-8000-000000000001', 'fresh context', 'fresh-audit-ip', '{}'::jsonb, '{}'::jsonb,
       now());
  $$,
  'retention fixtures include protected facts and cleanup candidates'
);

set local role service_role;
select is(
  public.run_retention_cleanup(
    now() - interval '1 hour', now() - interval '1 hour', now() - interval '1 hour', 10, true
  ) ->> 'dryRun',
  'true',
  'dry-run reports without mutating data'
);
set local role postgres;
select is((select ip_hash from platform.redemptions where id = '9e0c0000-0000-4000-8000-000000000001'), 'expired-redemption-ip', 'dry-run retains redemption IP hash');
select is((select response_body ->> 'email' from platform.idempotency_records where id = '9e080000-0000-4000-8000-000000000001'), 'must be scrubbed', 'dry-run retains idempotency response');

set local role service_role;
select is(
  public.run_retention_cleanup(
    now() - interval '1 hour', now() - interval '1 hour', now() - interval '1 hour', 10, false
  ) ->> 'sessionCount',
  '0',
  'cleanup reports no retired platform sessions'
);
set local role postgres;
select is((select ip_hash from platform.redemptions where id = '9e0c0000-0000-4000-8000-000000000001'), null, 'expired redemption IP hash is cleared');
select is((select ip_hash from platform.audit_logs where id = '9e0d0000-0000-4000-8000-000000000001'), null, 'expired audit IP hash is cleared');
select is((select ip_hash from platform.audit_logs where id = '9e0d0000-0000-4000-8000-000000000002'), 'fresh-audit-ip', 'fresh audit IP hash is protected');
select is((select count(*)::integer from platform.idempotency_records where id = '9e080000-0000-4000-8000-000000000001'), 0, 'unreferenced expired idempotency record is deleted');
select is((select response_body from platform.idempotency_records where id = '9e080000-0000-4000-8000-000000000002'), null, 'referenced expired idempotency response is scrubbed');
select is((select count(*)::integer from platform.redemptions where id = '9e0c0000-0000-4000-8000-000000000001'), 1, 'redemption fact is retained');
select is((select status from platform.entitlement_grants where id = '9e0b0000-0000-4000-8000-000000000001'), 'active', 'active entitlement fact is untouched');
select is((select status from platform.entitlement_grants where id = '9e050000-0000-4000-8000-000000000001'), 'active', 'unrelated entitlement fact is untouched');
select is((select status from platform.orders where id = '9e030000-0000-4000-8000-000000000001'), 'pending', 'order fact is untouched');
select is((select response_body ->> 'email' from platform.idempotency_records where id = '9e080000-0000-4000-8000-000000000003'), 'must remain', 'fresh idempotency response is protected');

set local role service_role;
select is(
  public.run_retention_cleanup(
    now() - interval '1 hour', now() - interval '1 hour', now() - interval '1 hour', 10, false
  ) ->> 'sessionCount',
  '0',
  'repeated cleanup is idempotent'
);
set local role postgres;
select is((select ip_hash from platform.audit_logs where id = '9e0d0000-0000-4000-8000-000000000001'), null, 'repeated cleanup does not restore scrubbed audit context');
select is((select count(*)::integer from platform.audit_logs where id = '9e0d0000-0000-4000-8000-000000000001'), 1, 'cleanup does not delete audit facts');
select throws_ok(
  $$select public.run_retention_cleanup(now(), now(), now(), 0, false)$$,
  '22023', null,
  'cleanup rejects an unbounded batch size'
);
select throws_ok(
  $$select public.run_retention_cleanup(null, now(), now(), 10, false)$$,
  '22023', null,
  'cleanup requires explicit cutoffs'
);

select * from finish();
rollback;
