import { useEffect, useState } from 'react';
import { Button, Card, Descriptions, Flex, Spin, Typography } from 'antd';

import {
  AdminSystemHealthResponseSchema,
  type AdminSystemHealthResponse,
} from '@aisenhub/contracts';
import { EntityStatus, ErrorState, EmptyState } from '@aisenhub/design-system';

import { adminRuntime } from '../../../providers/admin-runtime';

export function SystemHealthPage() {
  const [health, setHealth] = useState<AdminSystemHealthResponse | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [loading, setLoading] = useState(true);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    void adminRuntime.dataProvider
      .getSystemHealth()
      .then((result) => {
        if (active) setHealth(AdminSystemHealthResponseSchema.parse(result.data));
      })
      .catch((cause: unknown) => {
        if (active) setError(cause instanceof Error ? cause : new Error('Health check failed.'));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [reloadToken]);

  return (
    <Flex vertical gap={16}>
      <div>
        <Typography.Title level={2} style={{ marginBottom: 4 }}>
          System health
        </Typography.Title>
        <Typography.Paragraph type="secondary" style={{ marginBottom: 0 }}>
          Minimal service readiness checks returned by the Platform Backend.
        </Typography.Paragraph>
      </div>
      <Card>
        {loading ? (
          <Spin tip="Checking platform services…" />
        ) : error ? (
          <ErrorState
            description={error.message}
            action={<Button onClick={() => setReloadToken((value) => value + 1)}>Retry</Button>}
          />
        ) : health ? (
          <Descriptions bordered column={1}>
            <Descriptions.Item label="Overall status">
              <EntityStatus status={health.status} />
            </Descriptions.Item>
            {health.checks.map((check) => (
              <Descriptions.Item key={check.name} label={check.name}>
                <EntityStatus status={check.status} />
              </Descriptions.Item>
            ))}
          </Descriptions>
        ) : (
          <EmptyState description="No health checks were returned." />
        )}
      </Card>
    </Flex>
  );
}
