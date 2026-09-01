import {
  Alert,
  Button,
  Card,
  Descriptions,
  Flex,
  Form,
  Input,
  List,
  Modal,
  Space,
  Spin,
  Table,
  Tabs,
  Typography,
} from 'antd';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import type {
  AdminAccountDeletionRequestSummary,
  AdminGrantEntitlementRequest,
  AdminUserOverview,
  AdminUserOverviewEntitlement,
} from '@aisenhub/contracts';

import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';
import { DangerousActionDialog, type DangerousActionResult } from '../../../components';
import { useAdminCommand } from '../../../hooks/use-admin-command';
import { adminRuntime } from '../../../providers/admin-runtime';
import { AuditTimeline } from '../components/AuditTimeline';

type CommandKind = 'grant' | 'revoke' | 'restore' | 'disable' | 'processDeletion';

type SelectedCommand = {
  readonly kind: CommandKind;
  readonly id: string;
  readonly label: string;
  readonly currentState: string;
  readonly targetState: string;
  readonly impactSummary: string;
};

const emptyGrant = {
  reason: '',
  confirmation: true as const,
  productVersionId: '',
};

export function UserOverviewPage() {
  const { userId } = useParams<{ userId: string }>();
  const session = adminRuntime.session.getSession();
  const [overview, setOverview] = useState<AdminUserOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [selected, setSelected] = useState<SelectedCommand | null>(null);
  const [grantOpen, setGrantOpen] = useState(false);
  const [grantForm] = Form.useForm<{ productVersionId: string }>();
  const canAdminister = session?.role === 'owner' || session?.role === 'admin';
  const canGrantOrRevoke = canAdminister || session?.role === 'support';

  useEffect(() => {
    if (!userId) return;
    let active = true;
    setError(null);
    setLoading(true);
    void adminRuntime.dataProvider.getUserOverview(userId).then(
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
  }, [reloadToken, userId]);

  const invokeGrant = useCallback(
    (
      input: AdminGrantEntitlementRequest,
      options?: Parameters<typeof adminRuntime.commands.grantEntitlement>[2],
    ) =>
      userId
        ? adminRuntime.commands.grantEntitlement(userId, input, options)
        : Promise.reject(new Error('A User ID is required.')),
    [userId],
  );
  const grantCommand = useAdminCommand(invokeGrant);

  const onConfirm = useCallback(
    async (values: { reason: string; confirmation: true }): Promise<DangerousActionResult> => {
      if (!selected) throw new Error('A Customer command is required.');
      let result;
      if (selected.kind === 'grant') {
        const productVersionId = grantForm.getFieldValue('productVersionId')?.trim();
        result = await grantCommand.execute({ ...values, productVersionId });
      } else if (selected.kind === 'revoke') {
        result = await adminRuntime.commands.revokeEntitlement(selected.id, values);
      } else if (selected.kind === 'restore') {
        result = await adminRuntime.commands.restoreEntitlement(selected.id, values);
      } else if (selected.kind === 'disable') {
        result = await adminRuntime.commands.disableUser(selected.id, values);
      } else {
        result = await adminRuntime.commands.processAccountDeletion(selected.id, values);
      }
      setReloadToken((value) => value + 1);
      const data = result.data as { auditLogId?: string };
      return { requestId: result.requestId, auditLogId: data.auditLogId };
    },
    [grantCommand, grantForm, selected],
  );

  const openGrant = () => {
    grantForm.resetFields();
    setGrantOpen(true);
  };

  if (!userId) return <Alert type="error" message="User ID is required." />;
  if (error) {
    return (
      <Alert
        type="error"
        showIcon
        message="User 360 unavailable"
        description="Refresh the page or contact support with the request ID."
      />
    );
  }
  if (loading && !overview) return <Spin tip="Loading User 360…" />;
  if (!overview) return <Spin tip="Loading User 360…" />;

  const pendingDeletion = overview.deletionRequests.find((item) =>
    ['pending', 'failed'].includes(item.status),
  );
  return (
    <Flex vertical gap={16}>
      <Space direction="vertical" size={2}>
        <Typography.Title level={2} style={{ margin: 0 }}>
          {overview.profile.displayName ?? 'Unnamed user'}
        </Typography.Title>
        <Typography.Text type="secondary">User 360 · {overview.profile.userId}</Typography.Text>
      </Space>
      <Card>
        <Descriptions column={{ xs: 1, sm: 2 }}>
          <Descriptions.Item label="User ID">{overview.profile.userId}</Descriptions.Item>
          <Descriptions.Item label="Status">
            <EntityStatus status={overview.profile.status} />
          </Descriptions.Item>
          <Descriptions.Item label="Admin role">{overview.adminRole ?? '—'}</Descriptions.Item>
          <Descriptions.Item label="Created">
            <DateTimeDisplay value={overview.profile.createdAt} />
          </Descriptions.Item>
          <Descriptions.Item label="Sessions">
            {overview.sessionSummary.activeCount} active / {overview.sessionSummary.totalCount}{' '}
            total
          </Descriptions.Item>
        </Descriptions>
      </Card>

      <Card title="Customer commands">
        <Space wrap>
          {canGrantOrRevoke && overview.profile.status === 'active' ? (
            <Button onClick={openGrant}>Grant entitlement</Button>
          ) : null}
          {canAdminister && overview.profile.status === 'active' ? (
            <Button
              danger
              onClick={() =>
                setSelected({
                  kind: 'disable',
                  id: userId,
                  label: overview.profile.displayName ?? userId,
                  currentState: 'active',
                  targetState: 'disabled',
                  impactSummary: 'Disable the account and revoke every active Platform Session.',
                })
              }
            >
              Disable user
            </Button>
          ) : null}
          {canAdminister && pendingDeletion ? (
            <Button
              danger
              onClick={() =>
                setSelected({
                  kind: 'processDeletion',
                  id: pendingDeletion.id,
                  label: pendingDeletion.id,
                  currentState: pendingDeletion.status,
                  targetState: 'processing',
                  impactSummary:
                    'Claim the due deletion request for the controlled anonymization worker.',
                })
              }
            >
              Process deletion
            </Button>
          ) : null}
        </Space>
      </Card>

      <Tabs
        items={[
          {
            key: 'entitlements',
            label: `Entitlements (${overview.entitlements.length})`,
            children: (
              <EntitlementsPanel
                items={overview.entitlements}
                canGrantOrRevoke={canGrantOrRevoke}
                onSelect={setSelected}
              />
            ),
          },
          {
            key: 'redemptions',
            label: `Redemptions (${overview.redemptions.length})`,
            children: (
              <List
                dataSource={overview.redemptions}
                locale={{ emptyText: 'No redemptions.' }}
                renderItem={(item) => (
                  <List.Item>
                    <Space>
                      <Typography.Text>{item.productSku}</Typography.Text>
                      <EntityStatus status={item.status} />
                      <DateTimeDisplay value={item.redeemedAt} />
                    </Space>
                  </List.Item>
                )}
              />
            ),
          },
          {
            key: 'feedback',
            label: `Feedback (${overview.feedback.length})`,
            children: (
              <List
                dataSource={overview.feedback}
                locale={{ emptyText: 'No feedback.' }}
                renderItem={(item) => (
                  <List.Item>
                    <Space direction="vertical" size={0}>
                      <Typography.Text strong>{item.title}</Typography.Text>
                      <Typography.Text type="secondary">
                        {item.appSlug} · {item.kind} · {item.status}
                      </Typography.Text>
                      {item.content ? (
                        <Typography.Paragraph>{item.content}</Typography.Paragraph>
                      ) : null}
                    </Space>
                  </List.Item>
                )}
              />
            ),
          },
          {
            key: 'deletion',
            label: `Deletion (${overview.deletionRequests.length})`,
            children: <DeletionPanel items={overview.deletionRequests} />,
          },
          {
            key: 'audit',
            label: 'Audit timeline',
            children: <AuditTimeline items={overview.auditTimeline} />,
          },
        ]}
      />

      <Modal
        open={grantOpen}
        title="Grant entitlement"
        okText="Review command"
        onCancel={() => setGrantOpen(false)}
        onOk={() =>
          void grantForm.validateFields().then(() => {
            setGrantOpen(false);
            setSelected({
              kind: 'grant',
              id: userId,
              label: overview.profile.displayName ?? userId,
              currentState: overview.profile.status,
              targetState: 'entitled',
              impactSummary:
                'Create one new audited admin entitlement for the selected Product Version.',
            });
          })
        }
      >
        <Form form={grantForm} layout="vertical" initialValues={emptyGrant}>
          <Form.Item
            name="productVersionId"
            label="Product Version ID"
            rules={[
              { required: true, message: 'Enter a Product Version UUID.' },
              { type: 'string', min: 36, message: 'Enter a valid Product Version UUID.' },
            ]}
          >
            <Input placeholder="Published Product Version UUID" />
          </Form.Item>
        </Form>
      </Modal>

      {selected ? (
        <DangerousActionDialog
          open
          title={`${selected.kind === 'grant' ? 'Grant entitlement' : selected.kind === 'processDeletion' ? 'Process deletion' : selected.kind} · ${selected.label}`}
          actionLabel={
            selected.kind === 'grant'
              ? 'Grant entitlement'
              : selected.kind === 'processDeletion'
                ? 'Process deletion'
                : selected.kind
          }
          target={{
            label: selected.label,
            id: selected.id,
            currentState: selected.currentState,
            targetState: selected.targetState,
            impactSummary: selected.impactSummary,
          }}
          assurance={{ aal: session?.aal ?? 'aal1', mfaState: session?.mfaState ?? 'required' }}
          onConfirm={onConfirm}
          onCancel={() => setSelected(null)}
        />
      ) : null}
    </Flex>
  );
}

function EntitlementsPanel({
  items,
  canGrantOrRevoke,
  onSelect,
}: {
  readonly items: readonly AdminUserOverviewEntitlement[];
  readonly canGrantOrRevoke: boolean;
  readonly onSelect: (command: SelectedCommand) => void;
}) {
  const session = adminRuntime.session.getSession();
  const canRestore = session?.role === 'owner' || session?.role === 'admin';
  const columns = useMemo(
    () => [
      { dataIndex: 'productSku', key: 'productSku', title: 'Product' },
      {
        dataIndex: 'productVersion',
        key: 'productVersion',
        title: 'Version',
        render: (value: number) => `v${value}`,
      },
      { dataIndex: 'sourceType', key: 'sourceType', title: 'Source' },
      {
        dataIndex: 'status',
        key: 'status',
        title: 'Status',
        render: (value: string) => <EntityStatus status={value} />,
      },
      {
        dataIndex: 'expiresAt',
        key: 'expiresAt',
        title: 'Expires',
        render: (value: string | null) => (value ? <DateTimeDisplay value={value} /> : 'Never'),
      },
      {
        key: 'actions',
        title: 'Commands',
        render: (_value: unknown, item: AdminUserOverviewEntitlement) => (
          <Space>
            {canGrantOrRevoke && item.status === 'active' ? (
              <Button
                type="link"
                danger
                onClick={() =>
                  onSelect({
                    kind: 'revoke',
                    id: item.id,
                    label: item.productSku,
                    currentState: 'active',
                    targetState: 'revoked',
                    impactSummary:
                      'Revoke this entitlement permanently; the original grant will remain in the audit history.',
                  })
                }
              >
                Revoke
              </Button>
            ) : null}
            {canRestore && item.status === 'revoked' ? (
              <Button
                type="link"
                onClick={() =>
                  onSelect({
                    kind: 'restore',
                    id: item.id,
                    label: item.productSku,
                    currentState: 'revoked',
                    targetState: 'new active grant',
                    impactSummary:
                      'Create one new linked grant; the revoked original remains unchanged.',
                  })
                }
              >
                Restore
              </Button>
            ) : null}
          </Space>
        ),
      },
    ],
    [canGrantOrRevoke, canRestore, onSelect],
  );
  return (
    <Table
      rowKey="id"
      dataSource={[...items]}
      columns={columns}
      pagination={false}
      locale={{ emptyText: 'No entitlement records.' }}
      scroll={{ x: 'max-content' }}
    />
  );
}

function DeletionPanel({
  items,
}: {
  readonly items: readonly AdminAccountDeletionRequestSummary[];
}) {
  return (
    <List
      dataSource={[...items]}
      locale={{ emptyText: 'No account deletion requests.' }}
      renderItem={(item) => (
        <List.Item>
          <Space direction="vertical" size={0}>
            <Space>
              <EntityStatus status={item.status} />
              <Typography.Text copyable>{item.id}</Typography.Text>
            </Space>
            <Typography.Text type="secondary">
              Attempt {item.attemptCount} · execute after{' '}
              <DateTimeDisplay value={item.executeAfter} />
              {item.lastErrorCode ? ` · ${item.lastErrorCode}` : ''}
            </Typography.Text>
          </Space>
        </List.Item>
      )}
    />
  );
}
