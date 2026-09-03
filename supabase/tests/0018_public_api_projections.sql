begin;

select plan(12);

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

select * from finish();
rollback;
