import type { AdminRedemptionSummary } from '@aisenhub/contracts';
import { DateTimeDisplay } from '@aisenhub/design-system';

import { ResourcePage } from '../../operations/pages/ResourcePage';

export function RedemptionsPage() {
  return (
    <ResourcePage<AdminRedemptionSummary>
      resource="redemptions"
      title="Redemptions"
      description="Read-only redemption receipts produced by the Platform Backend transaction."
      emptyDescription="No redemptions match the current filters."
      initialSort="redeemedAt"
      columns={[
        { dataIndex: 'productSku', key: 'productSku', title: 'Product' },
        { dataIndex: 'userId', key: 'userId', title: 'User ID' },
        { dataIndex: 'batchId', key: 'batchId', title: 'Batch ID' },
        {
          dataIndex: 'redeemedAt',
          key: 'redeemedAt',
          title: 'Redeemed',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
      ]}
    />
  );
}
