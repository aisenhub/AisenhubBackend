import { Button, Table, Typography } from 'antd';
import type { BaseRecord, HttpError } from '@refinedev/core';
import type { TableProps } from 'antd';

import { EmptyState, ErrorState } from '@aisenhub/design-system';

type DataTableProps<TRecord extends BaseRecord> = {
  tableProps: TableProps<TRecord>;
  isError: boolean;
  error?: HttpError | null;
  emptyDescription: string;
  onRetry?: () => void;
};

export function DataTable<TRecord extends BaseRecord>({
  tableProps,
  isError,
  error,
  emptyDescription,
  onRetry,
}: DataTableProps<TRecord>) {
  if (isError) {
    return (
      <ErrorState
        description={error?.message ?? 'The Admin query could not be loaded.'}
        action={onRetry ? <Button onClick={onRetry}>Retry</Button> : undefined}
      />
    );
  }

  return (
    <Table<TRecord>
      {...tableProps}
      locale={{
        emptyText: <EmptyState description={emptyDescription} />,
      }}
      rowKey={(record) => String(record.id ?? JSON.stringify(record))}
      scroll={{ x: 'max-content' }}
      title={() => (
        <Typography.Text type="secondary">
          Read-only projection · filters and sorting are evaluated by Platform Backend
        </Typography.Text>
      )}
    />
  );
}
