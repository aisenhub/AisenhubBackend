begin;

select plan(12);

select has_function(
  'public',
  'resolve_application_context',
  array['uuid', 'text'],
  'application context resolver exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.resolve_application_context(uuid,text)'::regprocedure),
  true,
  'application context resolver is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.resolve_application_context(uuid,text)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[],
  'application context resolver pins search_path'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.resolve_application_context(uuid,text)',
    'EXECUTE'
  ),
  'service_role can resolve application context'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.resolve_application_context(uuid,text)',
    'EXECUTE'
  ),
  'anon cannot resolve application context'
);

set local role postgres;
select lives_ok($$
  insert into auth.users (id, email)
  values ('97000000-0000-4000-8000-000000000001', 'context@aisenhub.test');
  insert into platform.platform_apps
    (id, slug, name, category, status, membership_policy)
  values
    ('97000000-0000-4000-8000-000000000101', 'context-app', 'Context App', 'test', 'active', 'explicit'),
    ('97000000-0000-4000-8000-000000000102', 'context-other', 'Context Other', 'test', 'active', 'explicit');
  insert into platform.application_oauth_clients
    (id, application_id, provider, external_client_id, client_type, environment, name)
  values
    ('97000000-0000-4000-8000-000000000201', '97000000-0000-4000-8000-000000000101', 'supabase', 'context-client', 'public', 'development', 'Context client'),
    ('97000000-0000-4000-8000-000000000202', '97000000-0000-4000-8000-000000000102', 'supabase', 'context-other-client', 'public', 'development', 'Other client');
  insert into platform.application_memberships
    (application_id, user_id, status, created_source, activated_at)
  values
    ('97000000-0000-4000-8000-000000000101', '97000000-0000-4000-8000-000000000001', 'active', 'test', now());
$$, 'context fixtures can be created');

set local role service_role;
select is(
  (
    select application_slug
      from public.resolve_application_context(
        '97000000-0000-4000-8000-000000000001',
        'context-client'
      )
  ),
  'context-app',
  'client binding resolves its own application'
);
select is(
  (
    select membership_status
      from public.resolve_application_context(
        '97000000-0000-4000-8000-000000000001',
        'context-client'
      )
  ),
  'active',
  'resolver returns the user membership state'
);
select is(
  (
    select application_slug
      from public.resolve_application_context(
        '97000000-0000-4000-8000-000000000001',
        'context-other-client'
      )
  ),
  'context-other',
  'a different verified client resolves only its bound application'
);
select is(
  (
    select membership_status
      from public.resolve_application_context(
        '97000000-0000-4000-8000-000000000001',
        'context-other-client'
      )
  ),
  null,
  'a user membership in one application does not leak into another'
);
select is(
  (
    select count(*)::integer
      from public.resolve_application_context(
        '97000000-0000-4000-8000-000000000001',
        'missing-client'
      )
  ),
  0,
  'an unknown client does not resolve context'
);

set local role postgres;
update platform.application_memberships
   set status = 'suspended', suspended_at = now(), suspended_reason = 'test'
 where application_id = '97000000-0000-4000-8000-000000000101'
   and user_id = '97000000-0000-4000-8000-000000000001';
select is(
  (
    select membership_status
      from public.resolve_application_context(
        '97000000-0000-4000-8000-000000000001',
        'context-client'
      )
  ),
  'suspended',
  'resolver exposes suspended state for the auth kernel to deny'
);

select * from finish();
rollback;
