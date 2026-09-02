import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import process from 'node:process';

const repositoryRoot = resolve(import.meta.dirname, '..');
const commercialConfigPath = resolve(
  repositoryRoot,
  'docs',
  'implementation',
  'PRODUCTION_COMMERCIAL_CONFIG.md',
);
const realSaleEnabled = process.env.AISENHUB_PRODUCTION_REAL_SALE === 'true';
const result = {
  status: realSaleEnabled ? 'requires_human_gate' : 'deferred',
  realSaleEnabled,
  commercialConfigurationPresent: existsSync(commercialConfigPath),
  productionMutation: false,
  message: realSaleEnabled
    ? 'Real-sale configuration requires the consolidated HG-002 commercial decision.'
    : 'No real-sale configuration is enabled; commercial freeze is deferred while using test fixtures.',
};

console.log(JSON.stringify(result, null, 2));
if (realSaleEnabled && !result.commercialConfigurationPresent) process.exitCode = 1;
