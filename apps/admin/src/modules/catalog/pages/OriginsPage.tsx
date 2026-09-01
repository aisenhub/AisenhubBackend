import type { AdminOriginSummary } from '@aisenhub/contracts';
import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';

import { ResourcePage } from '../../operations/pages/ResourcePage';

export function OriginsPage() {
  return (
    <ResourcePage<AdminOriginSummary>
      resource="origins"
      title="Origins"
      description="Review registered application Origins. Production switching is an explicit command."
      emptyDescription="No Origins match the current filters."
      initialSort="updatedAt"
      statusOptions={['development', 'staging', 'production']}
      columns={[
        { dataIndex: 'appSlug', key: 'appSlug', sorter: true, title: 'Application' },
        { dataIndex: 'environment', key: 'environment', sorter: true, title: 'Environment' },
        { dataIndex: 'origin', key: 'origin', title: 'Origin' },
        {
          dataIndex: 'isActive',
          key: 'isActive',
          title: 'State',
          render: (active: boolean) => <EntityStatus status={active ? 'active' : 'inactive'} />,
        },
        {
          dataIndex: 'updatedAt',
          key: 'updatedAt',
          title: 'Updated',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
      ]}
    />
  );
}
