import { Alert, Badge, Card, Col, Flex, Row, Skeleton, Statistic, Tag, Typography } from 'antd';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';

import {
  AdminOverviewResponseSchema,
  type AdminOverviewResponse,
  AdminSystemHealthResponseSchema,
  type AdminSystemHealthResponse,
} from '@aisenhub/contracts';
import { EntityStatus, ErrorState } from '@aisenhub/design-system';
import { adminRuntime } from '../../providers/admin-runtime';

export function OverviewPage() {
  const [overview, setOverview] = useState<AdminOverviewResponse | null>(null);
  const [health, setHealth] = useState<AdminSystemHealthResponse | null>(null);
  const [overviewError, setOverviewError] = useState<Error | null>(null);
  const [healthError, setHealthError] = useState<Error | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    void Promise.allSettled([
      adminRuntime.dataProvider.getOverview(),
      adminRuntime.dataProvider.getSystemHealth(),
    ]).then(([overviewResult, healthResult]) => {
      if (!active) return;
      if (overviewResult.status === 'fulfilled') {
        setOverview(AdminOverviewResponseSchema.parse(overviewResult.value.data));
      } else {
        setOverviewError(
          overviewResult.reason instanceof Error
            ? overviewResult.reason
            : new Error('The operations overview could not be loaded.'),
        );
      }
      if (healthResult.status === 'fulfilled') {
        setHealth(AdminSystemHealthResponseSchema.parse(healthResult.value.data));
      } else {
        setHealthError(
          healthResult.reason instanceof Error
            ? healthResult.reason
            : new Error('System health could not be loaded.'),
        );
      }
      setLoading(false);
    });
    return () => {
      active = false;
    };
  }, []);

  return (
    <Flex vertical gap={16}>
      <div>
        <Typography.Title level={2} style={{ marginBottom: 4 }}>
          Overview
        </Typography.Title>
        <Typography.Paragraph type="secondary" style={{ marginBottom: 0 }}>
          Actionable operational counts from the Platform Backend. Each card opens a fixed,
          permission-checked query.
        </Typography.Paragraph>
      </div>
      {overviewError ? (
        <Alert type="error" message="Overview unavailable" description={overviewError.message} />
      ) : null}
      <Row gutter={[16, 16]}>
        {loading && !overview ? (
          <Col span={24}>
            <Card>
              <Skeleton active />
            </Card>
          </Col>
        ) : overview ? (
          overview.cards.map((card) => (
            <Col xs={24} sm={12} xl={8} key={card.key}>
              <Card>
                <Statistic title={card.label} value={card.count} />
                <Flex justify="space-between" align="center" style={{ marginTop: 12 }}>
                  <Badge
                    status={
                      card.severity === 'critical'
                        ? 'error'
                        : card.severity === 'attention'
                          ? 'warning'
                          : 'success'
                    }
                    text={card.severity === 'neutral' ? 'No action needed' : 'Review required'}
                  />
                  <Link to={card.href}>Open list</Link>
                </Flex>
              </Card>
            </Col>
          ))
        ) : (
          <Col span={24}>
            <Card>
              <ErrorState description="No operational cards were returned." />
            </Card>
          </Col>
        )}
      </Row>
      <Row gutter={[16, 16]}>
        <Col xs={24} xl={16}>
          <Card
            title="Operations workspace"
            extra={<Tag color="green">Read-only</Tag>}
            styles={{ body: { padding: 24 } }}
          >
            <Typography.Paragraph style={{ color: '#58717b', marginBottom: 16 }}>
              Use the operational projections below to inspect current platform facts. Search,
              sorting, and authorization are handled by the Platform Backend.
            </Typography.Paragraph>
            <Flex gap={12} wrap>
              <Link to="/applications">Applications</Link>
              <Link to="/users">Users</Link>
              <Link to="/audit-logs">Audit logs</Link>
              <Link to="/system-health">System health</Link>
            </Flex>
          </Card>
        </Col>
        <Col xs={24} xl={8}>
          <Card title="System health" extra={<Link to="/system-health">Details</Link>}>
            {healthError ? (
              <Alert
                type="warning"
                message="Health unavailable"
                description={healthError.message}
              />
            ) : health ? (
              <Flex vertical gap={8}>
                <Flex justify="space-between">
                  <Typography.Text>Overall status</Typography.Text>
                  <EntityStatus status={health.status} />
                </Flex>
                {health.checks.map((check) => (
                  <Flex justify="space-between" key={check.name}>
                    <Typography.Text>{check.name}</Typography.Text>
                    <EntityStatus status={check.status} />
                  </Flex>
                ))}
              </Flex>
            ) : (
              <Skeleton active paragraph={{ rows: 2 }} />
            )}
          </Card>
        </Col>
      </Row>
    </Flex>
  );
}
