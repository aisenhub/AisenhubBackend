import { spawnSync } from 'node:child_process';

const command = process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm';
const result = spawnSync(
  command,
  ['exec', 'supabase', 'test', 'db', 'supabase/tests/rls', '--local'],
  { stdio: 'inherit', shell: process.platform === 'win32' },
);

if (result.error) {
  throw result.error;
}

process.exit(result.status ?? 1);
