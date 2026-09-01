begin;

select plan(41);

select has_table('platform', 'redemption_batches', 'redemption batch table exists');
select col_is_pk('platform', 'redemption_batches', 'id', 'redemption batch id is the primary key');
select has_index(
  'platform',
  'redemption_batches',
  'redemption_batches_status_window_idx',
  'redemption batches have a status and validity-window index'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.redemption_batches'::regclass),
  'redemption batches have RLS enabled'
);
select has_table('platform', 'redemption_codes', 'redemption code table exists');
select has_index(
  'platform',
  'redemption_codes',
  'redemption_codes_code_hash_key',
  'redemption code hashes are unique'
);
select has_index(
  'platform',
  'redemption_codes',
  'redemption_codes_batch_status_idx',
  'redemption codes have a batch and status index'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.redemption_codes'::regclass),
  'redemption codes have RLS enabled'
);
select has_table('platform', 'redemptions', 'redemption receipt table exists');
select col_is_pk('platform', 'redemptions', 'id', 'redemption receipt id is the primary key');
select has_index(
  'platform',
  'redemptions',
  'redemptions_code_id_key',
  'one code can have at most one redemption'
);
select has_index(
  'platform',
  'redemptions',
  'redemptions_user_redeemed_at_idx',
  'redemptions have a per-user timeline index'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.redemptions'::regclass),
  'redemptions have RLS enabled'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'platform'
      and table_name in ('redemption_codes', 'redemptions')
      and column_name in ('code', 'plaintext_code', 'raw_code')
  ),
  'redemption storage has no plaintext code column'
);
select ok(
  not has_table_privilege('anon', 'platform.redemption_batches', 'SELECT'),
  'anon cannot read redemption batches directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.redemption_codes', 'SELECT'),
  'authenticated cannot read redemption codes directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.redemptions', 'INSERT'),
  'service_role cannot insert redemption receipts directly'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('61000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'redemption-schema-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('61000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'redemption-schema-other.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);

    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, source, created_by)
    values
      ('62000000-0000-4000-8000-000000000001', 'Schema Test Batch',
       '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
       'AH-TEST', 10, 2, 'test', '61000000-0000-4000-8000-000000000001'),
      ('62000000-0000-4000-8000-000000000002', 'Schema Test Batch Two',
       '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
       'AH-TEST2', 10, 2, 'test', '61000000-0000-4000-8000-000000000001');
  $$,
  'redemption schema users and batches can be created'
);

select lives_ok(
  $$
    insert into platform.redemption_codes
      (id, batch_id, code_hash, code_hint, pepper_version)
    values
      ('63000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000001', repeat('a', 64), 'AH-TEST-AAAA', 1),
      ('63000000-0000-4000-8000-000000000002', '62000000-0000-4000-8000-000000000001', repeat('b', 64), 'AH-TEST-BBBB', 1),
      ('63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000001', repeat('c', 64), 'AH-TEST-CCCC', 1),
      ('63000000-0000-4000-8000-000000000004', '62000000-0000-4000-8000-000000000001', repeat('d', 64), 'AH-TEST-DDDD', 1);
  $$,
  'issued code fixtures store only digests and hints'
);

