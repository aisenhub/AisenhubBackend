import { spawnSync } from 'node:child_process';
import process from 'node:process';

const steps = [
  ['Reset Local database', ['db:reset']],
  ['Verify deterministic fixtures', ['fixtures:verify']],
  ['Run release-candidate browser journey', ['test:e2e', '--workers=1']],
  ['Run redemption concurrency journey', ['test:redemption:concurrency']],
  [
    'Run Commerce resilience journey',
    ['exec', 'vitest', 'run', 'tests/integration/commerce-resilience.test.mjs'],
  ],
];

for (const [label, args] of steps) {
  console.log(`\n[release-candidate] ${label}`);
  const result = spawnSync('pnpm', args, {
    cwd: process.cwd(),
    stdio: 'inherit',
    shell: process.platform === 'win32',
    env: {
      ...process.env,
      PLAYWRIGHT_BASE_URL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5176',
      PLAYWRIGHT_ADMIN_BASE_URL: process.env.PLAYWRIGHT_ADMIN_BASE_URL ?? 'http://localhost:5177',
    },
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

console.log(
  '\n[release-candidate] PASS: deterministic Local journey and Commerce resilience completed.',
);
