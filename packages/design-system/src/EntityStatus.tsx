import { Tag } from 'antd';
import { createElement } from 'react';

export type StatusTone = 'default' | 'success' | 'processing' | 'warning' | 'error';

type StatusPresentation = {
  label: string;
  tone: StatusTone;
};

const statusPresentation: Readonly<Record<string, StatusPresentation>> = {
  active: { label: 'Active', tone: 'success' },
  closed: { label: 'Closed', tone: 'default' },
  current: { label: 'Current', tone: 'processing' },
  draft: { label: 'Draft', tone: 'default' },
  expired: { label: 'Expired', tone: 'warning' },
  failed: { label: 'Failed', tone: 'error' },
  paid: { label: 'Paid', tone: 'success' },
  paused: { label: 'Paused', tone: 'warning' },
  pending: { label: 'Pending', tone: 'processing' },
  published: { label: 'Published', tone: 'success' },
  redeemed: { label: 'Redeemed', tone: 'default' },
  refunded: { label: 'Refunded', tone: 'warning' },
  retired: { label: 'Retired', tone: 'default' },
  revoked: { label: 'Revoked', tone: 'error' },
};

export function getStatusPresentation(status: string): StatusPresentation {
  const normalized = status.trim().toLowerCase();
  return statusPresentation[normalized] ?? { label: status, tone: 'default' };
}

export type EntityStatusProps = {
  status: string;
  label?: string;
};

export function EntityStatus({ status, label }: EntityStatusProps) {
  const presentation = getStatusPresentation(status);
  return createElement(
    Tag,
    { color: presentation.tone, 'aria-label': `${presentation.label} status` },
    label ?? presentation.label,
  );
}
