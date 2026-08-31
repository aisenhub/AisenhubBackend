import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const outputPath = path.join(repositoryRoot, 'supabase', 'types', 'database.ts');
const typesDirectory = path.dirname(outputPath);

fs.mkdirSync(typesDirectory, { recursive: true });
const generatedTypes = execFileSync(
  'pnpm',
  ['exec', 'supabase', 'gen', 'types', 'typescript', '--local'],
  {
    cwd: repositoryRoot,
    encoding: 'utf8',
  },
);
fs.writeFileSync(outputPath, generatedTypes);
console.log(`Generated Supabase types at ${path.relative(repositoryRoot, outputPath)}.`);
