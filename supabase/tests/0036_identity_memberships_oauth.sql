begin;

select plan(35);

select has_table('platform', 'application_memberships', 'application membership table exists');
select has_table('platform', 'application_oauth_clients', 'OAuth client binding table exists');
select has_column('platform', 'platform_apps', 'registration_policy', 'applications expose registration policy');
select has_column('platform', 'platform_apps', 'membership_policy', 'applications expose membership policy');
select ok(
  exists (
    select 1 from pg_constraint
     where conrelid = 'platform.application_memberships'::regclass
       and contype = 'u'
       and conkey = array[
         (select attnum from pg_attribute where attrelid = 'platform.application_memberships'::regclass and attname = 'application_id'),
         (select attnum from pg_attribute where attrelid = 'platform.application_memberships'::regclass and attname = 'user_id')
       ]::smallint[]
  ),
  'one membership per application and user'
);
select ok(
  exists (
    select 1 from pg_constraint
     where conrelid = 'platform.application_oauth_clients'::regclass
       and contype = 'u'
       and conkey = array[(select attnum from pg_attribute where attrelid = 'platform.application_oauth_clients'::regclass and attname = 'external_client_id')]::smallint[]
  ),
  'one application owns each external client id'
);
select has_function('public', 'application_membership_command', array['uuid','text','uuid','uuid','uuid','text','text','text','text','uuid'], 'membership lifecycle command exists');
select is(
  (select prosecdef from pg_proc where oid = 'public.application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,text,uuid)'::regprocedure),
  true,
  'membership lifecycle command is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,text,uuid)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[],
  'membership lifecycle command pins search_path'
);
select ok(has_function_privilege('service_role', 'public.application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,text,uuid)', 'EXECUTE'), 'service_role can execute membership command');
select ok(not has_function_privilege('anon', 'public.application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,text,uuid)', 'EXECUTE'), 'anon cannot execute membership command');
select ok(not has_table_privilege('anon', 'platform.application_memberships', 'SELECT'), 'anon cannot read memberships');
select ok(not has_table_privilege('authenticated', 'platform.application_memberships', 'SELECT'), 'authenticated cannot read memberships');
select ok(not has_table_privilege('service_role', 'platform.application_oauth_clients', 'SELECT'), 'service_role cannot read OAuth bindings directly');
select has_function('public', 'list_user_application_memberships', array['uuid'], 'user membership projection exists');
select has_function('public', 'admin_list_application_memberships', array['uuid','uuid'], 'Admin membership projection exists');
select has_function('public', 'admin_list_application_oauth_clients', array['uuid','uuid'], 'Admin OAuth projection exists');
select ok(not has_function_privilege('anon', 'public.list_user_application_memberships(uuid)', 'EXECUTE'), 'anon cannot execute user membership projection');
select ok(has_function_privilege('service_role', 'public.admin_list_application_oauth_clients(uuid,uuid)', 'EXECUTE'), 'service_role can execute Admin OAuth projection');

set local role postgres;
select lives_ok($$
  insert into auth.users (id, email) values
    ('96000000-0000-4000-8000-000000000001', 'membership-a@aisenhub.test'),
    ('96000000-0000-4000-8000-000000000002', 'membership-b@aisenhub.test');
  insert into platform.platform_apps
    (id, slug, name, category, status, membership_policy)
  values
    ('96000000-0000-4000-8000-000000000101', 'membership-app-a', 'Membership App A', 'test', 'active', 'explicit'),
    ('96000000-0000-4000-8000-000000000102', 'membership-app-b', 'Membership App B', 'test', 'active', 'create_on_first_authorization');
  insert into platform.application_oauth_clients
    (id, application_id, provider, external_client_id, client_type, environment, name)
  values
    ('96000000-0000-4000-8000-000000000201', '96000000-0000-4000-8000-000000000101', 'supabase', 'membership-client-a', 'public', 'development', 'App A local client'),
    ('96000000-0000-4000-8000-000000000202', '96000000-0000-4000-8000-000000000102', 'supabase', 'membership-client-b', 'confidential', 'staging', 'App B staging client');
$$, 'identity membership and OAuth fixtures can be created');

