begin;

select plan(15);

select has_function(
  'public',
  'admin_query_resource',
  array['uuid', 'text', 'text', 'integer', 'text', 'text', 'text', 'text'],
  'Admin resource query projection exists'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.admin_query_resource(uuid,text,text,integer,text,text,text,text)'::regprocedure),
  'Admin resource query projection is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']::text[]
   from pg_proc
   where oid = 'public.admin_query_resource(uuid,text,text,integer,text,text,text,text)'::regprocedure),
  'Admin resource query projection fixes its search_path'
);
select ok(
  has_function_privilege('service_role', 'public.admin_query_resource(uuid,text,text,integer,text,text,text,text)', 'EXECUTE'),
  'service_role can invoke the Admin query projection'
);
select ok(
  not has_function_privilege('anon', 'public.admin_query_resource(uuid,text,text,integer,text,text,text,text)', 'EXECUTE'),
  'anon cannot invoke the Admin query projection'
);

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '91000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'admin-query-owner.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.admin_members (user_id, role) values ('91000000-0000-4000-8000-000000000001', 'owner');
  $$,
  'Admin query fixture owner can be created'
);

set local role service_role;
select ok(
  (public.admin_query_resource(
    '91000000-0000-4000-8000-000000000001', 'applications', null, 10, 'aisenlens', null, 'slug', 'asc'
  )->'items'->0->>'slug') = 'aisenlens',
  'owner can read an allowlisted application projection'
);
select ok(
  ((public.admin_query_resource(
    '91000000-0000-4000-8000-000000000001', 'applications', null, 1, null, null, 'slug', 'asc'
  )->'page'->>'hasMore')::boolean),
  'application projection returns stable page metadata'
);
select throws_ok(
  $$ select public.admin_query_resource('91000000-0000-4000-8000-000000000001', 'platform_users', null, 10, null, null, 'createdAt', 'desc'); $$,
  '22023', null,
  'unknown resources are rejected'
);
select throws_ok(
  $$ select public.admin_query_resource('91000000-0000-4000-8000-000000000001', 'applications', null, 10, null, null, 'unsafeExpression', 'desc'); $$,
  '22023', null,
  'unknown sort fields are rejected'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '91000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
      'admin-query-finance.local@aisenhub.test', 'not-used-by-this-test', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false
    );
    insert into platform.admin_members (user_id, role) values ('91000000-0000-4000-8000-000000000002', 'finance');
  $$,
  'Admin query fixture finance member can be created'
);
set local role service_role;
select throws_ok(
  $$ select public.admin_query_resource('91000000-0000-4000-8000-000000000002', 'applications', null, 10, null, null, 'slug', 'asc'); $$,
  '42501', null,
  'finance cannot read the applications action without permission'
);
select is(
  public.admin_query_resource('91000000-0000-4000-8000-000000000002', 'users', null, 10, '91000000-0000-4000-8000-000000000002', null, 'createdAt', 'asc')->'items'->0->>'displayName',
  null,
  'finance user projection redacts display name'
);

set local role postgres;
select lives_ok(
  $$
    insert into platform.feedback_requests (id, app_id, user_id, kind, title, content)
    values (
      '91000000-0000-4000-8000-000000000003',
      '20000000-0000-4000-8000-000000000003',
      '91000000-0000-4000-8000-000000000002',
      'bug', 'Finance private content', 'This content must be redacted for finance.'
    );
  $$,
  'feedback redaction fixture can be created'
);
set local role service_role;
select is(
  public.admin_query_resource('91000000-0000-4000-8000-000000000002', 'feedback', null, 10, 'Finance private content', null, 'createdAt', 'asc')->'items'->0->>'content',
  null,
  'finance feedback projection redacts content'
);

set local role postgres;
select * from finish();
rollback;
