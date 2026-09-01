export const testRoles = ['anon', 'authenticated', 'service_role'] as const;

export type TestRole = (typeof testRoles)[number];

export interface TestRoleContext {
  readonly role: TestRole;
  readonly headers: Readonly<Record<string, string>>;
}

export function createTestRoleContext(role: TestRole): TestRoleContext {
  return {
    role,
    headers: {
      'x-test-role': role,
    },
  };
}