select lives_ok(
  $$
    insert into platform.idempotency_records
      (id, scope, actor_key, idempotency_key, request_hash, expires_at)
    values
      ('65000000-0000-4000-8000-000000000001', 'redemption', 'user:61000000-0000-4000-8000-000000000001', 'schema-1', 'hash-1', now() + interval '1 day'),
      ('65000000-0000-4000-8000-000000000002', 'redemption', 'user:61000000-0000-4000-8000-000000000001', 'schema-2', 'hash-2', now() + interval '1 day'),
      ('65000000-0000-4000-8000-000000000003', 'redemption', 'user:61000000-0000-4000-8000-000000000001', 'schema-3', 'hash-3', now() + interval '1 day'),
      ('65000000-0000-4000-8000-000000000004', 'redemption', 'user:61000000-0000-4000-8000-000000000002', 'schema-4', 'hash-4', now() + interval '1 day');

    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id)
    values
      ('64000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'redemption', '66000000-0000-4000-8000-000000000001'),
      ('64000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'redemption', '66000000-0000-4000-8000-000000000002'),
      ('64000000-0000-4000-8000-000000000003', '61000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'redemption', '66000000-0000-4000-8000-000000000003'),
      ('64000000-0000-4000-8000-000000000004', '61000000-0000-4000-8000-000000000002', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'redemption', '66000000-0000-4000-8000-000000000004');
  $$,
  'redemption grants and idempotency records can be prepared'
);

select lives_ok(
  $$
    insert into platform.redemptions
      (id, code_id, batch_id, user_id, grant_id, idempotency_record_id, ip_hash)
    values
      ('66000000-0000-4000-8000-000000000001', '63000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', '64000000-0000-4000-8000-000000000001', '65000000-0000-4000-8000-000000000001', 'ip-hash-1');
  $$,
  'a matching code, batch, user, grant, and idempotency record form one receipt'
);
select throws_ok(
  $$
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, resolution_mode, code_prefix, quantity, per_user_limit, source, created_by)
    values ('62000000-0000-4000-8000-000000000010', 'Rolling', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'rolling', 'AH-ROLL', 1, 1, 'test', '61000000-0000-4000-8000-000000000001');
  $$,
  '23514', null,
  'rolling redemption resolution is rejected'
);
select throws_ok(
  $$
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, source, created_by)
    values ('62000000-0000-4000-8000-000000000011', 'Bad Prefix', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'ah bad', 1, 1, 'test', '61000000-0000-4000-8000-000000000001');
  $$,
  '23514', null,
  'redemption prefixes must be normalized safe tokens'
);
select throws_ok(
  $$
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, source, created_by)
    values ('62000000-0000-4000-8000-000000000012', 'Zero Quantity', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'AH-ZERO', 0, 1, 'test', '61000000-0000-4000-8000-000000000001');
  $$,
  '23514', null,
  'redemption quantity must be positive'
);
select throws_ok(
  $$
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, source, created_by)
    values ('62000000-0000-4000-8000-000000000013', 'Too Many Per User', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'AH-LIMIT', 2, 3, 'test', '61000000-0000-4000-8000-000000000001');
  $$,
  '23514', null,
  'per-user limit cannot exceed batch quantity'
);
select throws_ok(
  $$
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, starts_at, expires_at, source, created_by)
    values ('62000000-0000-4000-8000-000000000014', 'Bad Window', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'AH-WINDOW', 1, 1, now(), now() - interval '1 minute', 'test', '61000000-0000-4000-8000-000000000001');
  $$,
  '23514', null,
  'redemption batch expiry must follow its start'
);
select throws_ok(
  $$
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, status, source, created_by)
    values ('62000000-0000-4000-8000-000000000015', 'Bad Status', '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'AH-STATUS', 1, 1, 'redeemed', 'test', '61000000-0000-4000-8000-000000000001');
  $$,
  '23514', null,
  'unknown redemption batch statuses are rejected'
);
select throws_ok(
  $$
    insert into platform.redemption_codes
      (id, batch_id, code_hash, code_hint, pepper_version)
    values ('63000000-0000-4000-8000-000000000010', '62000000-0000-4000-8000-000000000001', 'not-a-digest', 'AH-BAD', 1);
  $$,
  '23514', null,
  'code hashes must be lowercase SHA-256-shaped digests'
);
select throws_ok(
  $$
    insert into platform.redemption_codes
      (id, batch_id, code_hash, code_hint, pepper_version)
    values ('63000000-0000-4000-8000-000000000011', '62000000-0000-4000-8000-000000000001', repeat('e', 64), 'AH-PEPPER', 0);
  $$,
  '23514', null,
  'pepper versions must be positive'
);
select throws_ok(
  $$
    update platform.redemption_codes
    set status = 'redeemed', redeemed_at = null
    where id = '63000000-0000-4000-8000-000000000002';
  $$,
  '23514', null,
  'redeemed codes require a redemption timestamp'
);
select throws_ok(
  $$
    insert into platform.redemption_codes
      (id, batch_id, code_hash, code_hint, pepper_version)
    values ('63000000-0000-4000-8000-000000000012', '62000000-0000-4000-8000-000000000001', repeat('a', 64), 'AH-DUPLICATE', 1);
  $$,
  '23505', null,
  'the same code digest cannot be issued twice'
);
select throws_ok(
  $$
    update platform.redemption_codes
    set code_hint = 'AH-TAMPERED'
    where id = '63000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'redemption code identity cannot be edited'
);
select throws_ok(
  $$
    delete from platform.redemption_codes
    where id = '63000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'redemption code history cannot be deleted'
);
select lives_ok(
  $$
    update platform.redemption_codes
    set status = 'redeemed', redeemed_at = now()
    where id = '63000000-0000-4000-8000-000000000001';
  $$,
  'issued codes can transition to redeemed once'
);
select throws_ok(
  $$
    insert into platform.redemptions
      (id, code_id, batch_id, user_id, grant_id, idempotency_record_id)
    values ('66000000-0000-4000-8000-000000000002', '63000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', '64000000-0000-4000-8000-000000000002', '65000000-0000-4000-8000-000000000002');
  $$,
  '23505', null,
  'one code cannot create a second redemption'
);
select throws_ok(
  $$
    insert into platform.redemptions
      (id, code_id, batch_id, user_id, grant_id, idempotency_record_id)
    values ('66000000-0000-4000-8000-000000000003', '63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000001', '64000000-0000-4000-8000-000000000003', '65000000-0000-4000-8000-000000000003');
  $$,
  '23514', null,
  'redemption code and batch must match'
);
select throws_ok(
  $$
    insert into platform.redemptions
      (id, code_id, batch_id, user_id, grant_id, idempotency_record_id)
    values ('66000000-0000-4000-8000-000000000004', '63000000-0000-4000-8000-000000000004', '62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', '64000000-0000-4000-8000-000000000004', '65000000-0000-4000-8000-000000000004');
  $$,
  '23514', null,
  'redemption user and entitlement grant must match'
);
select throws_ok(
  $$
    insert into platform.redemptions
      (id, code_id, batch_id, user_id, grant_id, idempotency_record_id)
    values ('66000000-0000-4000-8000-000000000003', '63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', '64000000-0000-4000-8000-000000000003', '65000000-0000-4000-8000-000000000001');
  $$,
  '23505', null,
  'one idempotency record cannot back two redemptions'
);
select is(
  (select count(*)::integer from platform.redemptions),
  1,
  'failed redemption inserts leave no extra receipts'
);
select throws_ok(
  $$
    update platform.redemptions
    set ip_hash = 'tampered'
    where id = '66000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'redemption receipts cannot be edited'
);
select throws_ok(
  $$
    delete from platform.redemptions
    where id = '66000000-0000-4000-8000-000000000001';
  $$,
  '23514', null,
  'redemption receipts cannot be deleted'
);

select * from finish();
rollback;
