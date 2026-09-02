begin;

select plan(17);

select has_function(
  'public',
  'admin_operations_overview',
  array['uuid'],
  'Admin operations overview function exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.admin_operations_overview(uuid)'::regprocedure),
  true,
  'Admin operations overview is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.admin_operations_overview(uuid)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[],
  'Admin operations overview pins search_path'
);
select ok(
  has_function_privilege('service_role', 'public.admin_operations_overview(uuid)', 'EXECUTE'),
  'service_role can read Admin operations overview'
);
select ok(
  not has_function_privilege('anon', 'public.admin_operations_overview(uuid)', 'EXECUTE'),
  'anon cannot read Admin operations overview'
);

set local role postgres;

select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('9f000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
       'operations-overview-owner@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false),
      ('9f000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
       'operations-overview-finance@aisenhub.test', 'not-used', now(), '{}', '{}', now(), now(), false);
    insert into platform.admin_members (user_id, role, status)
    values
      ('9f000000-0000-0000-0000-000000000001', 'owner', 'active'),
      ('9f000000-0000-0000-0000-000000000004', 'finance', 'active');
  $$,
  'overview role fixtures can be created'
);

select lives_ok(
  $$
    select public.admin_operations_overview('9f000000-0000-0000-0000-000000000001'::uuid);
  $$,
  'owner can read the fixed operations overview'
);

select ok(
  (select public.admin_operations_overview('9f000000-0000-0000-0000-000000000001'::uuid) ? 'generatedAt'),
  'overview includes a generation timestamp'
);
select ok(
  (select jsonb_typeof(public.admin_operations_overview('9f000000-0000-0000-0000-000000000001'::uuid) -> 'cards') = 'array'),
  'overview cards are an array'
);
select ok(
  (select not (public.admin_operations_overview('9f000000-0000-0000-0000-000000000001'::uuid)::text ~* '(email|token|secret|password|sql|table)')),
  'overview does not expose sensitive or query internals'
);
select ok(
  (select bool_and(card ?& array['key', 'label', 'count', 'severity', 'href'])
     from jsonb_array_elements(public.admin_operations_overview('9f000000-0000-0000-0000-000000000001'::uuid) -> 'cards') as card),
  'every card has the fixed safe shape'
);
select ok(
  (select bool_and((card ->> 'href') in (
    '/orders?status=pending', '/orders?status=paid', '/orders?status=chargeback',
    '/users?status=deletion_pending', '/feedback?status=open'
  )) from jsonb_array_elements(public.admin_operations_overview('9f000000-0000-0000-0000-000000000001'::uuid) -> 'cards') as card),
  'every card drills down to an allowlisted route'
);
select ok(
  (select count(*) >= 3 from jsonb_array_elements(public.admin_operations_overview('9f000000-0000-0000-0000-000000000001'::uuid) -> 'cards')),
  'owner receives the core operational cards'
);

select lives_ok(
  $$
    select public.admin_operations_overview('9f000000-0000-0000-0000-000000000004'::uuid);
  $$,
  'finance can read the fixed operations overview'
);
select is(
  (select count(*) from jsonb_array_elements(public.admin_operations_overview('9f000000-0000-0000-0000-000000000004'::uuid) -> 'cards') as card where card ->> 'key' = 'open-feedback'),
  0::bigint,
  'finance does not receive the feedback card'
);
select is(
  (select count(*) from jsonb_array_elements(public.admin_operations_overview('9f000000-0000-0000-0000-000000000004'::uuid) -> 'cards') as card where card ->> 'key' = 'chargeback-orders'),
  1::bigint,
  'finance receives the chargeback card'
);

select throws_ok(
  $$ select public.admin_operations_overview('00000000-0000-0000-0000-000000000099'::uuid); $$,
  '42501',
  'Active Admin membership is required',
  'inactive or unknown Admin members are denied'
);

select * from finish();
rollback;
