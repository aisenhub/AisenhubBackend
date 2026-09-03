begin;

select plan(29);

select has_function(
  'public',
  'complete_account_deletion_request',
  array['uuid', 'uuid', 'uuid'],
  'account deletion completion function exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.complete_account_deletion_request(uuid, uuid, uuid)',
    'EXECUTE'
  ),
  'service_role can complete account deletion'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.complete_account_deletion_request(uuid, uuid, uuid)',
    'EXECUTE'
  ),
  'anon cannot complete account deletion'
);
select ok(
  not (select attnotnull from pg_attribute
        where attrelid = 'platform.feedback_requests'::regclass
          and attname = 'user_id'
          and not attisdropped),
  'feedback direct user link can be cleared'
);

set local role postgres;
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      '9d000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
      'deletion-worker.local@aisenhub.test', 'not-used', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{"display":"Private Name"}'::jsonb,
      now(), now(), false
    );
    update platform.profiles
       set display_name = 'Private Name', avatar_url = 'https://example.test/private.png', locale = 'zh-CN'
     where id = '9d000000-0000-4000-8000-000000000001';
    insert into platform.products (id, sku, name, billing_type, status)
    values ('9d020000-0000-4000-8000-000000000001', 'DELETION_WORKER_PRODUCT', 'Deletion Worker Product', 'one_time', 'draft');
    insert into platform.product_versions (id, product_id, version, status, published_at, sales_terms)
    values ('9d030000-0000-4000-8000-000000000001', '9d020000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb);
    insert into platform.entitlement_grants
      (id, user_id, product_id, product_version_id, source_type, source_id, status)
    values
      ('9d040000-0000-4000-8000-000000000001', '9d000000-0000-4000-8000-000000000001',
       '9d020000-0000-4000-8000-000000000001', '9d030000-0000-4000-8000-000000000001',
       'admin', '9d050000-0000-4000-8000-000000000001', 'active'),
      ('9d040000-0000-4000-8000-000000000002', '9d000000-0000-4000-8000-000000000001',
       '9d020000-0000-4000-8000-000000000001', '9d030000-0000-4000-8000-000000000001',
       'admin', '9d050000-0000-4000-8000-000000000002', 'active');
    insert into platform.orders
      (id, order_no, user_id, customer_ref, currency, amount_total, channel, status, paid_at, fulfilled_at)
    values
      ('9d060000-0000-4000-8000-000000000001', 'AH-P6-DELETION-001', '9d000000-0000-4000-8000-000000000001',
       '9d070000-0000-4000-8000-000000000001', 'USD', 0, 'local', 'fulfilled', now(), now());
    insert into platform.feedback_requests
      (id, app_id, user_id, kind, title, content)
    values
      ('9d080000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
       '9d000000-0000-4000-8000-000000000001', 'support', 'Private feedback title', 'Private feedback content');
    insert into platform.audit_logs
      (id, actor_type, actor_id, action, target_type, target_id, reason, ip_hash, before_summary, after_summary)
    values
      ('9d090000-0000-4000-8000-000000000001', 'user', '9d000000-0000-4000-8000-000000000001',
       'test.user.context', 'user', '9d000000-0000-4000-8000-000000000001', 'test security context',
       'original-ip-hash', '{}'::jsonb, '{}'::jsonb);
    insert into platform.account_deletion_requests
      (id, user_id, status, execute_after, requested_at)
    values
      ('9d0a0000-0000-4000-8000-000000000001', '9d000000-0000-4000-8000-000000000001',
       'pending', now() - interval '1 minute', now() - interval '1 minute');
    update platform.profiles
       set status = 'deletion_pending'
     where id = '9d000000-0000-4000-8000-000000000001';
  $$,
  'deletion fixtures include profile, grants, order, feedback, audit, and request'
);

create temporary table deletion_claim_result on commit drop as
select * from public.claim_account_deletion_request('9d0b0000-0000-4000-8000-000000000001');
select is((select status from deletion_claim_result), 'processing', 'worker claims one due deletion request');

