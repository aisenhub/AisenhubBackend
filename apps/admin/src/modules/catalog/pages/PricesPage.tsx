import type { AdminPriceSummary } from '@aisenhub/contracts';
import { DateTimeDisplay, EntityStatus, MoneyDisplay } from '@aisenhub/design-system';

import { ResourcePage } from '../../operations/pages/ResourcePage';

export function PricesPage() {
  return (
    <ResourcePage<AdminPriceSummary>
      resource="prices"
      title="Prices"
      description="Review versioned price snapshots. Activated prices are not edited in place."
      emptyDescription="No prices match the current filters."
      initialSort="validFrom"
      statusOptions={['draft', 'active', 'retired']}
      columns={[
        { dataIndex: 'productSku', key: 'productSku', title: 'Product' },
        {
          dataIndex: 'productVersion',
          key: 'productVersion',
          title: 'Version',
          render: (value: number) => `v${value}`,
        },
        {
          dataIndex: 'amountMinor',
          key: 'amountMinor',
          title: 'Amount',
          render: (value: number, record: AdminPriceSummary) => (
            <MoneyDisplay amountMinor={value} currency={record.currency} />
          ),
        },
        { dataIndex: 'channel', key: 'channel', title: 'Channel' },
        {
          dataIndex: 'status',
          key: 'status',
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          dataIndex: 'validFrom',
          key: 'validFrom',
          title: 'Valid from',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
      ]}
    />
  );
}
