-- Local-only fixture data. Auth users are created by verify-fixtures.mjs first.

do $$
begin
  insert into platform.admin_members (user_id, role, status, created_by)
  values
    ('10000000-0000-4000-8000-000000000001', 'owner', 'active', null),
    ('10000000-0000-4000-8000-000000000002', 'admin', 'active', '10000000-0000-4000-8000-000000000001'),
    ('10000000-0000-4000-8000-000000000003', 'support', 'active', '10000000-0000-4000-8000-000000000001'),
    ('10000000-0000-4000-8000-000000000004', 'finance', 'active', '10000000-0000-4000-8000-000000000001')
  on conflict (user_id) do update
  set role = excluded.role,
      status = excluded.status,
      created_by = excluded.created_by,
      disabled_at = null;

  delete from platform.admin_members
  where user_id = '10000000-0000-4000-8000-000000000005';

  insert into platform.application_memberships
    (application_id, user_id, status, created_source, activated_at, created_by)
  values
    ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'active', 'system', now(), null),
    ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'active', 'system', now(), '10000000-0000-4000-8000-000000000001'),
    ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'active', 'system', now(), null),
    ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', 'active', 'system', now(), '10000000-0000-4000-8000-000000000001'),
    ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000005', 'active', 'system', now(), '10000000-0000-4000-8000-000000000001')
  on conflict (application_id, user_id) do update
  set status = excluded.status,
      activated_at = coalesce(platform.application_memberships.activated_at, excluded.activated_at),
      suspended_at = null,
      suspended_reason = null,
      left_at = null,
      deleted_at = null;
end;
$$;
