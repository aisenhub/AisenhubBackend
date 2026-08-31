import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repositoryRoot = fileURLToPath(new URL('..', import.meta.url));
const checker = join(repositoryRoot, 'scripts', 'check-boundaries.mjs');

describe('workspace dependency boundaries', () => {
  it('passes for the repository', () => {
    expect(() => execFileSync(process.execPath, [checker], { cwd: repositoryRoot })).not.toThrow();
  });

  it('fails for a forbidden admin-client Supabase fixture', () => {
    const fixtureRoot = mkdtempSync(join(tmpdir(), 'aisenhub-boundary-'));
    const clientDirectory = join(fixtureRoot, 'packages', 'admin-client');
    mkdirSync(join(clientDirectory, 'src'), { recursive: true });
    writeFileSync(
      join(clientDirectory, 'package.json'),
      JSON.stringify({ name: '@aisenhub/admin-client', dependencies: {} }),
    );
    writeFileSync(
      join(clientDirectory, 'src', 'index.ts'),
      "import { createClient } from '@supabase/supabase-js';\nexport { createClient };\n",
    );

    const result = spawnSync(process.execPath, [checker, '--root', fixtureRoot], {
      cwd: repositoryRoot,
      encoding: 'utf8',
    });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('forbidden reference');
  });
});