select throws_ok($$ insert into platform.application_oauth_clients
  (application_id, provider, external_client_id, client_type, environment, name)
  values ('96000000-0000-4000-8000-000000000102', 'supabase', 'membership-client-a', 'public', 'development', 'duplicate client'); $$,
  '23505', null, 'an external OAuth client cannot bind to two applications');

select lives_ok($$ insert into platform.application_memberships
  (application_id, user_id, status, created_source, activated_at)
  values ('96000000-0000-4000-8000-000000000101', '96000000-0000-4000-8000-000000000002', 'active', 'test', now()); $$,
  'a membership fixture can be created');

select throws_ok($$ insert into platform.application_memberships
  (application_id, user_id, status, created_source, activated_at)
  values ('96000000-0000-4000-8000-000000000101', '96000000-0000-4000-8000-000000000002', 'active', 'test', now());
  insert into platform.application_memberships
  (application_id, user_id, status, created_source, activated_at)
  values ('96000000-0000-4000-8000-000000000101', '96000000-0000-4000-8000-000000000002', 'active', 'test', now()); $$,
  '23505', null, 'an identity cannot have duplicate membership in one application');

set local role service_role;
select lives_ok($$ select public.application_membership_command(
  '96000000-0000-4000-8000-000000000001', 'create',
  '96000000-0000-4000-8000-000000000101', '96000000-0000-4000-8000-000000000001', null,
  'oauth', 'join App A', 'membership-create-1', 'membership-create-hash-1',
  '96000000-0000-4000-8000-000000000301'); $$, 'create command creates pending membership');

set local role postgres;
select is((select status from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000101' and user_id = '96000000-0000-4000-8000-000000000001'), 'pending', 'explicit membership policy starts pending');

select lives_ok($$ select public.application_membership_command(
  '96000000-0000-4000-8000-000000000001', 'activate', null, null,
  (select id from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000101' and user_id = '96000000-0000-4000-8000-000000000001'),
  'oauth', 'activate App A', 'membership-activate-1', 'membership-activate-hash-1',
  '96000000-0000-4000-8000-000000000302'); $$, 'member can activate pending membership');
select is((select status from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000101' and user_id = '96000000-0000-4000-8000-000000000001'), 'active', 'activation makes membership active');

select lives_ok($$ select public.application_membership_command(
  '96000000-0000-4000-8000-000000000001', 'create',
  '96000000-0000-4000-8000-000000000102', '96000000-0000-4000-8000-000000000001', null,
  'oauth', 'join App B', 'membership-create-2', 'membership-create-hash-2',
  '96000000-0000-4000-8000-000000000303'); $$, 'automatic membership policy creates membership');
select is((select status from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000102' and user_id = '96000000-0000-4000-8000-000000000001'), 'active', 'first authorization policy activates membership');

select lives_ok($$ select public.application_membership_command(
  '96000000-0000-4000-8000-000000000001', 'leave', null, null,
  (select id from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000102' and user_id = '96000000-0000-4000-8000-000000000001'),
  'self_service', 'leave App B', 'membership-leave-1', 'membership-leave-hash-1',
  '96000000-0000-4000-8000-000000000305'); $$, 'member can leave one application');
select is((select status from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000102' and user_id = '96000000-0000-4000-8000-000000000001'), 'left', 'leaving changes only the selected membership');
select is((select status from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000101' and user_id = '96000000-0000-4000-8000-000000000001'), 'active', 'leaving one application preserves another membership');
select is((select status from platform.profiles where id = '96000000-0000-4000-8000-000000000001'), 'active', 'leaving an application preserves Global Identity');

select throws_ok($$ select public.application_membership_command(
  '96000000-0000-4000-8000-000000000002', 'suspend', null, null,
  (select id from platform.application_memberships where application_id = '96000000-0000-4000-8000-000000000101' and user_id = '96000000-0000-4000-8000-000000000001'),
  'system', 'unauthorized suspend', 'membership-deny-1', 'membership-deny-hash-1',
  '96000000-0000-4000-8000-000000000304'); $$, '42501', null, 'another member cannot suspend membership');

select is((select status from platform.profiles where id = '96000000-0000-4000-8000-000000000001'), 'active', 'membership lifecycle never changes Global Profile status');

select * from finish();
rollback;
