begin;

select plan(24);

select has_function(
  'public', 'admin_application_membership_command',
  array['uuid','text','uuid','uuid','uuid','text','text','text','uuid'],
  'Admin membership command exists'
);
select has_function(
  'public', 'admin_oauth_client_command',
  array['uuid','text','uuid','uuid','text','text','text','text','text','text','text','text','uuid'],
  'Admin OAuth client command exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.admin_application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,uuid)'::regprocedure),
  true, 'Admin membership command is SECURITY DEFINER'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.admin_oauth_client_command(uuid,text,uuid,uuid,text,text,text,text,text,text,text,text,uuid)'::regprocedure),
  true, 'Admin OAuth client command is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.admin_application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,uuid)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[], 'Admin membership command pins search_path'
);
select is(
  (select proconfig from pg_proc where oid = 'public.admin_oauth_client_command(uuid,text,uuid,uuid,text,text,text,text,text,text,text,text,uuid)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[], 'Admin OAuth client command pins search_path'
);
select ok(has_function_privilege('service_role', 'public.admin_application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,uuid)', 'EXECUTE'), 'service_role can execute membership command');
select ok(has_function_privilege('service_role', 'public.admin_oauth_client_command(uuid,text,uuid,uuid,text,text,text,text,text,text,text,text,uuid)', 'EXECUTE'), 'service_role can execute OAuth command');
select ok(not has_function_privilege('anon', 'public.admin_application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,uuid)', 'EXECUTE'), 'anon cannot execute membership command');
select ok(not has_function_privilege('authenticated', 'public.admin_oauth_client_command(uuid,text,uuid,uuid,text,text,text,text,text,text,text,text,uuid)', 'EXECUTE'), 'authenticated cannot execute OAuth command');

set local role postgres;
select lives_ok($$
  insert into auth.users (id, email) values
    ('97000000-0000-4000-8000-000000000001', 'admin-ops-owner@aisenhub.test'),
    ('97000000-0000-4000-8000-000000000002', 'admin-ops-support@aisenhub.test'),
    ('97000000-0000-4000-8000-000000000003', 'admin-ops-member@aisenhub.test');
  insert into platform.platform_apps
    (id, slug, name, category, status, membership_policy)
  values
    ('97000000-0000-4000-8000-000000000101', 'admin-ops-app', 'Admin Operations App', 'test', 'active', 'explicit');
  insert into platform.admin_members (user_id, role, status, created_by)
  values
    ('97000000-0000-4000-8000-000000000001', 'owner', 'active', '97000000-0000-4000-8000-000000000001'),
    ('97000000-0000-4000-8000-000000000002', 'support', 'active', '97000000-0000-4000-8000-000000000001');
$$, 'Admin application operation fixtures can be created');

set local role postgres;
select lives_ok($$ select public.admin_application_membership_command(
  '97000000-0000-4000-8000-000000000001', 'create',
  '97000000-0000-4000-8000-000000000101', '97000000-0000-4000-8000-000000000003', null,
  'seed member', 'admin-membership-create-1', 'admin-membership-create-hash-1',
  '97000000-0000-4000-8000-000000000201'); $$,
  'Owner can create an application membership');
select is(
  (select status from platform.application_memberships where application_id = '97000000-0000-4000-8000-000000000101' and user_id = '97000000-0000-4000-8000-000000000003'),
  'pending', 'Admin-created explicit membership starts pending'
);
select is(
  (select count(*)::integer from platform.audit_logs where action = 'applications.membership.create' and target_type = 'application_membership'),
  1, 'Membership creation is audited exactly once'
);
select lives_ok($$ select public.admin_application_membership_command(
  '97000000-0000-4000-8000-000000000001', 'create',
  '97000000-0000-4000-8000-000000000101', '97000000-0000-4000-8000-000000000003', null,
  'seed member', 'admin-membership-create-1', 'admin-membership-create-hash-1',
  '97000000-0000-4000-8000-000000000202'); $$,
  'A repeated membership command is idempotent');
select throws_ok($$ select public.admin_application_membership_command(
  '97000000-0000-4000-8000-000000000002', 'suspend',
  '97000000-0000-4000-8000-000000000101', null,
  (select id from platform.application_memberships where user_id = '97000000-0000-4000-8000-000000000003'),
  'support suspend', 'admin-membership-deny-1', 'admin-membership-deny-hash-1',
  '97000000-0000-4000-8000-000000000203'); $$,
  '42501', null, 'Support cannot execute membership management commands');
select lives_ok($$ select public.admin_oauth_client_command(
  '97000000-0000-4000-8000-000000000001', 'create',
  '97000000-0000-4000-8000-000000000101', null, 'supabase', 'admin-ops-client',
  'public', 'development', 'Admin Operations Web', 'register client',
  'admin-oauth-create-1', 'admin-oauth-create-hash-1',
  '97000000-0000-4000-8000-000000000204'); $$,
  'Owner can create an OAuth client binding');
select ok(
  not exists (select 1 from information_schema.columns where table_schema = 'platform' and table_name = 'application_oauth_clients' and column_name like '%secret%'),
  'OAuth binding table has no secret column'
);
select throws_ok($$ select public.admin_oauth_client_command(
  '97000000-0000-4000-8000-000000000001', 'create',
  '97000000-0000-4000-8000-000000000101', null, 'supabase', 'admin-ops-client',
  'public', 'development', 'Duplicate Client', 'duplicate client',
  'admin-oauth-duplicate-1', 'admin-oauth-duplicate-hash-1',
  '97000000-0000-4000-8000-000000000205'); $$,
  '23505', null, 'An external OAuth client id cannot be registered twice');
select lives_ok($$ select public.admin_oauth_client_command(
  '97000000-0000-4000-8000-000000000001', 'disable',
  '97000000-0000-4000-8000-000000000101',
  (select id from platform.application_oauth_clients where external_client_id = 'admin-ops-client'),
  null, null, null, null, null, 'disable client',
  'admin-oauth-disable-1', 'admin-oauth-disable-hash-1',
  '97000000-0000-4000-8000-000000000206'); $$,
  'Owner can disable an OAuth client binding');
select is(
  (select status from platform.application_oauth_clients where external_client_id = 'admin-ops-client'),
  'disabled', 'Disabling changes only OAuth client status'
);
select lives_ok($$ select public.admin_oauth_client_command(
  '97000000-0000-4000-8000-000000000001', 'restore',
  '97000000-0000-4000-8000-000000000101',
  (select id from platform.application_oauth_clients where external_client_id = 'admin-ops-client'),
  null, null, null, null, null, 'restore client',
  'admin-oauth-restore-1', 'admin-oauth-restore-hash-1',
  '97000000-0000-4000-8000-000000000207'); $$,
  'Owner can restore an OAuth client binding');
select is(
  (select count(*)::integer from platform.audit_logs where target_type = 'application_oauth_client'),
  3, 'OAuth client create, disable and restore are audited'
);
select throws_ok($$ select public.admin_application_membership_command(
  '97000000-0000-4000-8000-000000000001', 'suspend',
  '97000000-0000-4000-8000-000000000101', null,
  (select id from platform.application_memberships where user_id = '97000000-0000-4000-8000-000000000003'),
  'invalid transition test', 'admin-membership-transition-1', 'admin-membership-transition-hash-1',
  '97000000-0000-4000-8000-000000000208'); $$,
  '23514', null, 'Illegal membership transition is rejected');

select * from finish();
rollback;
