import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import process from 'node:process';

const repositoryRoot = process.cwd();
const docsRoot = join(repositoryRoot, 'docs');
const markdownFiles = [];
const failures = [];

function visit(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const absolutePath = join(directory, entry.name);
    if (entry.isDirectory()) visit(absolutePath);
    else if (entry.isFile() && extname(entry.name).toLowerCase() === '.md')
      markdownFiles.push(absolutePath);
  }
}

function report(filePath, message) {
  failures.push(`${filePath.slice(repositoryRoot.length + 1)}: ${message}`);
}

visit(docsRoot);

for (const filePath of markdownFiles) {
  const content = readFileSync(filePath, 'utf8');
  const fenceCount = (content.match(/^```/gm) ?? []).length;
  if (fenceCount % 2 !== 0) report(filePath, 'unbalanced Markdown code fence');

  for (const match of content.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
    const rawTarget = match[1].trim().replace(/^<|>$/g, '');
    if (/^(?:https?:|mailto:|#)/i.test(rawTarget)) continue;
    const targetPath = rawTarget.split('#', 1)[0].split('?', 1)[0];
    if (!targetPath) continue;
    const absoluteTarget = resolve(dirname(filePath), targetPath);
    if (!existsSync(absoluteTarget)) report(filePath, `broken local link: ${rawTarget}`);
  }
}

const envExample = join(repositoryRoot, 'supabase', '.env.example');
const envContent = readFileSync(envExample, 'utf8');
for (const line of envContent.split(/\r?\n/)) {
  if (!line || line.startsWith('#')) continue;
  const [, name, value = ''] = line.match(/^([A-Z0-9_]+)=(.*)$/) ?? [];
  if (!name) report(envExample, `invalid environment example line: ${line}`);
  if (
    name &&
    !/^(?:replace-with-.*|http:\/\/127\.0\.0\.1(?::\d+)?|local$|false$|\d+(?:\.\d+)?)$/i.test(value)
  ) {
    report(envExample, `environment example value must be local-safe or a placeholder: ${name}`);
  }
}

if (failures.length > 0) {
  console.error(`Documentation check failed with ${failures.length} finding(s):`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `Documentation check passed: ${markdownFiles.length} Markdown files and env example validated.`,
);
