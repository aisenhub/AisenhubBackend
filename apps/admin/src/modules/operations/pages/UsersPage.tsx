import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';
import { Link } from 'react-router-dom';
import type { AdminUserSummary } from '@aisenhub/contracts';

import { ResourcePage } from './ResourcePage';

export function UsersPage() {
  return (
    <ResourcePage<AdminUserSummary>
      resource="users"
      title="Users"
      description="Inspect platform identity status and current Admin membership projections."
      emptyDescription="No users match the current filters."
      initialSort="createdAt"
      statusOptions={['active', 'disabled', 'deletion_pending', 'deleted']}
      columns={[
        {
          dataIndex: 'displayName',
          key: 'displayName',
          sorter: true,
          title: 'Display name',
          render: (value: string | null, user: AdminUserSummary) => (
            <Link to={`/customers/users/${user.id}`}>{value ?? 'Unnamed user'}</Link>
          ),
        },
        { dataIndex: 'id', key: 'id', title: 'User ID' },
        {
          dataIndex: 'adminRole',
          key: 'adminRole',
          title: 'Admin role',
          render: (role: string | null) => role ?? '—',
        },
        {
          dataIndex: 'status',
          key: 'status',
          sorter: true,
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          dataIndex: 'createdAt',
          key: 'createdAt',
          sorter: true,
          title: 'Created',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
      ]}
    />
  );
}
