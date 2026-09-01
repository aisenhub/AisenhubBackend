import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const outputPath = path.join(repositoryRoot, 'supabase', 'types', 'database.ts');
const typesDirectory = path.dirname(outputPath);
const isWindows = process.platform === 'win32';
const supabaseCli = path.join(
  repositoryRoot,
  'node_modules',
  '.bin',
  isWindows ? 'supabase.cmd' : 'supabase',
);

fs.mkdirSync(typesDirectory, { recursive: true });
const args = ['gen', 'types', 'typescript', '--local'];
const result = isWindows
  ? spawnSync(
      process.env.ComSpec ?? 'cmd.exe',
      ['/d', '/s', '/c', `${supabaseCli} ${args.join(' ')}`],
      { cwd: repositoryRoot, encoding: 'utf8', shell: false },
    )
  : spawnSync(supabaseCli, args, { cwd: repositoryRoot, encoding: 'utf8', shell: false });

if (result.error) throw result.error;
if (result.status !== 0) {
  process.stderr.write(result.stderr ?? 'Supabase type generation failed.');
  process.exit(result.status ?? 1);
}

const generatedTypes = result.stdout;
fs.writeFileSync(outputPath, generatedTypes);
console.log(`Generated Supabase types at ${path.relative(repositoryRoot, outputPath)}.`);
