begin;

select plan(6);

select has_function(
  'public',
  'resolve_admin_membership',
  array['uuid'],
  'Admin bearer membership resolver exists'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.resolve_admin_membership(uuid)'::regprocedure),
  true,
  'Admin bearer membership resolver is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.resolve_admin_membership(uuid)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[],
  'Admin bearer membership resolver pins search_path'
);
select ok(
  has_function_privilege('service_role', 'public.resolve_admin_membership(uuid)', 'EXECUTE'),
  'service_role can resolve Admin membership'
);
select ok(
  not has_function_privilege('anon', 'public.resolve_admin_membership(uuid)', 'EXECUTE'),
  'anon cannot resolve Admin membership'
);
select ok(
  not has_function_privilege('authenticated', 'public.resolve_admin_membership(uuid)', 'EXECUTE'),
  'authenticated cannot resolve Admin membership directly'
);

select * from finish();
rollback;
