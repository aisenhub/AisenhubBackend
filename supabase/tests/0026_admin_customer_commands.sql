begin;

select plan(25);

select has_function(
  'public',
  'admin_customer_command',
  array['uuid', 'text', 'uuid', 'jsonb', 'text', 'text', 'text', 'uuid'],
  'Admin Customer command wrapper exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.admin_customer_command(uuid,text,uuid,jsonb,text,text,text,uuid)'::regprocedure),
  true,
  'Admin Customer command is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.admin_customer_command(uuid,text,uuid,jsonb,text,text,text,uuid)'::regprocedure),
  array['search_path=pg_catalog, auth, platform']::text[],
  'Admin Customer command pins its search_path'
);
select ok(
  has_function_privilege('service_role', 'public.admin_customer_command(uuid,text,uuid,jsonb,text,text,text,uuid)', 'EXECUTE'),
  'service_role can invoke Customer commands'
);
select ok(
  not has_function_privilege('authenticated', 'public.admin_customer_command(uuid,text,uuid,jsonb,text,text,text,uuid)', 'EXECUTE'),
  'authenticated cannot invoke Customer commands directly'
);
select ok(
  (select array_agg(action order by action) from (values
    ('entitlements.grant'::text), ('entitlements.revoke'), ('entitlements.restore'),
    ('users.disable'), ('account_deletion.process')) as expected(action))
  <@ (select array_agg(action order by action) from (select unnest(array[
    'entitlements.grant', 'entitlements.revoke', 'entitlements.restore',
    'users.disable', 'account_deletion.process']::text[]) action) as actions),
  'Customer permission action names are fixed'
);

