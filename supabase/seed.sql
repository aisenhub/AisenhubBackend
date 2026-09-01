-- AisenHub Platform Local-only seed entrypoint.
--
-- Auth fixtures are created by `pnpm fixtures:verify` through the Local Auth
-- Admin API. This is intentional: direct writes to auth.users are not a
-- supported way to make users visible to the running GoTrue service.
-- The profile lifecycle trigger creates one platform profile per fixture.
-- Local Admin memberships are added after Auth setup by verify-fixtures.mjs.
-- Auth users are intentionally not inserted directly into this SQL seed.

insert into platform.platform_apps
  (id, slug, name, category, status, metadata)
values
  ('20000000-0000-4000-8000-000000000001', 'aisenlens', 'AisenLens', 'tool', 'active', '{"surface":"product"}'::jsonb),
  ('20000000-0000-4000-8000-000000000002', 'account', 'AisenHub Account', 'platform', 'active', '{"surface":"account"}'::jsonb),
  ('20000000-0000-4000-8000-000000000003', 'admin', 'AisenHub Admin', 'platform', 'active', '{"surface":"admin"}'::jsonb);

insert into platform.app_origins
  (id, app_id, environment, origin)
values
  ('21000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', 'development', 'http://localhost:5173'),
  ('21000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000003', 'development', 'http://localhost:5174'),
  ('21000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', 'development', 'http://localhost:5175');

insert into platform.features
  (id, app_id, code, name, value_type, status, merge_strategy)
values
  ('22000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'aisenlens.app.access', 'AisenLens app access', 'boolean', 'active', 'any_true'),
  ('22000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', 'aisenlens.supporter_feedback', 'AisenLens supporter feedback', 'boolean', 'active', 'any_true'),
  ('22000000-0000-4000-8000-000000000003', null, 'hub.remove_ads', 'Remove platform advertising', 'boolean', 'active', 'any_true'),
  ('22000000-0000-4000-8000-000000000004', null, 'hub.all_apps_access', 'Access all active applications', 'boolean', 'active', 'any_true');

update platform.platform_apps
set primary_feature_id = '22000000-0000-4000-8000-000000000001'
where id = '20000000-0000-4000-8000-000000000001';

insert into platform.products
  (id, sku, name, billing_type, status, entitlement_policy)
values
  ('23000000-0000-4000-8000-000000000001', 'AISENLENS_LIFETIME', 'AisenLens Lifetime', 'one_time', 'draft', 'snapshot');

insert into platform.product_versions
  (id, product_id, version, status, access_duration_days, sales_terms)
values
  ('24000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', 1, 'draft', null, '{"label":"AisenLens Lifetime"}'::jsonb);

insert into platform.product_version_features
  (product_version_id, feature_id, value)
values
  ('24000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'true'::jsonb),
  ('24000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000002', 'true'::jsonb);

insert into platform.product_prices
  (id, product_version_id, currency, amount_minor, channel, status, valid_from)
values
  ('27000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'USD', 0, 'manual', 'draft', now());

--
-- Keep this file available for deterministic non-Auth seed data introduced by
-- later phases. Never add production data or production credentials here.
