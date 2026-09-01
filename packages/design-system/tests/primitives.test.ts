import { describe, expect, it } from 'vitest';

import {
  DateTimeDisplay,
  EntityStatus,
  EmptyState,
  ErrorState,
  LoadingState,
  MoneyDisplay,
  PermissionDeniedState,
  formatDateTime,
  formatMinorUnits,
  formatRelativeTime,
  getStatusPresentation,
} from '../src';

describe('EntityStatus', () => {
  it('maps domain statuses to stable semantic tones', () => {
    expect(getStatusPresentation('PAID')).toEqual({ label: 'Paid', tone: 'success' });
    expect(getStatusPresentation('unrecognized')).toEqual({
      label: 'unrecognized',
      tone: 'default',
    });

    const element = EntityStatus({ status: 'revoked' });
    expect(element.props.color).toBe('error');
    expect(element.props['aria-label']).toBe('Revoked status');
  });
});

describe('MoneyDisplay', () => {
  it('formats minor units without page-level arithmetic', () => {
    expect(formatMinorUnits(1234, 'USD', 'en-US')).toBe('$12.34');
    expect(formatMinorUnits('1234', 'JPY', 'ja-JP')).toBe('￥1,234');
    expect(() => formatMinorUnits(1.2, 'USD')).toThrow(RangeError);

    const element = MoneyDisplay({ amountMinor: 1234, currency: 'USD', locale: 'en-US' });
    expect(element.props['aria-label']).toBe('$12.34');
  });
});

describe('DateTimeDisplay', () => {
  const value = '2026-01-01T00:00:00.000Z';
  const now = new Date('2026-01-02T00:00:00.000Z');

  it('renders exact timestamps using the requested timezone', () => {
    expect(formatDateTime(value, { locale: 'en-US', timeZone: 'UTC' })).toContain('Jan 1, 2026');
    expect(formatDateTime('not-a-date')).toBe('—');
  });

  it('supports relative display with deterministic test time', () => {
    expect(formatRelativeTime(value, now, 'en-US')).toBe('yesterday');
    const element = DateTimeDisplay({
      value,
      mode: 'relative',
      now,
      locale: 'en-US',
      timeZone: 'UTC',
    });
    expect(element.props.title).toContain('Jan 1, 2026');
  });
});

describe('state primitives', () => {
  it('exposes accessible loading, empty, error, and permission states', () => {
    expect(LoadingState({}).props['aria-live']).toBe('polite');
    expect(LoadingState({}).props['aria-busy']).toBe(true);
    expect(EmptyState({}).props.description).toBe('No records to display.');
    expect(ErrorState({}).props['aria-live']).toBe('assertive');
    expect(PermissionDeniedState({}).props.status).toBe('403');
  });
});
