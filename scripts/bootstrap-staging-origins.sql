-- One-time Staging bootstrap only. This file contains no credentials.
-- It must not be used against Local or Production.

begin;

insert into platform.platform_apps
  (id, slug, name, category, status, metadata)
values
  ('20000000-0000-4000-8000-000000000002', 'account', 'AisenHub Account', 'platform', 'active', '{"surface":"account"}'::jsonb),
  ('20000000-0000-4000-8000-000000000003', 'admin', 'AisenHub Admin', 'platform', 'active', '{"surface":"admin"}'::jsonb)
on conflict (slug) do nothing;

insert into platform.app_origins (app_id, environment, origin)
select app.id, 'staging', origins.origin
  from platform.platform_apps as app
  join (values
    ('account', 'https://aisenhub-backend-account-olive.vercel.app'),
    ('admin', 'https://aisenhub-backend-admin.vercel.app')
  ) as origins(slug, origin) on origins.slug = app.slug
on conflict (origin) do update
  set is_active = true
  where platform.app_origins.app_id = excluded.app_id
    and platform.app_origins.environment = excluded.environment;

commit;
