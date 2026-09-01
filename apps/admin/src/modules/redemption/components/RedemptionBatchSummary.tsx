import { Card, Descriptions, Space, Tag, Typography } from 'antd';
import type { AdminRedemptionBatchSummary } from '@aisenhub/contracts';

import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';

export function RedemptionBatchSummary({ batch }: { readonly batch: AdminRedemptionBatchSummary }) {
  return (
    <Card
      title={
        <Space>
          <Typography.Text strong>{batch.name}</Typography.Text>
          <EntityStatus status={batch.status} />
        </Space>
      }
    >
      <Descriptions column={{ xs: 1, sm: 2 }} size="small">
        <Descriptions.Item label="Product">
          {batch.productSku} · v{batch.productVersion}
        </Descriptions.Item>
        <Descriptions.Item label="Prefix">
          <Tag>{batch.codePrefix}</Tag>
        </Descriptions.Item>
        <Descriptions.Item label="Issued">
          {batch.issuedCount} / {batch.quantity}
        </Descriptions.Item>
        <Descriptions.Item label="Redeemed">{batch.redeemedCount}</Descriptions.Item>
        <Descriptions.Item label="Starts">
          <DateTimeDisplay value={batch.startsAt} />
        </Descriptions.Item>
        <Descriptions.Item label="Expires">
          {batch.expiresAt ? <DateTimeDisplay value={batch.expiresAt} /> : 'No expiry'}
        </Descriptions.Item>
      </Descriptions>
    </Card>
  );
}
