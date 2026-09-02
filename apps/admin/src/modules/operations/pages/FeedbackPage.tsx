import { DateTimeDisplay, EntityStatus } from '@aisenhub/design-system';
import type { AdminFeedbackSummary } from '@aisenhub/contracts';

import { ResourcePage } from './ResourcePage';

export function FeedbackPage() {
  return (
    <ResourcePage<AdminFeedbackSummary>
      resource="feedback"
      title="Feedback"
      description="Review user feedback through the role-filtered Platform Backend projection."
      emptyDescription="No feedback matches the current filters."
      initialSort="createdAt"
      statusOptions={['open', 'in_progress', 'resolved', 'closed']}
      columns={[
        { dataIndex: 'title', key: 'title', sorter: true, title: 'Title' },
        { dataIndex: 'kind', key: 'kind', title: 'Kind' },
        { dataIndex: 'appSlug', key: 'appSlug', title: 'Application' },
        {
          dataIndex: 'status',
          key: 'status',
          sorter: true,
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          dataIndex: 'createdAt',
          key: 'createdAt',
          sorter: true,
          title: 'Created',
          render: (value: string) => <DateTimeDisplay value={value} />,
        },
      ]}
    />
  );
}
