import { Button, Space } from 'antd';
import type { AdminOrderSummary } from '@aisenhub/contracts';
import { Link } from 'react-router-dom';

import { DateTimeDisplay, EntityStatus, MoneyDisplay } from '@aisenhub/design-system';
import { ResourcePage } from '../../operations/pages/ResourcePage';

export function OrdersPage() {
  return (
    <ResourcePage<AdminOrderSummary>
      resource="orders"
      title="Commerce"
      description="Search the backend-owned order projection and open a complete Order 360 view."
      emptyDescription="No orders match the current filters."
      initialSort="createdAt"
      statusOptions={[
        'pending',
        'paid',
        'fulfilled',
        'cancelled',
        'partially_refunded',
        'refunded',
        'chargeback',
      ]}
      columns={[
        {
          dataIndex: 'orderNo',
          key: 'orderNo',
          sorter: true,
          title: 'Order',
          render: (value: string, order: AdminOrderSummary) => (
            <Link to={`/orders/${order.id}`}>{value}</Link>
          ),
        },
        {
          dataIndex: 'status',
          key: 'status',
          sorter: true,
          title: 'Status',
          render: (value: string) => <EntityStatus status={value} />,
        },
        {
          dataIndex: 'amountTotal',
          key: 'amountTotal',
          sorter: true,
          title: 'Total',
          render: (value: number, order: AdminOrderSummary) => (
            <MoneyDisplay amountMinor={value} currency={order.currency} />
          ),
        },
        { dataIndex: 'channel', key: 'channel', title: 'Channel' },
        { dataIndex: 'itemCount', key: 'itemCount', title: 'Items' },
        {
          dataIndex: 'createdAt',
          key: 'createdAt',
          sorter: true,
          title: 'Created',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
        {
          key: 'actions',
          title: 'Actions',
          render: (_value: unknown, order: AdminOrderSummary) => (
            <Space>
              <Button type="link" size="small">
                <Link to={`/orders/${order.id}`}>Open Order 360</Link>
              </Button>
            </Space>
          ),
        },
      ]}
    >
      <Space wrap style={{ marginBottom: 16 }}>
        <span>
          Order, payment, refund, exception, and audit sections are loaded from one aggregate.
        </span>
      </Space>
    </ResourcePage>
  );
}
