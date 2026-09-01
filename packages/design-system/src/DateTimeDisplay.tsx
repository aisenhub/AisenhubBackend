import { Typography } from 'antd';
import { createElement } from 'react';

export type DateTimeDisplayProps = {
  value: Date | string;
  locale?: string;
  timeZone?: string;
  mode?: 'exact' | 'relative';
  now?: Date;
};

function toDate(value: Date | string): Date | null {
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function formatDateTime(
  value: Date | string,
  options: Pick<DateTimeDisplayProps, 'locale' | 'timeZone'> = {},
): string {
  const date = toDate(value);
  if (!date) return '—';
  return new Intl.DateTimeFormat(options.locale ?? 'en-US', {
    dateStyle: 'medium',
    timeStyle: 'medium',
    timeZone: options.timeZone,
  }).format(date);
}

export function formatRelativeTime(value: Date | string, now = new Date(), locale = 'en-US') {
  const date = toDate(value);
  if (!date) return '—';

  const differenceSeconds = (date.getTime() - now.getTime()) / 1000;
  const absoluteSeconds = Math.abs(differenceSeconds);
  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ['year', 31_536_000],
    ['month', 2_592_000],
    ['day', 86_400],
    ['hour', 3_600],
    ['minute', 60],
    ['second', 1],
  ];
  const [unit, secondsPerUnit] = units.find(([, seconds]) => absoluteSeconds >= seconds) ?? [
    'second',
    1,
  ];
  return new Intl.RelativeTimeFormat(locale, { numeric: 'auto' }).format(
    Math.round(differenceSeconds / secondsPerUnit),
    unit,
  );
}

export function DateTimeDisplay({
  value,
  locale,
  timeZone,
  mode = 'exact',
  now,
}: DateTimeDisplayProps) {
  const text =
    mode === 'relative'
      ? formatRelativeTime(value, now, locale)
      : formatDateTime(value, { locale, timeZone });
  const label = mode === 'relative' ? formatDateTime(value, { locale, timeZone }) : text;
  return createElement(Typography.Text, { 'aria-label': label, title: label }, text);
}
