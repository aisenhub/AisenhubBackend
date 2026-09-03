import { describe, expect, it } from 'vitest';

import { apiPath } from '../supabase/functions/_shared/http';

describe('Supabase Function HTTP path normalization', () => {
  it.each([
    ['https://api.example.test/functions/v1/platform-api', '/'],
    ['https://api.example.test/functions/v1/platform-api/', '/'],
    ['https://api.example.test/functions/v1/platform-api/v1/account/me', '/v1/account/me'],
    ['https://api.example.test/v1/account/me', '/v1/account/me'],
  ])('normalizes %s to %s', (url, expected) => {
    expect(apiPath(new Request(url))).toBe(expected);
  });
});