set local role postgres;
select lives_ok($$
  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
  ) values
    ('96000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
     'customer-owner.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
    ('96000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
     'customer-support.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
    ('96000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
     'customer-target.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
    ('96000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
     'customer-disabled.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
    ('96000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated',
     'customer-deletion.local@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false);
  insert into platform.admin_members (user_id, role) values
    ('96000000-0000-4000-8000-000000000001', 'owner'),
    ('96000000-0000-4000-8000-000000000002', 'support');
  insert into platform.products (id, sku, name, billing_type)
  values ('96000000-0000-4000-8000-000000000010', 'CUSTOMER_COMMAND_TEST', 'Customer Command Test', 'one_time');
  insert into platform.product_versions (id, product_id, version, status, published_at)
  values ('96000000-0000-4000-8000-000000000011', '96000000-0000-4000-8000-000000000010', 1, 'published', now());
  insert into platform.platform_sessions (user_id, token_hash, csrf_hash, expires_at, last_seen_at)
  values
    ('96000000-0000-4000-8000-000000000004', 'customer-disable-session-1', 'customer-disable-csrf-1', now() + interval '1 day', now()),
    ('96000000-0000-4000-8000-000000000004', 'customer-disable-session-2', 'customer-disable-csrf-2', now() + interval '1 day', now());
$$, 'Customer command fixtures can be created');

set local role service_role;
select ok(
  (public.admin_customer_command(
    '96000000-0000-4000-8000-000000000002', 'grant_entitlement',
    '96000000-0000-4000-8000-000000000003',
    jsonb_build_object('productVersionId', '96000000-0000-4000-8000-000000000011'),
    'support grant', 'customer-grant-1', repeat('a', 64), '96000000-0000-4000-8000-000000000101'
  )) ? 'auditLogId',
  'Support can grant an entitlement with a reason'
);
set local role postgres;
select is(
  (select count(*)::integer from platform.entitlement_grants
    where user_id = '96000000-0000-4000-8000-000000000003'),
  1,
  'grant creates exactly one entitlement'
);
select is(
  (select count(*)::integer from platform.audit_logs
    where request_id = '96000000-0000-4000-8000-000000000101'),
  1,
  'grant writes one domain audit event'
);
select is(
  (public.admin_customer_command(
  '96000000-0000-4000-8000-000000000002', 'grant_entitlement',
  '96000000-0000-4000-8000-000000000003',
  jsonb_build_object('productVersionId', '96000000-0000-4000-8000-000000000011'),
  'support grant retry', 'customer-grant-1', repeat('a', 64), '96000000-0000-4000-8000-000000000102'
  )->>'grantId'),
  (select id::text from platform.entitlement_grants where user_id = '96000000-0000-4000-8000-000000000003'),
  'same grant key replays the original result'
);
select throws_ok($$ select public.admin_customer_command(
  '96000000-0000-4000-8000-000000000002', 'grant_entitlement',
  '96000000-0000-4000-8000-000000000003',
  '{"productVersionId":"96000000-0000-4000-8000-000000000011"}'::jsonb,
  'different request', 'customer-grant-1', repeat('b', 64), null); $$,
  'P0001', null, 'same Customer key cannot change its request hash'
);
select is(
  (public.admin_customer_command(
    '96000000-0000-4000-8000-000000000002', 'revoke_entitlement',
    (select id from platform.entitlement_grants where user_id = '96000000-0000-4000-8000-000000000003'),
    '{}'::jsonb, 'support revoke', 'customer-revoke-1', repeat('c', 64), '96000000-0000-4000-8000-000000000103'
  )->>'status'),
  'revoked',
  'Support can revoke an active entitlement'
);
select throws_ok($$ select public.admin_customer_command(
  '96000000-0000-4000-8000-000000000002', 'restore_entitlement',
  (select id from platform.entitlement_grants where user_id = '96000000-0000-4000-8000-000000000003'),
  '{}'::jsonb, 'support restore', 'customer-restore-support-1', repeat('d', 64), null) $$,
  '42501', null, 'Support cannot restore an entitlement'
);
select is(
  (public.admin_customer_command(
    '96000000-0000-4000-8000-000000000001', 'restore_entitlement',
    (select id from platform.entitlement_grants where user_id = '96000000-0000-4000-8000-000000000003'),
    '{}'::jsonb, 'owner restore', 'customer-restore-1', repeat('e', 64), '96000000-0000-4000-8000-000000000104'
  )->>'status'),
  'active',
  'Owner restore creates a new active entitlement'
);
select is(
  (select count(*)::integer from platform.entitlement_grants
    where user_id = '96000000-0000-4000-8000-000000000003'),
  2,
  'restore preserves the original and creates one new grant'
);
select is(
  (select count(*)::integer from platform.entitlement_restore_links),
  1,
  'restore writes one immutable restore link'
);
select throws_ok($$ select public.admin_customer_command(
  '96000000-0000-4000-8000-000000000001', 'restore_entitlement',
  (select restores_grant_id from platform.entitlement_restore_links limit 1),
  '{}'::jsonb, 'repeat restore', 'customer-restore-2', repeat('f', 64), null) $$,
  '23505', null, 'a revoked original cannot be restored twice'
);

select is(
  (public.admin_customer_command(
    '96000000-0000-4000-8000-000000000001', 'disable_user',
    '96000000-0000-4000-8000-000000000004', '{}'::jsonb,
    'disable account', 'customer-disable-1', repeat('1', 64), '96000000-0000-4000-8000-000000000105'
  )->>'status'),
  'disabled',
  'Owner can disable an active user'
);
select is(
  (select count(*)::integer from platform.platform_sessions
    where user_id = '96000000-0000-4000-8000-000000000004' and revoked_at is not null),
  2,
  'disable revokes every active platform session'
);
select throws_ok($$ select public.admin_customer_command(
  '96000000-0000-4000-8000-000000000001', 'disable_user',
  '96000000-0000-4000-8000-000000000004', '{}'::jsonb,
  'disable again', 'customer-disable-2', repeat('2', 64), null) $$,
  '23514', null, 'already disabled users cannot be disabled twice'
);

create temporary table deletion_command_result on commit drop as
select * from public.request_account_deletion(
  '96000000-0000-4000-8000-000000000005', 'customer-deletion-request-1', repeat('3', 64),
  '96000000-0000-4000-8000-000000000106'
);
select is(
  (public.admin_customer_command(
    '96000000-0000-4000-8000-000000000001', 'process_account_deletion',
    (select deletion_request_id from deletion_command_result), '{}'::jsonb,
    'process deletion', 'customer-deletion-process-1', repeat('4', 64), '96000000-0000-4000-8000-000000000107'
  )->>'status'),
  'processing',
  'Owner can claim a due deletion request for processing'
);
select is(
  (select attempt_count from platform.account_deletion_requests
    where id = (select deletion_request_id from deletion_command_result)),
  1,
  'processing increments the deletion attempt count'
);
select is(
  (select resource_type from platform.idempotency_records
    where scope = 'admin.customer.command' and idempotency_key = 'customer-deletion-process-1'),
  'account_deletion_request',
  'deletion processing idempotency records identify the request resource'
);
select throws_ok($$ select public.admin_customer_command(
  '96000000-0000-4000-8000-000000000001', 'process_account_deletion',
  (select deletion_request_id from deletion_command_result), '{}'::jsonb,
  'process again', 'customer-deletion-process-2', repeat('5', 64), null) $$,
  '23514', null, 'a processing deletion request cannot be claimed twice'
);

select * from finish();
rollback;
