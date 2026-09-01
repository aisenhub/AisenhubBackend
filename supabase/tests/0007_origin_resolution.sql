begin;

select plan(10);

select ok(
  to_regprocedure('public.resolve_app_origin(text)') is not null,
  'exact Origin resolver exists'
);
select ok(
  has_function_privilege('anon', 'public.resolve_app_origin(text)', 'EXECUTE'),
  'anon can resolve an exact Origin'
);
select ok(
  has_function_privilege('authenticated', 'public.resolve_app_origin(text)', 'EXECUTE'),
  'authenticated can resolve an exact Origin'
);
select ok(
  not has_function_privilege('service_role', 'public.resolve_app_origin(text)', 'EXECUTE'),
  'service_role does not receive direct Origin resolver execution'
);
select ok(
  exists (
    select 1
      from pg_proc
     where oid = 'public.resolve_app_origin(text)'::regprocedure
       and prosecdef
       and proconfig @> array['search_path=pg_catalog, platform']::text[]
  ),
  'Origin resolver uses SECURITY DEFINER with a fixed search_path'
);

set local role anon;
select is(
  (select app_slug from public.resolve_app_origin('http://localhost:5173')),
  'account',
  'registered exact Origin resolves to the Account app'
);
select is(
  (select count(*)::integer from public.resolve_app_origin('http://localhost:5173/')),
  0,
  'an Origin with a path is not accepted'
);
select is(
  (select count(*)::integer from public.resolve_app_origin('null')),
  0,
  'the browser null Origin is not accepted'
);
select is(
  (select count(*)::integer from public.resolve_app_origin('https://attacker.example')),
  0,
  'an unregistered Origin is not accepted'
);
select is(
  (select count(*)::integer from public.resolve_app_origin('*')),
  0,
  'a wildcard Origin is not accepted'
);

select * from finish();
rollback;
