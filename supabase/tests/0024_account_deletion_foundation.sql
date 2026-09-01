begin;

select plan(38);

select has_table('platform', 'account_deletion_requests', 'account deletion request table exists');
select ok(
  to_regclass('platform.account_deletion_requests_one_open_idx') is not null,
  'one-open-request partial unique index exists'
);
select has_function('public', 'request_account_deletion', array['uuid', 'text', 'text', 'uuid'], 'request function exists');
select has_function('public', 'cancel_account_deletion', array['uuid', 'uuid'], 'cancel function exists');
select has_function('public', 'claim_account_deletion_request', array['uuid'], 'worker claim function exists');
select has_function('public', 'fail_account_deletion_request', array['uuid', 'uuid', 'text'], 'worker failure function exists');
select is(
  (select prosecdef from pg_proc where oid = 'public.request_account_deletion(uuid,text,text,uuid)'::regprocedure),
  true,
  'request function is SECURITY DEFINER'
);
select is(
  (select proconfig from pg_proc where oid = 'public.request_account_deletion(uuid,text,text,uuid)'::regprocedure),
  array['search_path=pg_catalog, platform']::text[],
  'request function pins search_path'
);
select has_function_privilege(
  'service_role',
  'public.request_account_deletion(uuid,text,text,uuid)',
  'EXECUTE'
);
select ok(
  not has_function_privilege('anon', 'public.request_account_deletion(uuid,text,text,uuid)', 'EXECUTE'),
  'anon cannot invoke the deletion request function'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (id, email)
    values ('95000000-0000-4000-8000-000000000001', 'deletion-foundation.local@aisenhub.test');
    update platform.profiles
       set display_name = 'Deletion Fixture', avatar_url = 'https://example.test/avatar.png', locale = 'zh-CN'
     where id = '95000000-0000-4000-8000-000000000001';
  $$,
  'deletion fixture user can be created'
);
select lives_ok(
  $$
    insert into platform.platform_sessions
      (user_id, token_hash, csrf_hash, expires_at, last_seen_at)
    values
      ('95000000-0000-4000-8000-000000000001', 'deletion-session-1', 'deletion-csrf-1', now() + interval '1 day', now()),
      ('95000000-0000-4000-8000-000000000001', 'deletion-session-2', 'deletion-csrf-2', now() + interval '1 day', now());
  $$,
  'deletion fixture sessions can be created'
);
select lives_ok(
  $$
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id)
    values
      ('95000000-0000-4000-8000-000000000010', '95000000-0000-4000-8000-000000000001',
       '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
       'promotion', '95000000-0000-4000-8000-000000000011');
  $$,
  'deletion fixture entitlement can be created'
);

set local role service_role;
create temporary table deletion_result (
  deletion_request_id uuid,
  status text,
  execute_after timestamptz,
  requested_at timestamptz,
  completed_at timestamptz
) on commit drop;
select lives_ok(
  $$
    insert into deletion_result
    select * from public.request_account_deletion(
      '95000000-0000-4000-8000-000000000001',
      'deletion-request-key-1',
      'deletion-request-hash-1',
      '95000000-0000-4000-8000-000000000020'
    );
  $$,
  'request creates a pending deletion workflow'
);
set local role postgres;
select is((select status from deletion_result), 'pending', 'request starts pending');
select is(
  (select status from platform.profiles where id = '95000000-0000-4000-8000-000000000001'),
  'deletion_pending',
  'request freezes the profile'
);
select is(
  (select count(*)::integer from platform.platform_sessions
    where user_id = '95000000-0000-4000-8000-000000000001' and revoked_at is not null),
  2,
  'request revokes every platform session'
);
select is(
  (select status from platform.entitlement_grants where id = '95000000-0000-4000-8000-000000000010'),
  'active',
  'request does not delete financial entitlement history prematurely'
);

set local role service_role;
select lives_ok(
  $$
    insert into deletion_result
    select * from public.request_account_deletion(
      '95000000-0000-4000-8000-000000000001',
      'deletion-request-key-1',
      'deletion-request-hash-1',
      '95000000-0000-4000-8000-000000000021'
    );
  $$,
  'same idempotency key replays the request safely'
);
select is(
  (select count(*)::integer from deletion_result where deletion_request_id = (select deletion_request_id from deletion_result limit 1)),
  2,
  'idempotent replay returns the same request'
);
select throws_ok(
  $$
    select * from public.request_account_deletion(
      '95000000-0000-4000-8000-000000000001', 'deletion-request-key-1', 'different-hash', null
    );
  $$,
  'P0001', null,
  'same idempotency key cannot change request hash'
);
set local role postgres;
update platform.profiles
   set status = 'active'
 where id = '95000000-0000-4000-8000-000000000001';
