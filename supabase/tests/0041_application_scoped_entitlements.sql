begin;

select plan(16);

select has_function(
  'public', 'list_user_application_entitlements', array['uuid', 'uuid'],
  'application entitlement projection exists'
);
select has_function(
  'public', 'check_application_access', array['uuid', 'uuid', 'text'],
  'application access resolver exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.list_user_application_entitlements(uuid,uuid)'::regprocedure),
  true, 'application entitlement projection is SECURITY DEFINER'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.check_application_access(uuid,uuid,text)'::regprocedure),
  true, 'application access resolver is SECURITY DEFINER'
);
select ok(has_function_privilege('service_role', 'public.list_user_application_entitlements(uuid,uuid)', 'EXECUTE'), 'service_role can execute application entitlement projection');
select ok(has_function_privilege('service_role', 'public.check_application_access(uuid,uuid,text)', 'EXECUTE'), 'service_role can execute application access resolver');
select ok(not has_function_privilege('anon', 'public.list_user_application_entitlements(uuid,uuid)', 'EXECUTE'), 'anon cannot execute application entitlement projection');
select ok(not has_function_privilege('authenticated', 'public.check_application_access(uuid,uuid,text)', 'EXECUTE'), 'authenticated cannot execute application access resolver');

set local role postgres;
select lives_ok($$
  insert into auth.users (id, email) values ('98000000-0000-4000-8000-000000000001', 'scoped-entitlement@aisenhub.test');
  insert into platform.platform_apps (id, slug, name, category, status, membership_policy)
  values
    ('98000000-0000-4000-8000-000000000101', 'scoped-app-a', 'Scoped App A', 'test', 'active', 'explicit'),
    ('98000000-0000-4000-8000-000000000102', 'scoped-app-b', 'Scoped App B', 'test', 'active', 'explicit');
  insert into platform.application_memberships (id, application_id, user_id, status, created_source, activated_at)
  values ('98000000-0000-4000-8000-000000000201', '98000000-0000-4000-8000-000000000101', '98000000-0000-4000-8000-000000000001', 'active', 'test', now());
  insert into platform.features (id, app_id, code, name, value_type, merge_strategy)
  values
    ('98000000-0000-4000-8000-000000000301', '98000000-0000-4000-8000-000000000101', 'scoped.app.access', 'Scoped App Access', 'boolean', 'any_true'),
    ('98000000-0000-4000-8000-000000000302', '98000000-0000-4000-8000-000000000102', 'scoped.other.access', 'Scoped Other Access', 'boolean', 'any_true');
  insert into platform.products (id, sku, name, billing_type, status)
  values ('98000000-0000-4000-8000-000000000401', 'SCOPED_ENTITLEMENT', 'Scoped Entitlement', 'one_time', 'draft');
  insert into platform.product_versions (id, product_id, version, status, published_at)
  values ('98000000-0000-4000-8000-000000000402', '98000000-0000-4000-8000-000000000401', 1, 'published', now());
  insert into platform.product_version_features (product_version_id, feature_id, value)
  values
    ('98000000-0000-4000-8000-000000000402', '98000000-0000-4000-8000-000000000301', 'true'::jsonb),
    ('98000000-0000-4000-8000-000000000402', '98000000-0000-4000-8000-000000000302', 'true'::jsonb);
  insert into platform.entitlement_grants (id, user_id, product_id, product_version_id, source_type, source_id)
  values ('98000000-0000-4000-8000-000000000403', '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000401', '98000000-0000-4000-8000-000000000402', 'admin', '98000000-0000-4000-8000-000000000404');
$$, 'application-scoped entitlement fixtures can be created');

select is(
  (select count(*)::integer from public.list_user_application_entitlements('98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000101')),
  1, 'an application receives only its own feature entitlement'
);
select is(
  (select feature from public.list_user_application_entitlements('98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000101')),
  'scoped.app.access', 'the entitlement projection filters feature ownership'
);
select is(
  (select count(*)::integer from public.list_user_application_entitlements('98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000102')),
  0, 'an application without membership receives no entitlement projection'
);
select is(
  (select allowed from public.check_application_access('98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000101', 'scoped.app.access')),
  true, 'an active member can resolve access for its application'
);
select is(
  (select allowed from public.check_application_access('98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000101', 'scoped.other.access')),
  false, 'cross-application feature access fails closed'
);
select lives_ok($$
  insert into platform.application_memberships (id, application_id, user_id, status, created_source, activated_at)
  values ('98000000-0000-4000-8000-000000000202', '98000000-0000-4000-8000-000000000102', '98000000-0000-4000-8000-000000000001', 'active', 'test', now());
$$, 'the same identity can separately join the second application');
select is(
  (select allowed from public.check_application_access('98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000102', 'scoped.other.access')),
  true, 'the second application resolves only after its membership is active'
);

select * from finish();
rollback;