create temporary table deletion_completion_result (payload jsonb) on commit drop;
insert into deletion_completion_result
select public.complete_account_deletion_request(
  '9d0a0000-0000-4000-8000-000000000001',
  '9d0b0000-0000-4000-8000-000000000001',
  '9d0c0000-0000-4000-8000-000000000001'
);

select is((select payload ->> 'status' from deletion_completion_result), 'completed', 'worker completes the deletion transaction');
select is((select payload ->> 'revokedGrantCount' from deletion_completion_result), '2', 'completion reports all revoked Grants');
select is((select payload ->> 'anonymizedFeedbackCount' from deletion_completion_result), '1', 'completion reports anonymized feedback');
select is((select payload ->> 'detachedOrderCount' from deletion_completion_result), '1', 'completion reports detached orders');
select is((select status from platform.account_deletion_requests where id = '9d0a0000-0000-4000-8000-000000000001'), 'completed', 'deletion request becomes completed');
select is((select status from platform.profiles where id = '9d000000-0000-4000-8000-000000000001'), 'deleted', 'profile becomes deleted');
select is((select display_name from platform.profiles where id = '9d000000-0000-4000-8000-000000000001'), null, 'profile display name is cleared');
select is((select avatar_url from platform.profiles where id = '9d000000-0000-4000-8000-000000000001'), null, 'profile avatar is cleared');
select is((select locale from platform.profiles where id = '9d000000-0000-4000-8000-000000000001'), null, 'profile locale is cleared');
select is((select count(*)::integer from platform.entitlement_grants where user_id = '9d000000-0000-4000-8000-000000000001' and status = 'active'), 0, 'no active Grant survives deletion');
select is((select count(*)::integer from platform.entitlement_grants where user_id = '9d000000-0000-4000-8000-000000000001' and status = 'revoked'), 2, 'Grant history is retained as revoked');
select is((select user_id from platform.feedback_requests where id = '9d080000-0000-4000-8000-000000000001'), null, 'feedback direct user link is cleared');
select is((select title from platform.feedback_requests where id = '9d080000-0000-4000-8000-000000000001'), '[deleted]', 'feedback title is anonymized');
select is((select content from platform.feedback_requests where id = '9d080000-0000-4000-8000-000000000001'), '[deleted]', 'feedback content is anonymized');
select is((select user_id from platform.orders where id = '9d060000-0000-4000-8000-000000000001'), null, 'order direct user link is cleared');
select is((select customer_ref from platform.orders where id = '9d060000-0000-4000-8000-000000000001'), '9d070000-0000-4000-8000-000000000001', 'order customer reference is retained');
select is((select ip_hash from platform.audit_logs where id = '9d090000-0000-4000-8000-000000000001'), null, 'user security context is removed from audit');
select is((select count(*)::integer from platform.audit_logs where action = 'account.deletion.completed' and target_id = '9d0a0000-0000-4000-8000-000000000001'), 1, 'completion writes one audit event');
select ok(
  not exists (
    select 1 from platform.audit_logs
     where target_id = '9d0a0000-0000-4000-8000-000000000001'
       and (reason ilike '%email%' or reason ilike '%password%' or reason ilike '%token%' or before_summary::text ilike '%secret%' or after_summary::text ilike '%credential%')
  ),
  'deletion audit contains no direct credential material'
);
select is((select (public.complete_account_deletion_request(
  '9d0a0000-0000-4000-8000-000000000001',
  '9d0b0000-0000-4000-8000-000000000001',
  '9d0c0000-0000-4000-8000-000000000002'
))->>'idempotent'), 'true', 'repeated completion is idempotent');
select is((select count(*)::integer from platform.audit_logs where action = 'account.deletion.completed' and target_id = '9d0a0000-0000-4000-8000-000000000001'), 1, 'repeated completion writes no duplicate audit');
select is((select id from auth.users where id = '9d000000-0000-4000-8000-000000000001'), '9d000000-0000-4000-8000-000000000001', 'Auth identity remains as the stable pseudonymous key');
select ok(
  not exists (
    select 1 from platform.entitlement_grants
     where user_id = '9d000000-0000-4000-8000-000000000001'
       and status = 'active'
  ),
  'deleted account cannot retain an active entitlement'
);

select * from finish();
rollback;