set local role service_role;
select throws_ok(
  $$
    select * from public.request_account_deletion(
      '95000000-0000-4000-8000-000000000001', 'deletion-request-key-2', 'deletion-request-hash-2', null
    );
  $$,
  '23505', null,
  'one open deletion request is enforced'
);

create temporary table cancel_result (
  deletion_request_id uuid,
  status text,
  execute_after timestamptz,
  requested_at timestamptz,
  completed_at timestamptz
) on commit drop;
select lives_ok(
  $$
    insert into cancel_result
    select * from public.cancel_account_deletion(
      '95000000-0000-4000-8000-000000000001',
      '95000000-0000-4000-8000-000000000022'
    );
  $$,
  'pending deletion can be cancelled'
);
set local role postgres;
select is((select status from cancel_result), 'cancelled', 'cancel transitions to cancelled');
select is(
  (select status from platform.profiles where id = '95000000-0000-4000-8000-000000000001'),
  'active',
  'cancel restores profile activity'
);

set local role service_role;
truncate deletion_result;
select lives_ok(
  $$
    insert into deletion_result
    select * from public.request_account_deletion(
      '95000000-0000-4000-8000-000000000001',
      'deletion-request-key-3',
      'deletion-request-hash-3',
      '95000000-0000-4000-8000-000000000023'
    );
  $$,
  'a cancelled account can start a new deletion request'
);

create temporary table claim_result (
  deletion_request_id uuid,
  user_id uuid,
  status text,
  attempt_count integer,
  execute_after timestamptz,
  processing_started_at timestamptz
) on commit drop;
select lives_ok(
  $$
    insert into claim_result
    select * from public.claim_account_deletion_request('95000000-0000-0000-0000-000000000030');
  $$,
  'worker can claim a due request'
);
select is((select status from claim_result), 'processing', 'claim transitions to processing');
select is((select attempt_count from claim_result), 1, 'first claim increments attempt count');
select is(
  (select count(*)::integer from public.claim_account_deletion_request('95000000-0000-0000-0000-000000000031')),
  0,
  'a processing request cannot be claimed twice'
);
select throws_ok(
  $$
    select * from public.fail_account_deletion_request(
      (select deletion_request_id from claim_result),
      '95000000-0000-0000-0000-000000000031',
      'DATABASE_STEP_FAILED'
    );
  $$,
  '42501', null,
  'only the owning worker can mark a request failed'
);
create temporary table failure_result (
  deletion_request_id uuid,
  status text,
  attempt_count integer,
  next_attempt_at timestamptz,
  last_error_code text
) on commit drop;
select lives_ok(
  $$
    insert into failure_result
    select * from public.fail_account_deletion_request(
      (select deletion_request_id from claim_result),
      '95000000-0000-0000-0000-000000000030',
      'DATABASE_STEP_FAILED'
    );
  $$,
  'worker can record a stable retryable failure'
);
select is((select status from failure_result), 'failed', 'failure transitions to failed');
select is((select last_error_code from failure_result), 'DATABASE_STEP_FAILED', 'only stable error code is retained');
set local role postgres;
select lives_ok(
  $$
    update platform.account_deletion_requests
       set next_attempt_at = now() - interval '1 second'
     where id = (select deletion_request_id from claim_result);
  $$,
  'test can make the failed request due for retry'
);
set local role service_role;
truncate claim_result;
select lives_ok(
  $$
    insert into claim_result
    select * from public.claim_account_deletion_request('95000000-0000-0000-0000-000000000032');
  $$,
  'worker can retry a failed request'
);
select is((select attempt_count from claim_result), 2, 'retry increments attempt count');
select throws_ok(
  $$
    select * from public.cancel_account_deletion(
      '95000000-0000-4000-8000-000000000001', null
    );
  $$,
  '23514', null,
  'processing deletion cannot be cancelled'
);

set local role postgres;
select throws_ok(
  $$ delete from auth.users where id = '95000000-0000-4000-8000-000000000001'; $$,
  '23503', null,
  'account deletion request retains the identity link until the controlled workflow completes'
);

select * from finish();
rollback;
