import { EntityStatus, DateTimeDisplay } from '@aisenhub/design-system';
import type { AdminApplicationSummary } from '@aisenhub/contracts';
import { Link } from 'react-router-dom';

import { ResourcePage } from './ResourcePage';

export function ApplicationsPage() {
  return (
    <ResourcePage<AdminApplicationSummary>
      resource="applications"
      title="Applications"
      description="Review registered platform applications and their active origins."
      emptyDescription="No applications match the current filters."
      initialSort="updatedAt"
      statusOptions={['draft', 'active', 'suspended', 'retired']}
      columns={[
        {
          dataIndex: 'name',
          key: 'name',
          sorter: true,
          title: 'Name',
          render: (name: string, record: AdminApplicationSummary) => (
            <Link to={`/applications/${record.id}`}>{name}</Link>
          ),
        },
        { dataIndex: 'slug', key: 'slug', sorter: true, title: 'Slug' },
        { dataIndex: 'category', key: 'category', title: 'Category' },
        { dataIndex: 'originCount', key: 'originCount', title: 'Active origins' },
        {
          dataIndex: 'status',
          key: 'status',
          sorter: true,
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          dataIndex: 'updatedAt',
          key: 'updatedAt',
          sorter: true,
          title: 'Updated',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
      ]}
    />
  );
}
