import type { AdminFeatureSummary } from '@aisenhub/contracts';
import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';

import { ResourcePage } from '../../operations/pages/ResourcePage';

export function FeaturesPage() {
  return (
    <ResourcePage<AdminFeatureSummary>
      resource="features"
      title="Features"
      description="Maintain atomic entitlement features without turning them into user roles."
      emptyDescription="No features match the current filters."
      initialSort="createdAt"
      statusOptions={['active', 'retired']}
      columns={[
        { dataIndex: 'code', key: 'code', sorter: true, title: 'Code' },
        { dataIndex: 'name', key: 'name', title: 'Name' },
        { dataIndex: 'valueType', key: 'valueType', title: 'Value type' },
        { dataIndex: 'mergeStrategy', key: 'mergeStrategy', title: 'Merge strategy' },
        {
          dataIndex: 'status',
          key: 'status',
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          dataIndex: 'createdAt',
          key: 'createdAt',
          title: 'Created',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
      ]}
    />
  );
}
