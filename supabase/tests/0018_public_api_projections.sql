begin;

select plan(24);

select has_table(
  'platform',
  'feedback_requests',
  'feedback requests table exists in the private platform schema'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.feedback_requests'::regclass),
  'feedback requests enable RLS'
);
select ok(
  not has_table_privilege('anon', 'platform.feedback_requests', 'SELECT'),
  'anon cannot read feedback requests directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.feedback_requests', 'SELECT'),
  'authenticated cannot read feedback requests directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.feedback_requests', 'SELECT'),
  'service_role cannot bypass the feedback API projection'
);

select has_function(
  'public',
  'get_public_products',
  '{}',
  'public product projection exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.get_public_products()'::regprocedure),
  'public product projection is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']::text[]
   from pg_proc
   where oid = 'public.get_public_products()'::regprocedure),
  'public product projection fixes its search_path'
);
select ok(
  has_function_privilege('anon', 'public.get_public_products()', 'EXECUTE'),
  'anon can read the public product projection'
);
select ok(
  not has_function_privilege('service_role', 'public.get_public_products()', 'EXECUTE'),
  'service_role does not need a public catalog function grant'
);

select has_function(
  'public',
  'list_user_entitlements',
  ARRAY['uuid'],
  'entitlement summary projection exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.list_user_entitlements(uuid)'::regprocedure),
  'entitlement summary projection is SECURITY DEFINER'
);
select ok(
  not has_function_privilege('anon', 'public.list_user_entitlements(uuid)', 'EXECUTE'),
  'anon cannot invoke the entitlement summary projection'
);
select ok(
  has_function_privilege('service_role', 'public.list_user_entitlements(uuid)', 'EXECUTE'),
  'service_role can invoke the entitlement summary projection'
);

select has_function(
  'public',
  'create_feedback',
  ARRAY['text', 'uuid', 'text', 'text', 'text'],
  'feedback command exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.create_feedback(text,uuid,text,text,text)'::regprocedure),
  'feedback command is SECURITY DEFINER'
);
select ok(
  not has_function_privilege('authenticated', 'public.create_feedback(text,uuid,text,text,text)', 'EXECUTE'),
  'authenticated cannot invoke the feedback command directly'
);
select ok(
  has_function_privilege('service_role', 'public.create_feedback(text,uuid,text,text,text)', 'EXECUTE'),
  'service_role can invoke the feedback command through the server API'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '81000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'public-api-user.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.products (id, sku, name, billing_type, status)
    values ('82000000-0000-4000-8000-000000000001', 'PUBLIC_API_PRODUCT', 'Public API Product', 'one_time', 'draft');
    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values ('83000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb);
    select set_config('app.catalog_command', 'set_current', true);
    update platform.products
       set status = 'active', current_version_id = '83000000-0000-4000-8000-000000000001'
     where id = '82000000-0000-4000-8000-000000000001';
    select set_config('app.catalog_command', '', true);
  $$,
  'public API projection fixtures can be created'
);

set local role anon;
select is(
  (select count(*)::integer from public.get_public_products() where sku = 'PUBLIC_API_PRODUCT'),
  1,
  'anon can read the active current product projection'
);
set local role postgres;

set local role service_role;
create temporary table feedback_projection (
  id uuid,
  status text,
  created_at timestamptz
) on commit drop;
select lives_ok(
  $$
    insert into feedback_projection
    select * from public.create_feedback(
      'account',
      '81000000-0000-4000-8000-000000000001',
      'bug',
      'Export issue',
      'The export action is unavailable.'
    );
  $$,
  'service role can create feedback through the command'
);
set local role postgres;
select is(
  (select status from feedback_projection),
  'open',
  'feedback command returns the initial open status'
);
select is(
  (select apps.slug
     from platform.feedback_requests as feedback
     join platform.platform_apps as apps on apps.id = feedback.app_id
    where feedback.id = (select id from feedback_projection)),
  'account',
  'feedback stores the server-resolved application identity'
);
select is(
  (select user_id from platform.feedback_requests where id = (select id from feedback_projection)),
  '81000000-0000-4000-8000-000000000001'::uuid,
  'feedback stores the authenticated user identity'
);

select * from finish();
rollback;
