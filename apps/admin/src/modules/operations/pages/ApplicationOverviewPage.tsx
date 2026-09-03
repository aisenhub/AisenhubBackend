import { Alert, Button, Card, Form, Input, Modal, Space, Spin, Table, Tag, Typography } from 'antd';
import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import type {
  AdminApplicationMembershipSummary,
  AdminCreateApplicationMembershipRequest,
  AdminCreateOAuthClientRequest,
  OAuthClientBindingSummary,
} from '@aisenhub/contracts';

import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';
import { adminRuntime } from '../../../providers/admin-runtime';

type MembershipForm = Pick<AdminCreateApplicationMembershipRequest, 'userId' | 'reason'>;
type OAuthForm = Omit<AdminCreateOAuthClientRequest, 'confirmation'>;

export function ApplicationOverviewPage() {
  const { applicationId } = useParams<{ applicationId: string }>();
  const session = adminRuntime.session.getSession();
  const canManage = session?.role === 'owner' || session?.role === 'admin';
  const [memberships, setMemberships] = useState<AdminApplicationMembershipSummary[]>([]);
  const [clients, setClients] = useState<OAuthClientBindingSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [membershipOpen, setMembershipOpen] = useState(false);
  const [clientOpen, setClientOpen] = useState(false);
  const [membershipForm] = Form.useForm<MembershipForm>();
  const [clientForm] = Form.useForm<OAuthForm>();

  const reload = useCallback(() => setReloadToken((value) => value + 1), []);

  useEffect(() => {
    if (!applicationId) return;
    let active = true;
    setLoading(true);
    setError(null);
    void Promise.all([
      adminRuntime.dataProvider.getApplicationMemberships(applicationId),
      adminRuntime.dataProvider.getApplicationOAuthClients(applicationId),
    ]).then(
      ([membershipResult, clientResult]) => {
        if (!active) return;
        setMemberships(membershipResult.data.items);
        setClients(clientResult.data.items);
        setLoading(false);
      },
      (requestError: unknown) => {
        if (!active) return;
        setError(requestError);
        setLoading(false);
      },
    );
    return () => {
      active = false;
    };
  }, [applicationId, reloadToken]);

  if (!applicationId) return <Alert type="error" message="Application id is required." />;
  if (loading && !memberships.length && !clients.length)
    return <Spin tip="Loading application operations…" />;
  if (error) {
    return (
      <Alert
        type="error"
        showIcon
        message="Application operations unavailable"
        description="Refresh the page or contact support with the request ID."
      />
    );
  }

  const submitMembership = async (values: MembershipForm) => {
    await adminRuntime.commands.createApplicationMembership(applicationId, {
      ...values,
      confirmation: true,
      createdSource: 'admin',
    });
    setMembershipOpen(false);
    membershipForm.resetFields();
    reload();
  };

  const submitClient = async (values: OAuthForm) => {
    await adminRuntime.commands.createOAuthClient(applicationId, { ...values, confirmation: true });
    setClientOpen(false);
    clientForm.resetFields();
    reload();
  };

  const changeMembership = async (
    membership: AdminApplicationMembershipSummary,
    action: 'suspend' | 'restore',
  ) => {
    const reason = globalThis.prompt(`Reason for ${action} membership`)?.trim();
    if (!reason) return;
    if (action === 'suspend') {
      await adminRuntime.commands.suspendApplicationMembership(applicationId, membership.id, {
        reason,
        confirmation: true,
      });
    } else {
      await adminRuntime.commands.restoreApplicationMembership(applicationId, membership.id, {
        reason,
        confirmation: true,
      });
    }
    reload();
  };

  const changeClient = async (client: OAuthClientBindingSummary, action: 'disable' | 'restore') => {
    const reason = globalThis.prompt(`Reason for ${action} OAuth client`)?.trim();
    if (!reason) return;
    if (action === 'disable') {
      await adminRuntime.commands.disableOAuthClient(applicationId, client.id, {
        reason,
        confirmation: true,
      });
    } else {
      await adminRuntime.commands.restoreOAuthClient(applicationId, client.id, {
        reason,
        confirmation: true,
      });
    }
    reload();
  };

  return (
    <Space direction="vertical" size="large" style={{ width: '100%' }}>
      <div>
        <Typography.Title level={2} style={{ marginBottom: 4 }}>
          Application operations
        </Typography.Title>
        <Typography.Paragraph type="secondary" style={{ marginBottom: 0 }}>
          Manage application membership and OAuth client bindings. Provider secrets and redirect
          configuration are never stored here.
        </Typography.Paragraph>
      </div>
      <Card
        title="Application members"
        extra={
          canManage ? <Button onClick={() => setMembershipOpen(true)}>Add member</Button> : null
        }
      >
        <Table<AdminApplicationMembershipSummary>
          rowKey="id"
          dataSource={memberships}
          pagination={{ pageSize: 10 }}
          columns={[
            { title: 'User', dataIndex: 'userId' },
            {
              title: 'Status',
              dataIndex: 'status',
              render: (status: string) => <EntityStatus status={status} />,
            },
            { title: 'Source', dataIndex: 'createdSource' },
            {
              title: 'Joined',
              dataIndex: 'joinedAt',
              render: (value: string) => <DateTimeDisplay value={value} />,
            },
            {
              title: 'Actions',
              render: (_: unknown, record) =>
                canManage && ['active', 'suspended'].includes(record.status) ? (
                  <Button
                    size="small"
                    onClick={() =>
                      void changeMembership(
                        record,
                        record.status === 'active' ? 'suspend' : 'restore',
                      )
                    }
                  >
                    {record.status === 'active' ? 'Suspend' : 'Restore'}
                  </Button>
                ) : null,
            },
          ]}
        />
      </Card>
      <Card
        title="OAuth clients"
        extra={
          canManage ? <Button onClick={() => setClientOpen(true)}>Register client</Button> : null
        }
      >
        <Table<OAuthClientBindingSummary>
          rowKey="id"
          dataSource={clients}
          pagination={{ pageSize: 10 }}
          columns={[
            { title: 'Name', dataIndex: 'name' },
            { title: 'Provider', dataIndex: 'provider' },
            { title: 'Client id', dataIndex: 'externalClientId' },
            {
              title: 'Environment',
              dataIndex: 'environment',
              render: (value: string) => <Tag>{value}</Tag>,
            },
            {
              title: 'Status',
              dataIndex: 'status',
              render: (status: string) => <EntityStatus status={status} />,
            },
            {
              title: 'Actions',
              render: (_: unknown, record) =>
                canManage && ['active', 'disabled'].includes(record.status) ? (
                  <Button
                    size="small"
                    onClick={() =>
                      void changeClient(record, record.status === 'active' ? 'disable' : 'restore')
                    }
                  >
                    {record.status === 'active' ? 'Disable' : 'Restore'}
                  </Button>
                ) : null,
            },
          ]}
        />
      </Card>
      <Modal
        title="Add application member"
        open={membershipOpen}
        onCancel={() => setMembershipOpen(false)}
        onOk={() => void membershipForm.submit()}
        confirmLoading={loading}
      >
        <Form
          form={membershipForm}
          layout="vertical"
          onFinish={(values) => void submitMembership(values)}
        >
          <Form.Item
            name="userId"
            label="User id"
            rules={[{ required: true, type: 'string', min: 36 }]}
          >
            <Input />
          </Form.Item>
          <Form.Item name="reason" label="Reason" rules={[{ required: true, min: 1, max: 1000 }]}>
            <Input.TextArea rows={3} />
          </Form.Item>
        </Form>
      </Modal>
      <Modal
        title="Register OAuth client"
        open={clientOpen}
        onCancel={() => setClientOpen(false)}
        onOk={() => void clientForm.submit()}
        confirmLoading={loading}
      >
        <Form form={clientForm} layout="vertical" onFinish={(values) => void submitClient(values)}>
          <Form.Item name="name" label="Name" rules={[{ required: true, max: 200 }]}>
            <Input />
          </Form.Item>
          <Form.Item name="provider" label="Provider" rules={[{ required: true, max: 100 }]}>
            <Input placeholder="supabase" />
          </Form.Item>
          <Form.Item
            name="externalClientId"
            label="External client id"
            rules={[{ required: true, max: 255 }]}
          >
            <Input />
          </Form.Item>
          <Form.Item name="clientType" label="Client type" rules={[{ required: true }]}>
            <Input placeholder="public or confidential" />
          </Form.Item>
          <Form.Item name="environment" label="Environment" rules={[{ required: true }]}>
            <Input placeholder="development, staging or production" />
          </Form.Item>
          <Form.Item name="reason" label="Reason" rules={[{ required: true, min: 1, max: 1000 }]}>
            <Input.TextArea rows={3} />
          </Form.Item>
        </Form>
      </Modal>
    </Space>
  );
}
