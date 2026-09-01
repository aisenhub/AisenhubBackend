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
  ('21000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000003', 'development', 'http://localhost:5174');
--
-- Keep this file available for deterministic non-Auth seed data introduced by
-- later phases. Never add production data or production credentials here.
