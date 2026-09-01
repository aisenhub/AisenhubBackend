import type { AdminProductVersionSummary } from '@aisenhub/contracts';
import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';

import { ResourcePage } from '../../operations/pages/ResourcePage';

export function ProductVersionsPage() {
  return (
    <ResourcePage<AdminProductVersionSummary>
      resource="productVersions"
      title="Product versions"
      description="Published versions are immutable facts; draft edits remain separate from commands."
      emptyDescription="No product versions match the current filters."
      initialSort="version"
      statusOptions={['draft', 'published', 'retired']}
      columns={[
        { dataIndex: 'productSku', key: 'productSku', title: 'Product' },
        {
          dataIndex: 'version',
          key: 'version',
          sorter: true,
          title: 'Version',
          render: (value: number) => `v${value}`,
        },
        {
          dataIndex: 'status',
          key: 'status',
          sorter: true,
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          dataIndex: 'publishedAt',
          key: 'publishedAt',
          title: 'Published',
          render: (value: string | null) => (value ? <DateTimeDisplay value={value} /> : '—'),
        },
      ]}
    />
  );
}
