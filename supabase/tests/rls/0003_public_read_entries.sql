begin;

select plan(7);

select ok(
  has_function_privilege('anon', 'public.get_public_app(text)', 'EXECUTE'),
  'anon can execute the public application read entry'
);
select ok(
  has_function_privilege('authenticated', 'public.get_public_app(text)', 'EXECUTE'),
  'authenticated can execute the public application read entry'
);
select ok(
  not has_function_privilege('service_role', 'public.get_public_app(text)', 'EXECUTE'),
  'service_role is not granted public application read execution'
);
select ok(
  exists (
    select 1
    from pg_proc
    where oid = 'public.get_public_app(text)'::regprocedure
      and prosecdef
      and proconfig @> array['search_path=pg_catalog, platform']::text[]
  ),
  'public application read entry uses a fixed search path'
);

set local role anon;
select is(
  (select count(*)::integer from public.get_public_app('aisenlens')),
  1,
  'anon can read one active application projection'
);
select is(
  (select count(*)::integer from public.get_public_app('missing-app')),
  0,
  'missing applications return no projection rows'
);
select is(
  (select count(*)::integer from public.get_public_app('account')),
  1,
  'active applications remain available to public reads'
);

select * from finish();
rollback;
