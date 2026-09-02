import { Empty, Result, Spin, Typography } from 'antd';
import { createElement, type ReactNode } from 'react';

export type StateMessageProps = {
  action?: ReactNode;
  description?: string;
  title?: string;
};

export function LoadingState({ description = 'Loading…' }: StateMessageProps) {
  return createElement(
    'div',
    {
      'aria-busy': true,
      'aria-label': description,
      'aria-live': 'polite',
      role: 'status',
      style: { padding: 32, textAlign: 'center' },
    },
    createElement(Spin),
    createElement(Typography.Paragraph, { style: { marginBottom: 0, marginTop: 12 } }, description),
  );
}

export function EmptyState({ description = 'No records to display.' }: StateMessageProps) {
  return createElement(Empty, { description, image: Empty.PRESENTED_IMAGE_SIMPLE });
}

export function ErrorState({
  action,
  title = 'Unable to load this information',
  description = 'Try again or contact support if the problem continues.',
}: StateMessageProps) {
  return createElement(Result, {
    extra: action,
    status: 'error',
    title,
    subTitle: description,
    'aria-live': 'assertive',
  });
}

export function PermissionDeniedState({
  title = 'Permission denied',
  description = 'Your Admin role does not allow this operation.',
}: StateMessageProps) {
  return createElement(Result, {
    status: '403',
    title,
    subTitle: description,
    'aria-live': 'polite',
  });
}
