begin;

select plan(19);

select has_column('platform', 'feedback_requests', 'membership_id', 'feedback stores its membership context');
select has_column('platform', 'audit_logs', 'application_id', 'audit logs store explicit application context');
select has_function('public', 'create_application_feedback', array['uuid', 'uuid', 'uuid', 'text', 'text', 'text'], 'application feedback command exists');
select has_function('platform', 'cleanup_application_data', array['uuid'], 'application cleanup helper exists');
select ok(not has_function_privilege('authenticated', 'public.create_application_feedback(uuid,uuid,uuid,text,text,text)', 'EXECUTE'), 'authenticated cannot invoke feedback command directly');
select ok(has_function_privilege('service_role', 'public.create_application_feedback(uuid,uuid,uuid,text,text,text)', 'EXECUTE'), 'service_role can invoke application feedback command');

set local role postgres;
select lives_ok($$
  insert into auth.users (id, email) values ('98000000-0000-4000-8000-000000000001', 'application-cleanup@aisenhub.test');
  insert into platform.platform_apps (id, slug, name, category, status, membership_policy)
  values
    ('98000000-0000-4000-8000-000000000101', 'cleanup-app-a', 'Cleanup App A', 'test', 'active', 'explicit'),
    ('98000000-0000-4000-8000-000000000102', 'cleanup-app-b', 'Cleanup App B', 'test', 'active', 'explicit');
  insert into platform.admin_members (user_id, role)
  values ('98000000-0000-4000-8000-000000000001', 'owner');
  insert into platform.application_memberships (id, application_id, user_id, status, created_source, activated_at)
  values
    ('98000000-0000-4000-8000-000000000201', '98000000-0000-4000-8000-000000000101', '98000000-0000-4000-8000-000000000001', 'active', 'test', now()),
    ('98000000-0000-4000-8000-000000000202', '98000000-0000-4000-8000-000000000102', '98000000-0000-4000-8000-000000000001', 'active', 'test', now());
  insert into platform.features (id, app_id, code, name, value_type, merge_strategy)
  values
    ('98000000-0000-4000-8000-000000000301', '98000000-0000-4000-8000-000000000101', 'cleanup.app.a', 'Cleanup App A', 'boolean', 'any_true'),
    ('98000000-0000-4000-8000-000000000302', '98000000-0000-4000-8000-000000000102', 'cleanup.app.b', 'Cleanup App B', 'boolean', 'any_true');
  insert into platform.products (id, sku, name, billing_type, status)
  values
    ('98000000-0000-4000-8000-000000000401', 'CLEANUP_APP_A_PRODUCT', 'Cleanup App A Product', 'one_time', 'draft'),
    ('98000000-0000-4000-8000-000000000402', 'CLEANUP_APP_B_PRODUCT', 'Cleanup App B Product', 'one_time', 'draft');
  insert into platform.product_versions (id, product_id, version, status, published_at)
  values
    ('98000000-0000-4000-8000-000000000411', '98000000-0000-4000-8000-000000000401', 1, 'published', now()),
    ('98000000-0000-4000-8000-000000000412', '98000000-0000-4000-8000-000000000402', 1, 'published', now());
  insert into platform.product_version_features (product_version_id, feature_id, value)
  values
    ('98000000-0000-4000-8000-000000000411', '98000000-0000-4000-8000-000000000301', 'true'::jsonb),
    ('98000000-0000-4000-8000-000000000412', '98000000-0000-4000-8000-000000000302', 'true'::jsonb);
  set local app.application_id = '98000000-0000-4000-8000-000000000101';
  insert into platform.entitlement_grants
    (id, user_id, product_id, product_version_id, source_type, source_id, status)
  values
    ('98000000-0000-4000-8000-000000000421', '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000401', '98000000-0000-4000-8000-000000000411', 'admin', '98000000-0000-4000-8000-000000000431', 'active');
  reset app.application_id;
$$, 'application cleanup fixtures can be created');

select lives_ok($$ select * from public.create_application_feedback(
  '98000000-0000-4000-8000-000000000101', '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000201', 'bug', 'App A issue', 'App A private details'
); $$, 'authenticated feedback command accepts the resolved membership');
select throws_ok($$ select * from public.create_application_feedback(
  '98000000-0000-4000-8000-000000000102', '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000201', 'bug', 'Wrong app', 'Must be rejected'
); $$, '42501', null, 'feedback cannot cross application membership boundaries');
select is((select membership_id from platform.feedback_requests where title = 'App A issue'), '98000000-0000-4000-8000-000000000201', 'feedback stores membership id');

set local app.application_id = '98000000-0000-4000-8000-000000000101';
select lives_ok($$
  insert into platform.audit_logs (actor_type, actor_id, action, target_type, target_id, reason)
  values ('user', '98000000-0000-4000-8000-000000000001', 'cleanup.app.event', 'application_membership', '98000000-0000-4000-8000-000000000201', 'application audit test');
$$, 'application audit context is assigned explicitly');
reset app.application_id;
select is((select count(*)::integer from platform.audit_logs where application_id = '98000000-0000-4000-8000-000000000101' and action = 'cleanup.app.event'), 1, 'application audit events are filterable by application id');
select throws_ok($$
  set local app.application_id = '98000000-0000-4000-8000-000000000101';
  insert into platform.audit_logs (application_id, actor_type, action, target_type, target_id, reason)
  values ('98000000-0000-4000-8000-000000000102', 'user', 'cleanup.wrong.app', 'application_membership', '98000000-0000-4000-8000-000000000201', 'mismatch test');
$$, '23514', null, 'audit rejects a mismatched explicit application context');

set local role service_role;
select is(
  public.admin_query_resource(
    '98000000-0000-4000-8000-000000000001', 'audit-logs', null, 10, null, null, 'createdAt', 'asc',
    '98000000-0000-4000-8000-000000000101'
  )->'items'->0->>'applicationId',
  '98000000-0000-4000-8000-000000000101',
  'Admin audit projection filters by explicit application id'
);
select lives_ok($$ select public.application_membership_command(
  '98000000-0000-4000-8000-000000000001', 'leave', null, null,
  '98000000-0000-4000-8000-000000000201', 'self_service', 'Leave App A',
  'cleanup-leave-001', 'cleanup-leave-hash-001', null
); $$, 'application leave runs the cleanup workflow');
set local role postgres;
select is((select status from platform.application_memberships where id = '98000000-0000-4000-8000-000000000201'), 'left', 'application leave terminates only the selected membership');
select is((select status from platform.entitlement_grants where id = '98000000-0000-4000-8000-000000000421'), 'revoked', 'application leave revokes only scoped grants');
select is((select user_id from platform.feedback_requests where title = '[deleted]' and app_id = '98000000-0000-4000-8000-000000000101'), null, 'application leave anonymizes scoped feedback');
select is((select status from platform.application_memberships where id = '98000000-0000-4000-8000-000000000202'), 'active', 'application leave preserves other memberships');

select * from finish();
rollback;
