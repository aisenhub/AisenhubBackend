begin;

select plan(32);

select has_function('public', 'admin_user_overview', array['uuid', 'uuid'], 'User overview function exists');
select has_function(
  'public',
  'admin_query_customer_resource',
  array['uuid', 'text', 'text', 'integer', 'text', 'text', 'text', 'text'],
  'Customer query function exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.admin_user_overview(uuid,uuid)'::regprocedure),
  true,
  'User overview is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.admin_user_overview(uuid,uuid)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[],
  'User overview pins search_path'
);
select has_function_privilege(
  'service_role',
  'public.admin_user_overview(uuid,uuid)',
  'EXECUTE'
);
select ok(
  not has_function_privilege('anon', 'public.admin_user_overview(uuid,uuid)', 'EXECUTE'),
  'anon cannot invoke User overview'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (id, email) values
      ('97000000-0000-4000-8000-000000000001', 'overview-owner@aisenhub.test'),
      ('97000000-0000-4000-8000-000000000002', 'overview-admin@aisenhub.test'),
      ('97000000-0000-4000-8000-000000000003', 'overview-support@aisenhub.test'),
      ('97000000-0000-4000-8000-000000000004', 'overview-finance@aisenhub.test'),
      ('97000000-0000-4000-8000-000000000010', 'overview-target@aisenhub.test');
    insert into platform.admin_members (user_id, role) values
      ('97000000-0000-4000-8000-000000000001', 'owner'),
      ('97000000-0000-4000-8000-000000000002', 'admin'),
      ('97000000-0000-4000-8000-000000000003', 'support'),
      ('97000000-0000-4000-8000-000000000004', 'finance');
    update platform.profiles
       set display_name = 'Overview Target',
           avatar_url = 'https://example.test/overview-target.png',
           locale = 'en-US'
     where id = '97000000-0000-4000-8000-000000000010';
  $$,
  'User overview fixtures can be created'
);
select lives_ok(
  $$
    insert into platform.platform_sessions
      (user_id, token_hash, csrf_hash, expires_at, last_seen_at, revoked_at, revoked_reason, created_at)
    values
      ('97000000-0000-4000-8000-000000000010', 'overview-session-active', 'overview-csrf-active', now() + interval '1 day', now(), null, null, now() - interval '2 hours'),
      ('97000000-0000-4000-8000-000000000010', 'overview-session-revoked', 'overview-csrf-revoked', now() + interval '1 day', now() - interval '1 hour', now(), 'test', now() - interval '2 hours');
  $$,
  'User overview session fixtures can be created'
);
select lives_ok(
  $$
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id)
    values
      ('97000000-0000-4000-8000-000000000011', '97000000-0000-4000-8000-000000000010',
       '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
       'promotion', '97000000-0000-4000-8000-000000000012');
    insert into platform.redemption_batches
      (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, status, source, created_by)
    values
      ('97000000-0000-4000-8000-000000000013', 'Overview Batch',
       '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
       'AH-OVERVIEW', 1, 1, 'draft', 'test', '97000000-0000-4000-8000-000000000001');
    insert into platform.idempotency_records
      (id, scope, actor_key, idempotency_key, request_hash, expires_at)
    values
      ('97000000-0000-4000-8000-000000000050', 'test.overview', 'target', 'overview', 'overview-hash', now() + interval '1 day');
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id)
    values
      ('97000000-0000-4000-8000-000000000014', '97000000-0000-4000-8000-000000000010',
       '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
       'redemption', '97000000-0000-4000-8000-000000000015');
    insert into platform.redemption_codes
      (id, batch_id, code_hash, code_hint, pepper_version, status, redeemed_at)
    values
      ('97000000-0000-4000-8000-000000000016', '97000000-0000-4000-8000-000000000013', repeat('a', 64), 'AH-OVERVIEW-****-0001', 1, 'redeemed', now());
    insert into platform.redemptions
      (id, code_id, batch_id, user_id, grant_id, idempotency_record_id, ip_hash)
    values
      ('97000000-0000-4000-8000-000000000015', '97000000-0000-4000-8000-000000000016',
       '97000000-0000-4000-8000-000000000013', '97000000-0000-4000-8000-000000000010',
       '97000000-0000-4000-8000-000000000014', '97000000-0000-4000-8000-000000000050', 'hashed-ip');
  $$,
  'User overview entitlement and redemption fixtures can be created'
);
select lives_ok(
  $$
    insert into platform.feedback_requests (id, app_id, user_id, kind, title, content)
    values ('97000000-0000-4000-8000-000000000020', '20000000-0000-4000-8000-000000000002',
            '97000000-0000-4000-8000-000000000010', 'bug', 'Overview feedback', 'Private feedback body');
    insert into platform.account_deletion_requests
      (id, user_id, status, execute_after)
    values ('97000000-0000-4000-8000-000000000021', '97000000-0000-4000-8000-000000000010', 'pending', now());
    insert into platform.audit_logs
      (id, actor_type, actor_id, action, target_type, target_id, reason, before_summary, after_summary)
    values
      ('97000000-0000-4000-8000-000000000022', 'system', '97000000-0000-4000-8000-000000000010', 'overview.test', 'profile', '97000000-0000-4000-8000-000000000010', 'Overview test', '{}'::jsonb, '{}'::jsonb),
      ('97000000-0000-4000-8000-000000000023', 'system', null, 'overview.redemption.test', 'redemption', '97000000-0000-4000-8000-000000000015', 'Overview test', '{}'::jsonb, '{}'::jsonb);
  $$,
  'User overview feedback, deletion, and audit fixtures can be created'
);

