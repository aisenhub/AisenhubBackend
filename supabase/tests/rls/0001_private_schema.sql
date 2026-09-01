begin;

select plan(6);

select ok(
  not has_schema_privilege('anon', 'platform', 'USAGE'),
  'anon cannot use the private platform schema'
);
select ok(
  not has_schema_privilege('authenticated', 'platform', 'USAGE'),
  'authenticated cannot use the private platform schema'
);
select ok(
  not has_table_privilege('anon', 'platform.idempotency_records', 'SELECT'),
  'anon cannot select private idempotency records'
);
select ok(
  not has_table_privilege('authenticated', 'platform.idempotency_records', 'SELECT'),
  'authenticated cannot select private idempotency records'
);
select ok(
  not has_table_privilege('service_role', 'platform.idempotency_records', 'INSERT'),
  'service_role cannot insert private idempotency records directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.idempotency_records', 'UPDATE'),
  'service_role cannot update private idempotency records directly'
);

select * from finish();
rollback;
