import { Card, Col, Descriptions, Flex, Row, Tag, Typography } from 'antd';
import { Link } from 'react-router-dom';

export function OverviewPage() {
  return (
    <Flex vertical gap={16}>
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
          <Card title="Foundation map">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="UI system">Ant Design</Descriptions.Item>
              <Descriptions.Item label="Admin framework">Refine</Descriptions.Item>
              <Descriptions.Item label="Data boundary">/v1/admin/*</Descriptions.Item>
              <Descriptions.Item label="Business authority">Platform Backend</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
      </Row>
    </Flex>
  );
}
