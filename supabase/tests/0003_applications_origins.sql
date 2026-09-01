begin;

select plan(28);

select has_table('platform', 'platform_apps', 'application registry exists');
select has_table('platform', 'app_origins', 'application Origin registry exists');
select col_is_pk('platform', 'platform_apps', 'id', 'application id is the primary key');
select col_is_pk('platform', 'app_origins', 'id', 'Origin id is the primary key');
select has_index(
  'platform',
  'platform_apps',
  'platform_apps_slug_key',
  'application slugs are unique'
);
select has_index(
  'platform',
  'app_origins',
  'app_origins_origin_key',
  'Origins are globally unique'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.platform_apps'::regclass),
  'application registry has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'platform.app_origins'::regclass),
  'Origin registry has RLS enabled'
);
select ok(
  not has_table_privilege('anon', 'platform.platform_apps', 'SELECT'),
  'anon cannot read applications directly'
);
select ok(
  not has_table_privilege('authenticated', 'platform.app_origins', 'SELECT'),
  'authenticated cannot read Origins directly'
);
select ok(
  not has_table_privilege('service_role', 'platform.platform_apps', 'INSERT'),
  'service_role cannot insert applications directly'
);
select ok(
  not has_function_privilege('anon', 'platform.prevent_origin_identity_change()', 'EXECUTE'),
  'anon cannot execute Origin identity trigger directly'
);

select ok(
  exists (
    select 1
    from platform.platform_apps
    where id = '20000000-0000-4000-8000-000000000001'
      and slug = 'aisenlens'
      and status = 'active'
  ),
  'AisenLens seed application is deterministic'
);
select ok(
  exists (
    select 1
    from platform.platform_apps
    where id = '20000000-0000-4000-8000-000000000002'
      and slug = 'account'
  ),
  'Account seed application exists'
);
select ok(
  exists (
    select 1
    from platform.platform_apps
    where id = '20000000-0000-4000-8000-000000000003'
      and slug = 'admin'
  ),
  'Admin seed application exists'
);
select ok(
  exists (
    select 1
    from platform.app_origins
    where id = '21000000-0000-4000-8000-000000000001'
      and origin = 'http://localhost:5173'
      and environment = 'development'
  ),
  'Local Account Origin is deterministic'
);
select ok(
  exists (
    select 1
    from platform.app_origins
    where id = '21000000-0000-4000-8000-000000000002'
      and origin = 'http://localhost:5174'
      and environment = 'development'
  ),
  'Local Admin Origin is deterministic'
);
select ok(
  not exists (
    select 1
    from platform.app_origins
    where environment = 'production' and origin like '%*%'
  ),
  'production seed contains no wildcard Origin'
);

select throws_ok(
  $$
    insert into platform.platform_apps (slug, name, category, status)
    values ('invalid-app', 'Invalid', 'tool', 'not-a-status');
  $$,
  '23514',
  null,
  'invalid application status is rejected'
);
select throws_ok(
  $$
    insert into platform.platform_apps (slug, name, category)
    values ('Not-Lowercase', 'Invalid', 'tool');
  $$,
  '23514',
  null,
  'application slugs must use lowercase machine identifiers'
);
select throws_ok(
  $$
    insert into platform.app_origins (app_id, environment, origin)
    values ('20000000-0000-4000-8000-000000000001', 'development', 'http://*.example.test');
  $$,
  '23514',
  null,
  'wildcard Origins are rejected'
);
select throws_ok(
  $$
    insert into platform.app_origins (app_id, environment, origin)
    values ('20000000-0000-4000-8000-000000000001', 'production', 'https://lens.example.test/path');
  $$,
  '23514',
  null,
  'Origins with paths are rejected'
);
select throws_ok(
  $$
    insert into platform.app_origins (app_id, environment, origin)
    values ('20000000-0000-4000-8000-000000000001', 'local', 'http://lens.example.test');
  $$,
  '23514',
  null,
  'unknown environments are rejected'
);
select throws_ok(
  $$
    insert into platform.app_origins (app_id, environment, origin)
    values ('20000000-0000-4000-8000-000000000001', 'development', 'http://localhost:5173');
  $$,
  '23505',
  null,
  'duplicate Origins are rejected'
);
select throws_ok(
  $$
    insert into platform.platform_apps (slug, name, category)
    values ('aisenlens', 'Duplicate', 'tool');
  $$,
  '23505',
  null,
  'duplicate application slugs are rejected'
);
select throws_ok(
  $$
    update platform.platform_apps
    set slug = 'aisen-lens'
    where id = '20000000-0000-4000-8000-000000000002';
  $$,
  '23514',
  null,
  'referenced application slug cannot change'
);
select throws_ok(
  $$
    update platform.app_origins
    set origin = 'http://localhost:5199'
    where id = '21000000-0000-4000-8000-000000000001';
  $$,
  '23514',
  null,
  'Origin identity cannot change in place'
);
select throws_ok(
  $$
    delete from platform.platform_apps
    where id = '20000000-0000-4000-8000-000000000002';
  $$,
  '23503',
  null,
  'an application referenced by an Origin cannot be deleted'
);

select * from finish();
rollback;
