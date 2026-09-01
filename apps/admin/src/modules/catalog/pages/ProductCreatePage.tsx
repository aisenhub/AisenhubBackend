import { Alert, Button, Card, Form, Input, Select, Space, Typography } from 'antd';
import { useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';

import { getAdminErrorNotification } from '../../../app/error-messages';
import { adminRuntime } from '../../../providers/admin-runtime';

type ProductDraftValues = {
  sku: string;
  name: string;
  billingType: 'one_time' | 'subscription' | 'credits';
  entitlementPolicy?: 'snapshot' | 'all_apps_access';
  reason: string;
};

export function ProductCreatePage() {
  const [form] = Form.useForm<ProductDraftValues>();
  const navigate = useNavigate();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const onFinish = async (values: ProductDraftValues) => {
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await adminRuntime.dataProvider.createProduct(values);
      navigate(`/catalog/products/${result.data.id}`);
    } catch (commandError) {
      setError(commandError);
    } finally {
      setSubmitting(false);
    }
  };

  const errorMessage = error ? getAdminErrorNotification(error) : null;
  return (
    <FlexPage
      title="Create product draft"
      description="Create a draft product identity; publication remains a separate Business Command."
    >
      {errorMessage ? (
        <Alert
          type="error"
          showIcon
          message={errorMessage.message}
          description={errorMessage.description}
        />
      ) : null}
      <Card>
        <Form form={form} layout="vertical" onFinish={onFinish} requiredMark="optional">
          <Form.Item
            name="sku"
            label="SKU"
            rules={[
              {
                required: true,
                pattern: /^[A-Z0-9][A-Z0-9_-]*$/,
                message: 'Use uppercase letters, numbers, hyphens, or underscores.',
              },
            ]}
          >
            <Input placeholder="AISENLENS_PRO" />
          </Form.Item>
          <Form.Item
            name="name"
            label="Name"
            rules={[{ required: true, whitespace: true, message: 'Enter a product name.' }]}
          >
            <Input />
          </Form.Item>
          <Form.Item
            name="billingType"
            label="Billing type"
            rules={[{ required: true, message: 'Choose a billing type.' }]}
          >
            <Select
              options={[
                { value: 'one_time', label: 'One-time' },
                { value: 'subscription', label: 'Subscription' },
                { value: 'credits', label: 'Credits' },
              ]}
            />
          </Form.Item>
          <Form.Item name="entitlementPolicy" label="Entitlement policy">
            <Select
              allowClear
              options={[
                { value: 'snapshot', label: 'Snapshot' },
                { value: 'all_apps_access', label: 'All apps access' },
              ]}
            />
          </Form.Item>
          <Form.Item
            name="reason"
            label="Reason"
            rules={[
              { required: true, whitespace: true, message: 'Enter a reason for this draft.' },
            ]}
          >
            <Input.TextArea rows={3} placeholder="Explain why this draft is needed." />
          </Form.Item>
          <Space>
            <Button onClick={() => navigate('/catalog/products')} disabled={submitting}>
              Cancel
            </Button>
            <Button type="primary" htmlType="submit" loading={submitting}>
              Create draft
            </Button>
          </Space>
        </Form>
      </Card>
    </FlexPage>
  );
}

function FlexPage({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <div>
      <Typography.Title level={2} style={{ marginBottom: 4 }}>
        {title}
      </Typography.Title>
      <Typography.Paragraph type="secondary">{description}</Typography.Paragraph>
      {children}
    </div>
  );
}
