import type { AdminRedemptionCodeSummary } from '@aisenhub/contracts';
import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';

import { ResourcePage } from '../../operations/pages/ResourcePage';

export function RedemptionCodesPage() {
  return (
    <ResourcePage<AdminRedemptionCodeSummary>
      resource="redemptionCodes"
      title="Redemption codes"
      description="Review safe code hints and lifecycle status. Complete plaintext is never a query result."
      emptyDescription="No Redemption codes match the current filters."
      initialSort="createdAt"
      statusOptions={['issued', 'redeemed', 'revoked']}
      columns={[
        { dataIndex: 'codeHint', key: 'codeHint', title: 'Code hint' },
        { dataIndex: 'batchId', key: 'batchId', title: 'Batch ID' },
        {
          dataIndex: 'status',
          key: 'status',
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          dataIndex: 'redeemedAt',
          key: 'redeemedAt',
          title: 'Redeemed',
          render: (value: string | null) => (value ? <DateTimeDisplay value={value} /> : '—'),
        },
      ]}
    />
  );
}
