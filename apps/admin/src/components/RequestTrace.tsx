import { Descriptions, Typography } from 'antd';

export type RequestTraceProps = {
  readonly requestId?: string;
  readonly auditLogId?: string;
  readonly auditHref?: string;
  readonly entityHref?: string;
};

export function RequestTrace({ requestId, auditLogId, auditHref, entityHref }: RequestTraceProps) {
  if (!requestId && !auditLogId) return null;
  return (
    <Descriptions column={1} size="small" bordered>
      {requestId ? (
        <Descriptions.Item label="Request ID">
          <Typography.Text copyable={{ text: requestId }}>{requestId}</Typography.Text>
        </Descriptions.Item>
      ) : null}
      {auditLogId ? (
        <Descriptions.Item label="Audit log">
          {auditHref ? (
            <Typography.Link href={auditHref}>View audit {auditLogId}</Typography.Link>
          ) : (
            <Typography.Text copyable={{ text: auditLogId }}>{auditLogId}</Typography.Text>
          )}
        </Descriptions.Item>
      ) : null}
      {entityHref ? (
        <Descriptions.Item label="Entity">
          <Typography.Link href={entityHref}>Open affected entity</Typography.Link>
        </Descriptions.Item>
      ) : null}
    </Descriptions>
  );
}
