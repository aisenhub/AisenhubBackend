-- Local-only Catalog / Entitlement / Redemption fixtures.
-- Auth users are created by scripts/verify-fixtures.mjs before this file runs.
-- No redemption plaintext is stored; code_hash contains only deterministic test digests.

do $fixture$
begin

if (select status from platform.product_versions where id = '24000000-0000-4000-8000-000000000001') = 'draft' then
  perform * from public.publish_product_version('24000000-0000-4000-8000-000000000001');
end if;

update platform.product_prices
   set status = 'active'
 where id = '27000000-0000-4000-8000-000000000001';

perform * from public.set_current_product_version(
  '23000000-0000-4000-8000-000000000001',
  '24000000-0000-4000-8000-000000000001'
);

update platform.products
   set status = 'active'
 where id = '23000000-0000-4000-8000-000000000001';

if not exists (
  select 1 from platform.products
   where id = '23000000-0000-4000-8000-000000000001'
     and sku = 'AISENLENS_LIFETIME'
     and status = 'active'
     and current_version_id = '24000000-0000-4000-8000-000000000001'
) then
  raise exception 'AisenLens active current product fixture is missing';
end if;
if not exists (
  select 1 from platform.product_versions
   where id = '24000000-0000-4000-8000-000000000001'
     and status = 'published'
     and access_duration_days is null
) then
  raise exception 'AisenLens published lifetime version fixture is missing';
end if;
if (select count(*) from platform.product_version_features where product_version_id = '24000000-0000-4000-8000-000000000001') <> 2 then
  raise exception 'AisenLens feature snapshot fixture count is not stable';
end if;
if not exists (
  select 1 from platform.product_prices
   where id = '27000000-0000-4000-8000-000000000001'
     and status = 'active'
) then
  raise exception 'AisenLens active local price fixture is missing';
end if;

insert into platform.redemption_batches
  (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit,
   status, starts_at, expires_at, source, created_by)
values
  ('30000000-0000-4000-8000-000000000001', 'Local Active Batch',
   '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
   'AH-LOCAL-ACTIVE', 2, 1, 'active', now() - interval '1 hour', null,
   'local-fixture', '10000000-0000-4000-8000-000000000002'),
  ('30000000-0000-4000-8000-000000000002', 'Local Paused Batch',
   '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
   'AH-LOCAL-PAUSED', 1, 1, 'paused', now() - interval '1 hour', null,
   'local-fixture', '10000000-0000-4000-8000-000000000002'),
  ('30000000-0000-4000-8000-000000000003', 'Local Expired Batch',
   '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
   'AH-LOCAL-EXPIRED', 1, 1, 'active', now() - interval '2 days', now() - interval '1 day',
   'local-fixture', '10000000-0000-4000-8000-000000000002'),
  ('30000000-0000-4000-8000-000000000004', 'Local Closed Batch',
   '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
   'AH-LOCAL-CLOSED', 1, 1, 'closed', now() - interval '1 hour', null,
   'local-fixture', '10000000-0000-4000-8000-000000000002')
on conflict (id) do nothing;

insert into platform.redemption_codes
  (id, batch_id, code_hash, code_hint, pepper_version, status)
values
  ('31000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', repeat('a', 64), 'AH-LOCAL-ACTIVE-****-0001', 1, 'issued'),
  ('31000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', repeat('b', 64), 'AH-LOCAL-ACTIVE-****-0002', 1, 'issued'),
  ('31000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000002', repeat('c', 64), 'AH-LOCAL-PAUSED-****-0001', 1, 'issued'),
  ('31000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000003', repeat('d', 64), 'AH-LOCAL-EXPIRED-****-0001', 1, 'issued')
on conflict (id) do nothing;

insert into platform.audit_logs
  (id, actor_type, actor_id, action, target_type, target_id, reason, before_summary, after_summary)
values
  ('32000000-0000-4000-8000-000000000001', 'admin', '10000000-0000-4000-8000-000000000002', 'entitlements.grant', 'entitlement_grant', '33000000-0000-4000-8000-000000000001', 'Local active entitlement fixture', '{}'::jsonb, '{}'::jsonb),
  ('32000000-0000-4000-8000-000000000002', 'admin', '10000000-0000-4000-8000-000000000002', 'entitlements.grant', 'entitlement_grant', '33000000-0000-4000-8000-000000000002', 'Local expired entitlement fixture', '{}'::jsonb, '{}'::jsonb),
  ('32000000-0000-4000-8000-000000000003', 'admin', '10000000-0000-4000-8000-000000000002', 'entitlements.grant', 'entitlement_grant', '33000000-0000-4000-8000-000000000003', 'Local revoked entitlement fixture', '{}'::jsonb, '{}'::jsonb)
on conflict (id) do nothing;

insert into platform.entitlement_grants
  (id, user_id, product_id, product_version_id, source_type, source_id, status,
   starts_at, expires_at, revoked_at, revoke_reason, created_at)
values
  ('33000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000005',
   '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
   'admin', '32000000-0000-4000-8000-000000000001', 'active',
   now() - interval '1 hour', null, null, null, now() - interval '1 hour'),
  ('33000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000005',
   '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
   'admin', '32000000-0000-4000-8000-000000000002', 'active',
   now() - interval '3 days', now() - interval '1 day', null, null, now() - interval '3 days'),
  ('33000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000005',
   '23000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001',
   'admin', '32000000-0000-4000-8000-000000000003', 'revoked',
   now() - interval '4 days', null, now() - interval '2 days', 'Local revoked entitlement fixture', now() - interval '4 days')
on conflict (id) do nothing;

  if (select count(*) from platform.redemption_batches) <> 4 then
    raise exception 'Local redemption batch fixture count is not stable';
  end if;
  if (select count(*) from platform.redemption_codes) <> 4 then
    raise exception 'Local redemption code fixture count is not stable';
  end if;
  if exists (select 1 from platform.redemption_codes where length(code_hash) <> 64) then
    raise exception 'Local redemption fixture contains a non-digest code';
  end if;
  if (select count(*) from platform.entitlement_grants where user_id = '10000000-0000-4000-8000-000000000005') <> 3 then
    raise exception 'Local entitlement fixture count is not stable';
  end if;
  if not exists (select 1 from platform.entitlement_grants where id = '33000000-0000-4000-8000-000000000001' and status = 'active' and expires_at is null) then
    raise exception 'Local active entitlement fixture is missing';
  end if;
  if not exists (select 1 from platform.entitlement_grants where id = '33000000-0000-4000-8000-000000000002' and status = 'active' and expires_at < now()) then
    raise exception 'Local expired entitlement fixture is missing';
  end if;
  if not exists (select 1 from platform.entitlement_grants where id = '33000000-0000-4000-8000-000000000003' and status = 'revoked') then
    raise exception 'Local revoked entitlement fixture is missing';
  end if;
end;
$fixture$;