set local role service_role;
create temporary table overview_results (payload jsonb) on commit drop;
select lives_ok(
  $$ insert into overview_results select public.admin_user_overview(
    '97000000-0000-4000-8000-000000000001', '97000000-0000-4000-8000-000000000010'
  ); $$,
  'owner can read User 360'
);
select is((select payload from overview_results) -> 'profile' ->> 'displayName', 'Overview Target', 'owner sees profile name');
select is(jsonb_array_length((select payload from overview_results) -> 'entitlements'), 2, 'overview includes grant history');
select is(jsonb_array_length((select payload from overview_results) -> 'redemptions'), 1, 'overview includes redemptions');
select is((select payload from overview_results) -> 'feedback' -> 0 ->> 'content', 'Private feedback body', 'owner sees feedback content');
select is(((select payload from overview_results) -> 'sessionSummary' ->> 'activeCount')::integer, 1, 'overview counts active sessions');
select is(((select payload from overview_results) -> 'sessionSummary' ->> 'totalCount')::integer, 2, 'overview counts total sessions');
select is(jsonb_array_length((select payload from overview_results) -> 'deletionRequests'), 1, 'overview includes deletion requests');
select ok(jsonb_array_length((select payload from overview_results) -> 'auditTimeline') >= 2, 'overview includes related audit timeline');
select ok((select payload from overview_results)::text not ilike '%token%' and (select payload from overview_results)::text not ilike '%ip_hash%', 'overview excludes security context');

truncate overview_results;
select lives_ok(
  $$ insert into overview_results select public.admin_user_overview(
    '97000000-0000-4000-8000-000000000004', '97000000-0000-4000-8000-000000000010'
  ); $$,
  'finance can read the permitted User 360 projection'
);
select is((select payload from overview_results) -> 'profile' ->> 'displayName', null, 'finance cannot see profile name');
select is((select payload from overview_results) -> 'profile' ->> 'avatarUrl', null, 'finance cannot see profile avatar');
select is((select payload from overview_results) -> 'feedback' -> 0 ->> 'content', null, 'finance cannot see feedback content');
select is((select payload from overview_results) -> 'entitlements' -> 0 ->> 'productSku', 'AISENLENS_LIFETIME', 'finance retains necessary product facts');

truncate overview_results;
select lives_ok(
  $$ insert into overview_results select public.admin_user_overview(
    '97000000-0000-4000-8000-000000000003', '97000000-0000-4000-8000-000000000010'
  ); $$,
  'support can read the permitted User 360 projection'
);
select is((select payload from overview_results) -> 'feedback' -> 0 ->> 'content', 'Private feedback body', 'support can manage feedback content');

set local role postgres;
select lives_ok(
  $$
    update platform.profiles
       set status = 'deleted', deleted_at = now(), display_name = null, avatar_url = null, locale = null
     where id = '97000000-0000-4000-8000-000000000010';
  $$,
  'deleted profile fixture can be prepared'
);
set local role service_role;
truncate overview_results;
select lives_ok(
  $$ insert into overview_results select public.admin_user_overview(
    '97000000-0000-4000-8000-000000000001', '97000000-0000-4000-8000-000000000010'
  ); $$,
  'deleted profile remains queryable as a retained business identity'
);
select is((select payload from overview_results) -> 'profile' ->> 'status', 'deleted', 'overview preserves deleted status');
select is(jsonb_array_length((select payload from overview_results) -> 'entitlements'), 2, 'deleted profile retains grant history projection');
select throws_ok(
  $$ select public.admin_user_overview('97000000-0000-4000-8000-000000000001', '97000000-0000-4000-8000-000000000099'); $$,
  'P0002', null,
  'unknown User 360 target is rejected'
);
select throws_ok(
  $$ select public.admin_query_customer_resource('97000000-0000-4000-8000-000000000001', 'unknown', null, 10, null, null, 'createdAt', 'desc'); $$,
  '22023', null,
  'unknown Customer resources are rejected'
);

select * from finish();
rollback;
