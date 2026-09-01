import { Typography } from 'antd';
import { createElement } from 'react';

export type MoneyDisplayProps = {
  amountMinor: bigint | number | string;
  currency: string;
  locale?: string;
};

function assertMinorUnits(amountMinor: MoneyDisplayProps['amountMinor']): number {
  if (typeof amountMinor === 'bigint') {
    const numeric = Number(amountMinor);
    if (!Number.isSafeInteger(numeric)) {
      throw new RangeError('Money amount exceeds the safe display range.');
    }
    return numeric;
  }

  const numeric = typeof amountMinor === 'string' ? Number(amountMinor) : amountMinor;
  if (!Number.isSafeInteger(numeric)) {
    throw new RangeError('Money amount must be a safe integer in minor units.');
  }
  return numeric;
}

export function formatMinorUnits(
  amountMinor: MoneyDisplayProps['amountMinor'],
  currency: string,
  locale = 'en-US',
): string {
  const normalizedCurrency = currency.trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(normalizedCurrency)) {
    throw new RangeError('Currency must be an ISO 4217 code.');
  }

  const formatter = new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: normalizedCurrency,
  });
  const fractionDigits = formatter.resolvedOptions().maximumFractionDigits ?? 2;
  return formatter.format(assertMinorUnits(amountMinor) / 10 ** fractionDigits);
}

export function MoneyDisplay({ amountMinor, currency, locale }: MoneyDisplayProps) {
  return createElement(
    Typography.Text,
    { 'aria-label': formatMinorUnits(amountMinor, currency, locale) },
    formatMinorUnits(amountMinor, currency, locale),
  );
}
