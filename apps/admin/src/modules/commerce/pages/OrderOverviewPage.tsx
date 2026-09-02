import {
  Alert,
  Button,
  Card,
  Col,
  Descriptions,
  Flex,
  Form,
  Input,
  InputNumber,
  List,
  Modal,
  Row,
  Select,
  Space,
  Spin,
  Table,
  Tabs,
  Typography,
} from 'antd';
import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import type {
  AdminOrderException,
  AdminOrderItemOverview,
  AdminOrderOverview,
  AdminOrderRefund,
  AdminVerifyOrderRequest,
  AdminRefundOrderItemRequest,
} from '@aisenhub/contracts';

import { DateTimeDisplay, EntityStatus, MoneyDisplay } from '@aisenhub/design-system';
import { DangerousActionDialog, type DangerousActionResult } from '../../../components';
import { useAdminCommand } from '../../../hooks/use-admin-command';
import { adminRuntime } from '../../../providers/admin-runtime';
import { AuditTimeline } from '../../operations/components/AuditTimeline';

type VerifyDraft = Pick<AdminVerifyOrderRequest, 'paymentReference' | 'amountMinor' | 'currency'>;
type RefundDraft = Pick<AdminRefundOrderItemRequest, 'amountMinor' | 'mode'>;

type SelectedCommand =
  | {
      readonly kind: 'verify';
      readonly paymentId: string;
      readonly input: VerifyDraft;
    }
  | {
      readonly kind: 'refund';
      readonly item: AdminOrderItemOverview;
      readonly input: RefundDraft;
    };

