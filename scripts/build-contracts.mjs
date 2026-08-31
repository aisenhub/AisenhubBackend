import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const lockPath = path.join(repositoryRoot, 'node_modules', '.contracts-build-lock');
const sleepBuffer = new Int32Array(new SharedArrayBuffer(4));

for (;;) {
  try {
    fs.mkdirSync(lockPath);
    break;
  } catch (error) {
    if (!(error instanceof Error) || !('code' in error) || error.code !== 'EEXIST') throw error;
    Atomics.wait(sleepBuffer, 0, 0, 100);
  }
}

try {
  const pnpmExecutable = process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm';
  execFileSync(pnpmExecutable, ['--filter', '@aisenhub/contracts', 'build'], {
    cwd: repositoryRoot,
    shell: process.platform === 'win32',
    stdio: 'inherit',
  });
} finally {
  fs.rmSync(lockPath, { recursive: true, force: true });
}
