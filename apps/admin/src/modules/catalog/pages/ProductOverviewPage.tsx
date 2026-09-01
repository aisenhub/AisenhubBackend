import { Alert, Card, Descriptions, Flex, List, Space, Spin, Tabs, Typography } from 'antd';
import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import type { AdminProductOverview } from '@aisenhub/contracts';

import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';
import { adminRuntime } from '../../../providers/admin-runtime';
import { ProductVersionDiff } from '../components/ProductVersionDiff';

export function ProductOverviewPage() {
  const { productId } = useParams<{ productId: string }>();
  const [overview, setOverview] = useState<AdminProductOverview | null>(null);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    if (!productId) return;
    let active = true;
    setOverview(null);
    setError(null);
    void adminRuntime.dataProvider.getProductOverview(productId).then(
      (result) => {
        if (active) setOverview(result.data);
      },
      (requestError: unknown) => {
        if (active) setError(requestError);
      },
    );
    return () => {
      active = false;
    };
  }, [productId]);

  if (!productId) return <Alert type="error" message="Product ID is required." />;
  if (error)
    return (
      <Alert
        type="error"
        showIcon
        message="Product overview unavailable"
        description="Refresh the page or contact support with the request ID."
      />
    );
  if (!overview) return <Spin tip="Loading Product 360…" />;

  const currentVersion = overview.product.currentVersion?.version ?? null;
  const latestPublished =
    overview.versions
      .filter((version) => version.status === 'published')
      .sort((a, b) => b.version - a.version)[0]?.version ?? null;
  return (
    <Flex vertical gap={16}>
      <Space direction="vertical" size={2}>
        <Typography.Title level={2} style={{ margin: 0 }}>
          {overview.product.name}
        </Typography.Title>
        <Typography.Text type="secondary">Product 360 · {overview.product.sku}</Typography.Text>
      </Space>
      <Card>
        <Descriptions column={{ xs: 1, sm: 2 }}>
          <Descriptions.Item label="SKU">{overview.product.sku}</Descriptions.Item>
          <Descriptions.Item label="Billing">{overview.product.billingType}</Descriptions.Item>
          <Descriptions.Item label="Status">
            <EntityStatus status={overview.product.status} />
          </Descriptions.Item>
          <Descriptions.Item label="Versions">{overview.versions.length}</Descriptions.Item>
        </Descriptions>
      </Card>
      <Card title="Version alignment">
        <ProductVersionDiff currentVersion={currentVersion} publishedVersion={latestPublished} />
      </Card>
      <Tabs
        items={[
          {
            key: 'versions',
            label: 'Versions',
            children: (
              <List
                dataSource={overview.versions}
                renderItem={(version) => (
                  <List.Item>
                    <Space>
                      <Typography.Text strong>v{version.version}</Typography.Text>
                      <EntityStatus status={version.status} />
                      {version.publishedAt ? <DateTimeDisplay value={version.publishedAt} /> : null}
                    </Space>
                  </List.Item>
                )}
              />
            ),
          },
          {
            key: 'prices',
            label: 'Prices',
            children: (
              <List
                dataSource={overview.prices}
                renderItem={(price) => (
                  <List.Item>
                    <Space>
                      <Typography.Text strong>
                        {price.currency} {price.amountMinor}
                      </Typography.Text>
                      <EntityStatus status={price.status} />
                      <Typography.Text type="secondary">{price.channel}</Typography.Text>
                    </Space>
                  </List.Item>
                )}
              />
            ),
          },
          {
            key: 'redemption',
            label: 'Redemption batches',
            children: (
              <List
                dataSource={overview.redemptionBatches}
                locale={{ emptyText: 'No redemption batches.' }}
                renderItem={(batch) => (
                  <List.Item>
                    <Link to={`/catalog/products/${overview.product.id}`}>{batch.name}</Link>
                    <EntityStatus status={batch.status} />
                  </List.Item>
                )}
              />
            ),
          },
          {
            key: 'audit',
            label: 'Audit history',
            children: (
              <List
                dataSource={overview.auditLogs}
                locale={{ emptyText: 'No audit entries.' }}
                renderItem={(entry) => (
                  <List.Item>
                    <Space direction="vertical" size={0}>
                      <Typography.Text strong>{entry.action}</Typography.Text>
                      <Typography.Text type="secondary">{entry.reason}</Typography.Text>
                      <DateTimeDisplay value={entry.createdAt} />
                    </Space>
                  </List.Item>
                )}
              />
            ),
          },
        ]}
      />
    </Flex>
  );
}
