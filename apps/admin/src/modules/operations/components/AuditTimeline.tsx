import { Timeline, Typography } from 'antd';

import { DateTimeDisplay } from '@aisenhub/design-system';
import type { AdminAuditLogSummary } from '@aisenhub/contracts';

type AuditTimelineProps = {
  items: readonly AdminAuditLogSummary[];
};

export function AuditTimeline({ items }: AuditTimelineProps) {
  if (items.length === 0) return null;

  return (
    <Timeline
      items={items.map((item) => ({
        children: (
          <div>
            <Typography.Text strong>{item.action}</Typography.Text>
            <Typography.Text type="secondary"> · {item.targetType}</Typography.Text>
            <br />
            <Typography.Text type="secondary">{item.reason}</Typography.Text>
            <br />
            <DateTimeDisplay value={item.createdAt} />
          </div>
        ),
        key: item.id,
      }))}
    />
  );
}