export function OrderOverviewPage() {
  const { orderId } = useParams<{ orderId: string }>();
  const session = adminRuntime.session.getSession();
  const [overview, setOverview] = useState<AdminOrderOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [selected, setSelected] = useState<SelectedCommand | null>(null);
  const [verifyPayment, setVerifyPayment] = useState<AdminOrderOverview['payments'][number] | null>(
    null,
  );
  const [refundItem, setRefundItem] = useState<AdminOrderItemOverview | null>(null);
  const [verifyForm] = Form.useForm<VerifyDraft>();
  const [refundForm] = Form.useForm<RefundDraft>();
  const canVerify = session?.role === 'owner' || session?.role === 'finance';
  const canRefund =
    session?.role === 'owner' || session?.role === 'admin' || session?.role === 'finance';

  useEffect(() => {
    if (!orderId) return;
    let active = true;
    setLoading(true);
    setError(null);
    void adminRuntime.dataProvider.getOrderOverview(orderId).then(
      (result) => {
        if (active) setOverview(result.data);
        if (active) setLoading(false);
      },
      (requestError: unknown) => {
        if (active) setError(requestError);
        if (active) setLoading(false);
      },
    );
    return () => {
      active = false;
    };
  }, [orderId, reloadToken]);

  const invokeVerify = useCallback(
    (
      input: AdminVerifyOrderRequest,
      options?: Parameters<typeof adminRuntime.commands.verifyOrder>[2],
    ) =>
      orderId
        ? adminRuntime.commands.verifyOrder(orderId, input, options)
        : Promise.reject(new Error('An Order ID is required.')),
    [orderId],
  );
  const invokeRefund = useCallback(
    (
      input: AdminRefundOrderItemRequest,
      options?: Parameters<typeof adminRuntime.commands.refundOrderItem>[2],
    ) =>
      selected?.kind === 'refund'
        ? adminRuntime.commands.refundOrderItem(selected.item.id, input, options)
        : Promise.reject(new Error('An Order Item is required.')),
    [selected],
  );
  const verifyCommand = useAdminCommand(invokeVerify);
  const refundCommand = useAdminCommand(invokeRefund);

  const onConfirm = useCallback(
    async (values: { reason: string; confirmation: true }): Promise<DangerousActionResult> => {
      if (!selected) throw new Error('A Commerce command is required.');
      const result =
        selected.kind === 'verify'
          ? await verifyCommand.execute({ ...selected.input, ...values })
          : await refundCommand.execute({ ...selected.input, ...values });
      setReloadToken((value) => value + 1);
      return { requestId: result.requestId, auditLogId: result.data.auditLogId };
    },
    [refundCommand, selected, verifyCommand],
  );

  if (!orderId) return <Alert type="error" message="Order ID is required." />;
  if (error) {
    return (
      <Alert
        type="error"
        showIcon
        message="Order 360 unavailable"
        description="Refresh the page or contact support with the request ID."
      />
    );
  }
  if (loading && !overview) return <Spin description="Loading Order 360…" />;
  if (!overview) return <Spin description="Loading Order 360…" />;

  const overviewData = overview;
  return (
    <Flex vertical gap={16}>
      <Space orientation="vertical" size={2}>
        <Link to="/orders">← Back to Commerce</Link>
        <Typography.Title level={2} style={{ margin: 0 }}>
          {overviewData.order.orderNo}
        </Typography.Title>
        <Typography.Text type="secondary">
          Order 360 · backend-owned commerce projection
        </Typography.Text>
      </Space>

      <Card>
        <Descriptions column={{ xs: 1, sm: 2, lg: 3 }}>
          <Descriptions.Item label="Order ID">
            <Typography.Text copyable={{ text: overviewData.order.id }}>
              {overviewData.order.id}
            </Typography.Text>
          </Descriptions.Item>
          <Descriptions.Item label="Status">
            <EntityStatus status={overviewData.order.status} />
          </Descriptions.Item>
          <Descriptions.Item label="Total">
            <MoneyDisplay
              amountMinor={overviewData.order.amountTotal}
              currency={overviewData.order.currency}
            />
          </Descriptions.Item>
          <Descriptions.Item label="Channel">{overviewData.order.channel}</Descriptions.Item>
          <Descriptions.Item label="Items">{overviewData.order.itemCount}</Descriptions.Item>
          <Descriptions.Item label="Created">
            <DateTimeDisplay value={overviewData.order.createdAt} />
          </Descriptions.Item>
          <Descriptions.Item label="Customer reference">
            {overviewData.order.customerRef}
          </Descriptions.Item>
          {overviewData.order.userId ? (
            <Descriptions.Item label="User ID">{overviewData.order.userId}</Descriptions.Item>
          ) : null}
        </Descriptions>
      </Card>

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={12}>
          <Card
            title="Payments"
            extra={<Typography.Text type="secondary">Read-only projection</Typography.Text>}
          >
            <Table
              rowKey="id"
              dataSource={overviewData.payments}
              pagination={false}
              scroll={{ x: 640 }}
              locale={{ emptyText: 'No payment records.' }}
              columns={[
                { dataIndex: 'provider', key: 'provider', title: 'Provider' },
                {
                  dataIndex: 'status',
                  key: 'status',
                  title: 'Status',
                  render: (value: string) => <EntityStatus status={value} />,
                },
                {
                  dataIndex: 'amount',
                  key: 'amount',
                  title: 'Amount',
                  render: (value: number, payment: AdminOrderOverview['payments'][number]) => (
                    <MoneyDisplay amountMinor={value} currency={payment.currency} />
                  ),
                },
                {
                  dataIndex: 'paidAt',
                  key: 'paidAt',
                  title: 'Paid',
                  render: (value: string | null) =>
                    value ? <DateTimeDisplay value={value} /> : '—',
                },
                {
                  key: 'actions',
                  title: 'Commands',
                  render: (_value: unknown, payment: AdminOrderOverview['payments'][number]) =>
                    canVerify && payment.status === 'pending' ? (
                      <Button
                        type="link"
                        onClick={() => {
                          verifyForm.setFieldsValue({
                            amountMinor: payment.amount,
                            currency: payment.currency,
                            paymentReference: payment.id,
                          });
                          setVerifyPayment(payment);
                        }}
                      >
                        Verify payment
                      </Button>
                    ) : null,
                },
              ]}
            />
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="Exceptions">
            <ExceptionList items={overviewData.exceptions} />
          </Card>
        </Col>
      </Row>

      <Card title="Order items">
        <Table
          rowKey="id"
          dataSource={overviewData.items}
          pagination={false}
          scroll={{ x: 860 }}
          locale={{ emptyText: 'No order items.' }}
          columns={[
            { dataIndex: 'productSku', key: 'productSku', title: 'Product' },
            {
              dataIndex: 'productVersion',
              key: 'productVersion',
              title: 'Version',
              render: (value: number) => `v${value}`,
            },
            {
              dataIndex: 'totalAmount',
              key: 'totalAmount',
              title: 'Total',
              render: (value: number) => (
                <MoneyDisplay amountMinor={value} currency={overviewData.order.currency} />
              ),
            },
            {
              dataIndex: 'fulfillmentStatus',
              key: 'fulfillmentStatus',
              title: 'Fulfillment',
              render: (value: string) => <EntityStatus status={value} />,
            },
            {
              dataIndex: 'refundedAmount',
              key: 'refundedAmount',
              title: 'Refunded',
              render: (value: number) => (
                <MoneyDisplay amountMinor={value} currency={overviewData.order.currency} />
              ),
            },
            {
              dataIndex: 'grantStatus',
              key: 'grantStatus',
              title: 'Entitlement grant',
              render: (value: string | null) => (value ? <EntityStatus status={value} /> : '—'),
            },
            {
              key: 'actions',
              title: 'Commands',
              render: (_value: unknown, item: AdminOrderItemOverview) =>
                canRefund ? (
                  <Button
                    type="link"
                    danger
                    onClick={() => openRefund(item, refundForm, setRefundItem)}
                  >
                    Refund item
                  </Button>
                ) : null,
            },
          ]}
        />
        {!canRefund && session?.role === 'support' ? (
          <Typography.Paragraph type="secondary" style={{ margin: '16px 0 0' }}>
            Support can inspect commerce records but cannot refund an order item.
          </Typography.Paragraph>
        ) : null}
      </Card>

      <Tabs
        items={[
          {
            key: 'events',
            label: `Payment events (${overviewData.events.length})`,
            children: (
              <Table
                rowKey="id"
                dataSource={overviewData.events}
                pagination={false}
                scroll={{ x: 760 }}
                locale={{ emptyText: 'No payment events.' }}
                columns={[
                  { dataIndex: 'provider', key: 'provider', title: 'Provider' },
                  { dataIndex: 'eventType', key: 'eventType', title: 'Event' },
                  {
                    dataIndex: 'status',
                    key: 'status',
                    title: 'Status',
                    render: (value: string) => <EntityStatus status={value} />,
                  },
                  {
                    dataIndex: 'occurredAt',
                    key: 'occurredAt',
                    title: 'Occurred',
                    render: (value: string) => <DateTimeDisplay value={value} />,
                  },
                ]}
              />
            ),
          },
          {
            key: 'refunds',
            label: `Refunds (${overviewData.refunds.length})`,
            children: (
              <RefundList items={overviewData.refunds} currency={overviewData.order.currency} />
            ),
          },
          {
            key: 'audit',
            label: `Audit (${overviewData.auditTimeline.length})`,
            children: <AuditTimeline items={overviewData.auditTimeline} />,
          },
        ]}
      />

      <Modal
        open={Boolean(verifyPayment)}
        title="Verify payment"
        okText="Review command"
        onCancel={() => setVerifyPayment(null)}
        onOk={() =>
          void verifyForm.validateFields().then((values) => {
            setVerifyPayment(null);
            setSelected({ kind: 'verify', paymentId: verifyPayment?.id ?? '', input: values });
          })
        }
      >
        <Form form={verifyForm} layout="vertical">
          <Form.Item
            name="paymentReference"
            label="Payment reference"
            rules={[{ required: true, whitespace: true, message: 'Enter the provider reference.' }]}
          >
            <Input placeholder="Provider reference or local proof" />
          </Form.Item>
          <Form.Item
            name="amountMinor"
            label="Amount in minor units"
            rules={[{ required: true, type: 'number', min: 0, message: 'Enter a valid amount.' }]}
          >
            <InputNumber style={{ width: '100%' }} min={0} precision={0} />
          </Form.Item>
          <Form.Item
            name="currency"
            label="Currency"
            rules={[
              {
                required: true,
                pattern: /^[A-Z]{3}$/,
                message: 'Use a three-letter currency code.',
              },
            ]}
          >
            <Input maxLength={3} />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        open={Boolean(refundItem)}
        title="Prepare item refund"
        okText="Review command"
        onCancel={() => setRefundItem(null)}
        onOk={() =>
          void refundForm.validateFields().then((values) => {
            setRefundItem(null);
            if (refundItem) setSelected({ kind: 'refund', item: refundItem, input: values });
          })
        }
      >
        <Form form={refundForm} layout="vertical">
          <Form.Item
            name="amountMinor"
            label="Refund amount in minor units"
            rules={[
              { required: true, type: 'number', min: 1, message: 'Enter a positive amount.' },
            ]}
          >
            <InputNumber style={{ width: '100%' }} min={1} precision={0} />
          </Form.Item>
          <Form.Item name="mode" label="Refund mode" rules={[{ required: true }]}>
            <Select
              options={[
                { value: 'compensation', label: 'Compensation (no provider return)' },
                { value: 'return', label: 'Return to provider' },
              ]}
            />
          </Form.Item>
        </Form>
      </Modal>

      {selected ? (
        <DangerousActionDialog
          open
          title={`${selected.kind === 'verify' ? 'Verify payment' : 'Refund order item'} · ${overviewData.order.orderNo}`}
          actionLabel={selected.kind === 'verify' ? 'Verify payment' : 'Refund item'}
          target={{
            label: overviewData.order.orderNo,
            id: selected.kind === 'verify' ? selected.paymentId : selected.item.id,
            currentState: overviewData.order.status,
            targetState: selected.kind === 'verify' ? 'fulfilled' : 'refunded / partially refunded',
            impactSummary:
              selected.kind === 'verify'
                ? 'Record the verified payment and let Platform Backend fulfill the order atomically.'
                : 'Record an audited refund command for this item and update its entitlement state through the backend.',
          }}
          assurance={{ aal: session?.aal ?? 'aal1', mfaState: session?.mfaState ?? 'required' }}
          onConfirm={onConfirm}
          onCancel={() => setSelected(null)}
        />
      ) : null}
    </Flex>
  );
}

