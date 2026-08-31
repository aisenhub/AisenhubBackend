begin;

select plan(14);

select has_schema('platform', 'private platform schema exists');
select has_table('platform', 'idempotency_records', 'idempotency table exists');
select col_is_pk('platform', 'idempotency_records', 'id', 'id is the primary key');
select col_not_null('platform', 'idempotency_records', 'scope', 'scope is required');
select col_not_null('platform', 'idempotency_records', 'request_hash', 'request hash is required');
select col_not_null('platform', 'idempotency_records', 'expires_at', 'expiry is required');
select ok(
  not has_schema_privilege('anon', 'platform', 'USAGE'),
  'anon cannot use the private platform schema'
);
select ok(
  not has_schema_privilege('authenticated', 'platform', 'USAGE'),
  'authenticated cannot use the private platform schema'
);
select has_index(
  'platform',
  'idempotency_records',
  'idempotency_records_scope_actor_key_unique',
  'idempotency key scope is unique'
);
select ok(
  not has_function_privilege('anon', 'platform.set_updated_at()', 'EXECUTE'),
  'anon cannot execute the updated-at trigger function'
);
select ok(
  not has_function_privilege('authenticated', 'platform.set_updated_at()', 'EXECUTE'),
  'authenticated cannot execute the updated-at trigger function'
);
select ok(
  not has_function_privilege('service_role', 'platform.set_updated_at()', 'EXECUTE'),
  'service_role cannot execute the updated-at trigger function directly'
);

select throws_ok(
  $$
    insert into platform.idempotency_records
      (scope, actor_key, idempotency_key, request_hash, expires_at)
    values
      ('test.scope', 'test.actor', 'test-key', 'hash-a', now());
    insert into platform.idempotency_records
      (scope, actor_key, idempotency_key, request_hash, expires_at)
    values
      ('test.scope', 'test.actor', 'test-key', 'hash-b', now());
  $$,
  '23505',
  null,
  'same scoped key cannot be inserted twice, including with a different hash'
);

select throws_ok(
  $$
    insert into platform.idempotency_records
      (scope, actor_key, idempotency_key, request_hash, expires_at)
    values
      ('test.scope.invalid', 'test.actor', '   ', 'hash', now());
  $$,
  '23514',
  null,
  'blank idempotency keys are rejected'
);

select * from finish();
rollback;
