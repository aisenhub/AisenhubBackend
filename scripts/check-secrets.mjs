import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const trackedFiles = execFileSync('git', ['ls-files', '-z'], {
  cwd: repositoryRoot,
  encoding: 'utf8',
})
  .split('\0')
  .filter(Boolean);

const secretPatterns = [
  { name: 'private key', pattern: /-----BEGIN [A-Z ]*PRIVATE KEY-----/ },
  { name: 'JWT', pattern: /\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b/ },
  { name: 'Supabase secret key', pattern: /\bsb_secret_[A-Za-z0-9_-]{8,}\b/ },
  { name: 'Supabase access token', pattern: /\bsbp_[A-Za-z0-9_-]{8,}\b/ },
  { name: 'Stripe secret', pattern: /\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{12,}\b/ },
  { name: 'webhook secret', pattern: /\bwhsec_[A-Za-z0-9]{12,}\b/ },
];

const findings = [];
for (const relativePath of trackedFiles) {
  const absolutePath = path.join(repositoryRoot, relativePath);
  let contents;
  try {
    contents = fs.readFileSync(absolutePath);
  } catch {
    continue;
  }

  if (contents.includes(0)) continue;
  const lines = contents.toString('utf8').split(/\r?\n/);
  for (const [lineNumber, line] of lines.entries()) {
    for (const { name, pattern } of secretPatterns) {
      if (pattern.test(line)) findings.push(`${relativePath}:${lineNumber + 1} (${name})`);
    }
  }
}

if (findings.length > 0) {
  console.error('Potential committed secret material detected:');
  for (const finding of findings) console.error(`- ${finding}`);
  process.exitCode = 1;
} else {
  console.log(`Secret scan passed for ${trackedFiles.length} tracked files.`);
}