function openRefund(
  item: AdminOrderItemOverview,
  form: ReturnType<typeof Form.useForm<RefundDraft>>[0],
  setItem: (value: AdminOrderItemOverview) => void,
) {
  form.resetFields();
  form.setFieldsValue({
    amountMinor: item.totalAmount - item.refundedAmount,
    mode: 'compensation',
  });
  setItem(item);
}

function ExceptionList({ items }: { readonly items: readonly AdminOrderException[] }) {
  return (
    <List
      dataSource={[...items]}
      locale={{ emptyText: 'No payment exceptions.' }}
      renderItem={(item) => (
        <List.Item>
          <Space orientation="vertical" size={2}>
            <Space wrap>
              <EntityStatus status={item.type} />
              <Typography.Text type="secondary">
                Payment event {item.paymentEventId}
              </Typography.Text>
            </Space>
            <Typography.Text>{item.reason}</Typography.Text>
            <DateTimeDisplay value={item.createdAt} />
          </Space>
        </List.Item>
      )}
    />
  );
}

function RefundList({
  items,
  currency,
}: {
  readonly items: readonly AdminOrderRefund[];
  readonly currency: string;
}) {
  return (
    <List
      dataSource={[...items]}
      locale={{ emptyText: 'No refunds.' }}
      renderItem={(item) => (
        <List.Item>
          <Space orientation="vertical" size={2}>
            <Space wrap>
              <MoneyDisplay amountMinor={item.amountMinor} currency={currency} />
              <Typography.Text>{item.mode}</Typography.Text>
              <DateTimeDisplay value={item.createdAt} />
            </Space>
            <Typography.Text type="secondary">{item.reason}</Typography.Text>
          </Space>
        </List.Item>
      )}
    />
  );
}
