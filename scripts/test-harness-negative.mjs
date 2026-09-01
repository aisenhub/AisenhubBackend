import { spawnSync } from 'node:child_process';

if (process.argv.includes('--fixture')) {
  throw new Error('intentional harness failure fixture');
}

const result = spawnSync(process.execPath, [process.argv[1], '--fixture'], {
  encoding: 'utf8',
});

if (result.status === 0) {
  throw new Error('The intentional failure fixture unexpectedly passed.');
}

console.log(
  'Negative harness self-check passed: a failing fixture produced a nonzero exit status.',
);
