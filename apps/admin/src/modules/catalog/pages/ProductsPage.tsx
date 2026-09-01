import { Button, Space } from 'antd';
import type { AdminProductSummary } from '@aisenhub/contracts';
import { Link } from 'react-router-dom';

import { EntityStatus } from '@aisenhub/design-system';
import { ResourcePage } from '../../operations/pages/ResourcePage';

export function ProductsPage() {
  return (
    <ResourcePage<AdminProductSummary>
      resource="products"
      title="Products"
      description="Edit draft product facts and open the backend-owned Product 360 view."
      emptyDescription="No products match the current filters."
      initialSort="updatedAt"
      statusOptions={['draft', 'active', 'archived']}
      columns={[
        { dataIndex: 'sku', key: 'sku', sorter: true, title: 'SKU' },
        { dataIndex: 'name', key: 'name', sorter: true, title: 'Name' },
        { dataIndex: 'billingType', key: 'billingType', title: 'Billing' },
        {
          dataIndex: 'status',
          key: 'status',
          sorter: true,
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          key: 'currentVersion',
          title: 'Current version',
          render: (_value: unknown, record: AdminProductSummary) =>
            record.currentVersion ? `v${record.currentVersion.version}` : 'Not selected',
        },
        {
          key: 'actions',
          title: 'Actions',
          render: (_value: unknown, record: AdminProductSummary) => (
            <Space>
              <Link to={`/catalog/products/${record.id}`}>Open 360</Link>
              {record.status === 'draft' ? (
                <Button type="link" size="small">
                  Edit draft
                </Button>
              ) : null}
            </Space>
          ),
        },
      ]}
    >
      <Button type="primary" style={{ marginBottom: 16 }}>
        <Link to="/catalog/products/new">New product draft</Link>
      </Button>
    </ResourcePage>
  );
}
