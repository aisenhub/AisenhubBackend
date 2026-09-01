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
end;
$$;
