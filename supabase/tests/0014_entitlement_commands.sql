begin;

select plan(42);

select has_table('platform', 'audit_logs', 'audit log table exists');
select col_is_pk('platform', 'audit_logs', 'id', 'audit log id is the primary key');
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.audit_logs'::regclass),
  'audit logs have RLS enabled'
);
select has_index(
  'platform',
  'audit_logs',
  'audit_logs_target_created_idx',
  'audit target timeline index exists'
);
select has_index(
  'platform',
  'audit_logs',
  'audit_logs_request_id_idx',
  'audit request lookup index exists'
);
select has_table('platform', 'entitlement_restore_links', 'restore policy table exists');
select has_index(
  'platform',
  'entitlement_restore_links',
  'entitlement_restore_links_restored_grant_id_key',
  'restore targets are unique'
);
select ok(
  not has_table_privilege('anon', 'platform.audit_logs', 'SELECT'),
  'anon cannot read audit logs directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.audit_logs', 'INSERT'),
  'service_role cannot insert audit logs directly'
);
select has_function('public', 'grant_entitlement', ARRAY['uuid', 'uuid', 'text', 'uuid', 'timestamp with time zone', 'timestamp with time zone', 'text', 'uuid', 'text', 'uuid', 'uuid'], 'grant command exists');
select has_function('public', 'revoke_entitlement', ARRAY['uuid', 'text', 'uuid', 'text', 'uuid'], 'revoke command exists');
select has_function('public', 'restore_entitlement', ARRAY['uuid', 'uuid', 'text', 'uuid'], 'restore command exists');
select ok(
  (select prosecdef from pg_proc where oid = 'public.grant_entitlement(uuid,uuid,text,uuid,timestamptz,timestamptz,text,uuid,text,uuid,uuid)'::regprocedure),
  'grant command is SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, platform']
   from pg_proc
   where oid = 'public.grant_entitlement(uuid,uuid,text,uuid,timestamptz,timestamptz,text,uuid,text,uuid,uuid)'::regprocedure),
  'grant command fixes its search_path'
);
select ok(
  not has_function_privilege('anon', 'public.grant_entitlement(uuid,uuid,text,uuid,timestamptz,timestamptz,text,uuid,text,uuid,uuid)', 'EXECUTE'),
  'anon cannot invoke grant command'
);
select ok(
  has_function_privilege('service_role', 'public.revoke_entitlement(uuid,text,uuid,text,uuid)', 'EXECUTE'),
  'service_role can invoke revoke command'
);
select lives_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values
      ('43000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
       'entitlement-admin.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
      ('43000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
       'entitlement-user.local@aisenhub.test', 'not-used-by-this-test', now(),
       '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);
  $$,
  'entitlement command actors can be created'
);
select lives_ok(
  $$
    insert into platform.products (id, sku, name, billing_type)
    values ('44000000-0000-4000-8000-000000000001', 'TEST_ENTITLEMENT_PRODUCT', 'Entitlement Test Product', 'one_time');
    insert into platform.product_versions
      (id, product_id, version, status, published_at, sales_terms)
    values ('45000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', 1, 'published', now(), '{}'::jsonb);
    insert into platform.product_version_features
      (product_version_id, feature_id, value)
    values ('45000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'true'::jsonb);
    insert into platform.product_prices
      (id, product_version_id, currency, amount_minor, channel, status)
    values ('46000000-0000-4000-8000-000000000001', '45000000-0000-4000-8000-000000000001', 'USD', 100, 'manual', 'active');
  $$,
  'a published version with a feature and active price is available'
);
select lives_ok(
  $$
    create temporary table admin_grant_result on commit drop as
    select * from public.grant_entitlement(
      '43000000-0000-4000-8000-000000000002',
      '45000000-0000-4000-8000-000000000001',
      'admin', null, now(), null, 'admin',
      '43000000-0000-4000-8000-000000000001',
      'manual entitlement grant', null,
      '47000000-0000-4000-8000-000000000001'
    );
  $$,
  'admin grant uses the common grant operation'
);
select ok(
  (select status = 'active' from admin_grant_result),
  'admin grant is active'
);
select ok(
  (select source_id = audit_log_id from admin_grant_result),
  'admin grant source ID is the audit ID'
);
select ok(
  exists (
    select 1
    from platform.audit_logs as audit
    join admin_grant_result as result on result.audit_log_id = audit.id
    where audit.action = 'entitlements.grant'
      and audit.target_id = result.grant_id
  ),
  'successful grant writes an audit event'
);
select lives_ok(
  $$
    select * from public.grant_entitlement(
      '43000000-0000-4000-8000-000000000002',
      '45000000-0000-4000-8000-000000000001',
      'redemption', '47000000-0000-4000-8000-000000000002', now(), null,
      'system', null, 'redemption fulfillment', null,
      '47000000-0000-4000-8000-000000000002'
    );
  $$,
  'redemption sources reuse the common grant operation'
);
select throws_ok(
  $$
    select * from public.grant_entitlement(
      '43000000-0000-4000-8000-000000000002',
      '45000000-0000-4000-8000-000000000001',
      'redemption', '47000000-0000-4000-8000-000000000002', now(), null,
      'system', null, 'duplicate redemption', null,
      '47000000-0000-4000-8000-000000000003'
    );
  $$,
  '23505', null,
  'duplicate source delivery is rejected atomically'
);
select lives_ok(
  $$
    select * from public.grant_entitlement(
      '43000000-0000-4000-8000-000000000002',
      '45000000-0000-4000-8000-000000000001',
      'order_item', '47000000-0000-4000-8000-000000000004', now(), null,
      'system', null, 'order fulfillment', null,
      '47000000-0000-4000-8000-000000000004'
    );
  $$,
  'order item sources reuse the common grant operation'
);
select throws_ok(
  $$
    select * from public.grant_entitlement(
      '43000000-0000-4000-8000-000000000002',
      '45000000-0000-4000-8000-000000000001',
      'admin', null, now(), null, 'admin',
      '43000000-0000-4000-8000-000000000001', null, null,
      '47000000-0000-4000-8000-000000000005'
    );
  $$,
  '23514', null,
  'admin grants require a reason'
);
select ok(
  not exists (select 1 from platform.audit_logs where request_id = '47000000-0000-4000-8000-000000000005'),
  'failed grant does not leave an audit record'
);
select throws_ok(
  $$
    select * from public.grant_entitlement(
      '43000000-0000-4000-8000-000000000002',
      '45000000-0000-4000-8000-000000000001',
      'admin', '47000000-0000-4000-8000-000000000006', now(), null, 'admin',
      '43000000-0000-4000-8000-000000000001', 'invalid source', null,
      '47000000-0000-4000-8000-000000000006'
    );
  $$,
  '23514', null,
  'admin source IDs cannot bypass audit linkage'
);
select lives_ok(
  $$
    create temporary table revoke_result on commit drop as
    select * from public.revoke_entitlement(
      (select grant_id from admin_grant_result),
      'admin', '43000000-0000-4000-8000-000000000001',
      'manual correction', '47000000-0000-4000-8000-000000000007'
    );
  $$,
  'active grants can be revoked through the common revoke operation'
);
select ok(
  (select status = 'revoked' from platform.entitlement_grants where id = (select grant_id from admin_grant_result)),
  'the original grant is revoked'
);
select ok(
  exists (
    select 1 from platform.audit_logs
    where id = (select audit_log_id from revoke_result)
      and action = 'entitlements.revoke'
  ),
  'successful revoke writes an audit event'
);
select lives_ok(
  $$
    create temporary table restore_result on commit drop as
    select * from public.restore_entitlement(
      (select grant_id from admin_grant_result),
      '43000000-0000-4000-8000-000000000001',
      'restore after correction', '47000000-0000-4000-8000-000000000008'
    );
  $$,
  'restore creates a new grant through the common grant path'
);
select ok(
  (select grant_id <> (select grant_id from admin_grant_result) from restore_result),
  'restore receives a new grant ID'
);
select ok(
  (select source_id = audit_log_id from restore_result),
  'restore source ID is the new audit ID'
);
select ok(
  exists (
    select 1 from platform.entitlement_restore_links
    where restores_grant_id = (select grant_id from admin_grant_result)
      and restored_grant_id = (select grant_id from restore_result)
  ),
  'restore linkage is persisted'
);
select ok(
  (select status = 'revoked' from platform.entitlement_grants where id = (select grant_id from admin_grant_result)),
  'restore does not revive the original grant'
);
select throws_ok(
  $$
    select * from public.restore_entitlement(
      (select grant_id from admin_grant_result),
      '43000000-0000-4000-8000-000000000001',
      'repeat restore', '47000000-0000-4000-8000-000000000009'
    );
  $$,
  '23505', null,
  'a revoked original cannot be restored twice'
);
select throws_ok(
  $$
    update platform.audit_logs
    set reason = 'tampered'
    where id = (select audit_log_id from admin_grant_result);
  $$,
  '23514', null,
  'audit logs cannot be updated'
);
select throws_ok(
  $$
    delete from platform.audit_logs
    where id = (select audit_log_id from admin_grant_result);
  $$,
  '23514', null,
  'audit logs cannot be deleted'
);
select throws_ok(
  $$
    select * from public.restore_entitlement(
      (select id from platform.entitlement_grants where source_type = 'order_item'),
      '43000000-0000-4000-8000-000000000001',
      'cannot restore active grant', '47000000-0000-4000-8000-000000000010'
    );
  $$,
  '23514', null,
  'only revoked grants can be restored'
);
select lives_ok(
  $$
    insert into platform.product_versions
      (id, product_id, version, status, sales_terms)
    values ('48000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', 2, 'draft', '{}'::jsonb);
  $$,
  'a draft version is available for grant rejection'
);
select throws_ok(
  $$
    select * from public.grant_entitlement(
      '43000000-0000-4000-8000-000000000002',
      '48000000-0000-4000-8000-000000000001',
      'admin', null, now(), null, 'admin',
      '43000000-0000-4000-8000-000000000001', 'draft version rejection', null,
      '47000000-0000-0000-8000-000000000011'
    );
  $$,
  '23514', null,
  'grants cannot reference draft versions'
);

select * from finish();
rollback;
