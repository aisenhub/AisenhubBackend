import { Alert, Button, Checkbox, Descriptions, Form, Input, Modal, Space, Typography } from 'antd';
import { useEffect, useState } from 'react';

import type { AdminClientError } from '@aisenhub/admin-client';

import { getAdminErrorNotification } from '../app/error-messages';
import { MfaRequirement, type AdminAssuranceState } from './MfaRequirement';
import { RequestTrace } from './RequestTrace';

export type DangerousActionTarget = {
  readonly label: string;
  readonly id: string;
  readonly currentState: string;
  readonly targetState: string;
  readonly impactSummary: string;
};

export type DangerousActionValues = {
  readonly reason: string;
  readonly confirmation: true;
};

export type DangerousActionResult = {
  readonly requestId: string;
  readonly auditLogId?: string;
  readonly auditHref?: string;
  readonly entityHref?: string;
};

export type DangerousActionDialogProps = {
  readonly open: boolean;
  readonly title: string;
  readonly actionLabel: string;
  readonly target: DangerousActionTarget;
  readonly assurance: AdminAssuranceState;
  readonly onConfirm: (values: DangerousActionValues) => Promise<DangerousActionResult>;
  readonly onCancel: () => void;
};

function getErrorRequestId(error: unknown): string | undefined {
  const clientError = error as Partial<AdminClientError> | null;
  return clientError?.requestId;
}

export function getCommandErrorPresentation(error: unknown) {
  const notification = getAdminErrorNotification(error);
  return {
    title: notification.message ?? 'Operation unavailable',
    description: notification.description ?? 'The operation could not be completed.',
    requestId: getErrorRequestId(error),
  };
}

export function DangerousActionDialog({
  open,
  title,
  actionLabel,
  target,
  assurance,
  onConfirm,
  onCancel,
}: DangerousActionDialogProps) {
  const [form] = Form.useForm<DangerousActionValues>();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [result, setResult] = useState<DangerousActionResult | null>(null);

  useEffect(() => {
    if (!open) {
      form.resetFields();
      setSubmitting(false);
      setError(null);
      setResult(null);
    }
  }, [form, open]);

  const handleFinish = async (values: DangerousActionValues) => {
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const commandResult = await onConfirm({
        reason: values.reason.trim(),
        confirmation: true,
      });
      setResult(commandResult);
    } catch (commandError) {
      setError(commandError);
    } finally {
      setSubmitting(false);
    }
  };

  const errorPresentation = error ? getCommandErrorPresentation(error) : null;
  return (
    <Modal
      open={open}
      title={title}
      onCancel={submitting ? undefined : onCancel}
      closable={!submitting}
      maskClosable={!submitting}
      destroyOnHidden
      footer={
        result ? (
          <Button type="primary" onClick={onCancel}>
            Done
          </Button>
        ) : (
          <Space>
            <Button onClick={onCancel} disabled={submitting}>
              Cancel
            </Button>
            <Button
              type="primary"
              danger
              htmlType="submit"
              form="dangerous-action-form"
              loading={submitting}
              disabled={assurance.aal !== 'aal2' || assurance.mfaState !== 'verified'}
            >
              {actionLabel}
            </Button>
          </Space>
        )
      }
    >
      {result ? (
        <Space orientation="vertical" size="middle" style={{ width: '100%' }}>
          <Alert type="success" showIcon message={`${actionLabel} completed`} />
          <RequestTrace
            requestId={result.requestId}
            auditLogId={result.auditLogId}
            auditHref={result.auditHref}
            entityHref={result.entityHref}
          />
        </Space>
      ) : (
        <Form
          id="dangerous-action-form"
          form={form}
          layout="vertical"
          onFinish={handleFinish}
          requiredMark="optional"
          initialValues={{ confirmation: false }}
        >
          <Space orientation="vertical" size="middle" style={{ width: '100%' }}>
            <DescriptionsBlock target={target} />
            <MfaRequirement {...assurance} />
            {errorPresentation ? (
              <Alert
                type="error"
                showIcon
                message={errorPresentation.title}
                description={
                  <Space orientation="vertical" size="small">
                    <Typography.Text>{errorPresentation.description}</Typography.Text>
                    {errorPresentation.requestId ? (
                      <Typography.Text type="secondary">
                        Request ID: {errorPresentation.requestId}
                      </Typography.Text>
                    ) : null}
                  </Space>
                }
              />
            ) : null}
            <Form.Item
              label="Reason"
              name="reason"
              rules={[
                { required: true, whitespace: true, message: 'Enter a reason for this operation.' },
              ]}
            >
              <Input.TextArea rows={3} placeholder="Explain why this operation is necessary." />
            </Form.Item>
            <Form.Item
              name="confirmation"
              valuePropName="checked"
              rules={[
                {
                  validator: (_, value) =>
                    value
                      ? Promise.resolve()
                      : Promise.reject(new Error('Confirm the operation to continue.')),
                },
              ]}
            >
              <Checkbox>
                I understand this operation changes the authoritative platform state.
              </Checkbox>
            </Form.Item>
          </Space>
        </Form>
      )}
    </Modal>
  );
}

function DescriptionsBlock({ target }: { readonly target: DangerousActionTarget }) {
  return (
    <Descriptions column={1} size="small" bordered>
      <Descriptions.Item label="Target">{target.label}</Descriptions.Item>
      <Descriptions.Item label="Immutable ID">
        <Typography.Text copyable={{ text: target.id }}>{target.id}</Typography.Text>
      </Descriptions.Item>
      <Descriptions.Item label="Current state">{target.currentState}</Descriptions.Item>
      <Descriptions.Item label="Target state">{target.targetState}</Descriptions.Item>
      <Descriptions.Item label="Impact">{target.impactSummary}</Descriptions.Item>
    </Descriptions>
  );
}
