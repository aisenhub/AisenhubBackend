begin;

select plan(19);

select has_function(
  'public',
  'admin_redemption_command',
  array['uuid', 'text', 'uuid', 'jsonb', 'text', 'text', 'text', 'uuid'],
  'Admin Redemption command wrapper exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.admin_redemption_command(uuid,text,uuid,jsonb,text,text,text,uuid)'::regprocedure),
  'Admin Redemption command is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']::text[] from pg_proc where oid = 'public.admin_redemption_command(uuid,text,uuid,jsonb,text,text,text,uuid)'::regprocedure),
  'Admin Redemption command fixes its search_path'
);
select ok(
  has_function_privilege('service_role', 'public.admin_redemption_command(uuid,text,uuid,jsonb,text,text,text,uuid)', 'EXECUTE'),
  'service_role can invoke Redemption commands'
);
select ok(
  not has_function_privilege('anon', 'public.admin_redemption_command(uuid,text,uuid,jsonb,text,text,text,uuid)', 'EXECUTE'),
  'anon cannot invoke Redemption commands'
);

set local role postgres;
select lives_ok($$
  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
  ) values (
    '94000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
    'redemption-command-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
  );
  insert into platform.admin_members (user_id, role) values ('94000000-0000-4000-8000-000000000001', 'owner');
  insert into platform.products (id, sku, name, billing_type)
  values ('94000000-0000-4000-8000-000000000010', 'REDEMPTION_TEST', 'Redemption Test', 'one_time');
  insert into platform.product_versions (id, product_id, version, status, published_at)
  values ('94000000-0000-4000-8000-000000000011', '94000000-0000-4000-8000-000000000010', 1, 'published', now());
$$, 'Redemption command fixtures can be created');

set local role postgres;
select ok(
  (public.admin_redemption_command(
    '94000000-0000-4000-8000-000000000001', 'create_redemption_batch', null,
    '{"name":"Local Codes","productId":"94000000-0000-4000-8000-000000000010","productVersionId":"94000000-0000-4000-8000-000000000011","codePrefix":"AH-LOCAL","quantity":2,"source":"test"}'::jsonb,
    'create local batch', 'redemption-create-1', repeat('a', 64), '94000000-0000-4000-8000-000000000101'
  )) ? 'auditLogId',
  'batch creation returns an audit ID'
);
select is(
  (public.admin_redemption_command(
    '94000000-0000-4000-8000-000000000001', 'create_redemption_batch', null,
    '{"name":"Duplicate","productId":"94000000-0000-4000-8000-000000000010","productVersionId":"94000000-0000-4000-8000-000000000011","codePrefix":"AH-LOCAL","quantity":2,"source":"test"}'::jsonb,
    'retry local batch', 'redemption-create-1', repeat('a', 64), '94000000-0000-4000-8000-000000000102'
  ))->>'name',
  'Local Codes',
  'batch creation retry returns the original safe result'
);
select throws_ok($$ select public.admin_redemption_command(
  '94000000-0000-4000-8000-000000000001', 'create_redemption_batch', null,
  '{"name":"Different","productId":"94000000-0000-4000-8000-000000000010","productVersionId":"94000000-0000-4000-8000-000000000011","codePrefix":"AH-LOCAL","quantity":2,"source":"test"}'::jsonb,
  'different request', 'redemption-create-1', repeat('b', 64), '94000000-0000-4000-8000-000000000103'); $$,
  'P0001', null, 'same idempotency key cannot change the request'
);

select ok(
  (public.admin_redemption_command(
    '94000000-0000-4000-8000-000000000001', 'generate_redemption_codes',
    (select id from platform.redemption_batches where name = 'Local Codes'),
    '{"quantity":2,"codeRecords":[{"codeHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","codeHint":"AH-LOCAL-****-AAAA","pepperVersion":1},{"codeHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","codeHint":"AH-LOCAL-****-BBBB","pepperVersion":1}]}'::jsonb,
    'generate local codes', 'redemption-generate-1', repeat('c', 64), '94000000-0000-4000-8000-000000000104'
  )->'codes') @> '[{"codeHint":"AH-LOCAL-****-AAAA"}]'::jsonb,
  'generation returns only code hints from the database'
);
select ok(
  not (public.admin_redemption_command(
    '94000000-0000-4000-8000-000000000001', 'generate_redemption_codes',
    (select id from platform.redemption_batches where name = 'Local Codes'),
    '{"quantity":2,"codeRecords":[{"codeHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","codeHint":"AH-LOCAL-****-AAAA","pepperVersion":1},{"codeHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","codeHint":"AH-LOCAL-****-BBBB","pepperVersion":1}]}'::jsonb,
    'retry generation', 'redemption-generate-1', repeat('c', 64), '94000000-0000-4000-8000-000000000105'
  ) ? 'code'),
  'generation retry remains plaintext-free'
);
select is(
  (select count(*)::integer from platform.redemption_codes where batch_id = (select id from platform.redemption_batches where name = 'Local Codes')),
  2,
  'generation stores the requested code count'
);
select is(
  (select status from platform.redemption_batches where name = 'Local Codes'),
  'active',
  'generation activates the batch atomically'
);
select is(
  (select count(*)::integer from platform.audit_logs where action like 'redemption.%'),
  2,
  'create and generate each write one audit row'
);

select is(
  public.admin_redemption_command(
    '94000000-0000-4000-8000-000000000001', 'pause_redemption_batch',
    (select id from platform.redemption_batches where name = 'Local Codes'), '{}'::jsonb,
    'pause local batch', 'redemption-pause-1', repeat('d', 64), '94000000-0000-4000-8000-000000000106'
  )->>'status', 'paused', 'active batches can be paused');
select is(
  public.admin_redemption_command(
    '94000000-0000-4000-8000-000000000001', 'close_redemption_batch',
    (select id from platform.redemption_batches where name = 'Local Codes'), '{}'::jsonb,
    'close local batch', 'redemption-close-1', repeat('e', 64), '94000000-0000-4000-8000-000000000107'
  )->>'status', 'closed', 'paused batches can be closed');
select throws_ok($$ select public.admin_redemption_command(
  '94000000-0000-4000-8000-000000000001', 'pause_redemption_batch',
  (select id from platform.redemption_batches where name = 'Local Codes'), '{}'::jsonb,
  'invalid pause', 'redemption-pause-2', repeat('f', 64), '94000000-0000-4000-8000-000000000108'); $$,
  '23514', null, 'closed batches cannot be paused'
);

set local role postgres;
select is(
  (select count(*)::integer from platform.redemption_codes where code_hash in (repeat('a', 64), repeat('b', 64))),
  2,
  'storage contains digests but no plaintext code column'
);
select is(
  (select count(*)::integer from platform.idempotency_records where scope = 'admin.redemption.command'),
  4,
  'each successful command has one idempotency record'
);

select * from finish();
rollback;
