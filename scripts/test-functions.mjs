import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const functionsRoot = path.join(repositoryRoot, 'supabase', 'functions');
const functionNames = ['platform-api', 'platform-public', 'platform-admin', 'payment-webhook'];
const codeGenerationSource = path.join(functionsRoot, '_shared', 'redemption-code.ts');
const adminPermissionsSource = path.join(functionsRoot, '_shared', 'admin-permissions.ts');
const adminPermissionsMatrix = path.join(
  repositoryRoot,
  'packages',
  'contracts',
  'src',
  'admin-permissions.matrix.json',
);
const adminApiSource = path.join(functionsRoot, '_shared', 'admin-api.ts');
const adminQueryMigration = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260901059000_admin_query_projections.sql',
);
const adminCatalogCommandMigration = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260901110632_admin_catalog_commands.sql',
);
const adminRedemptionCommandMigration = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260901112513_admin_redemption_commands.sql',
);
const adminManualOrderVerifyMigration = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260901190000_admin_manual_order_verify.sql',
);
const commerceRefundMigration = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260901200000_commerce_refunds.sql',
);

for (const functionName of functionNames) {
  const entrypoint = path.join(functionsRoot, functionName, 'index.ts');
  const source = fs.readFileSync(entrypoint, 'utf8');
  if (!source.includes('Deno.serve(')) {
    throw new Error(`Function ${functionName} does not expose a Deno handler.`);
  }
  if (functionName === 'platform-api') {
    if (!source.includes('../_shared/platform-api.ts')) {
      throw new Error(`Function ${functionName} does not use the platform API router.`);
    }
  } else if (
    functionName === 'platform-public'
      ? !source.includes('../_shared/public-api.ts')
      : !source.includes('../_shared/health.ts')
  ) {
    throw new Error(`Function ${functionName} does not use the shared health handler.`);
  }
}

if (process.argv.includes('code-generation')) {
  const source = fs.readFileSync(codeGenerationSource, 'utf8');
  for (const required of ['crypto.getRandomValues', 'crypto.subtle', 'toRedemptionCodeRecord']) {
    if (!source.includes(required)) {
      throw new Error(`Redemption code generation is missing ${required}.`);
    }
  }
  if (source.includes('console.log') || source.includes('console.error')) {
    throw new Error('Redemption code generation must not log code material.');
  }
  console.log('Redemption code generation security smoke check passed.');
}

if (process.argv.includes('admin-permissions')) {
  const matrix = JSON.parse(fs.readFileSync(adminPermissionsMatrix, 'utf8'));
  const actions = Object.keys(matrix.actions ?? {});
  const source = fs.readFileSync(adminPermissionsSource, 'utf8');
  if (actions.length === 0 || !source.includes('admin-permissions.matrix.json')) {
    throw new Error('Admin permission adapter is missing the complete shared action matrix.');
  }
  if (!source.includes('evaluateBackendAdminAction')) {
    throw new Error('Admin permission adapter does not expose the backend evaluator.');
  }
  console.log(`Admin permission mapping smoke check passed for ${actions.length} actions.`);
}

if (
  process.argv.includes('admin-query') ||
  process.argv.includes('admin-catalog-query') ||
  process.argv.includes('catalog-drafts') ||
  process.argv.includes('catalog-commands')
) {
  const source = fs.readFileSync(adminApiSource, 'utf8');
  const migration = fs.readFileSync(adminQueryMigration, 'utf8');
  const commandMigration = fs.readFileSync(adminCatalogCommandMigration, 'utf8');
  for (const required of [
    '/v1/admin/system-health',
    'applications|users|origins|features|products|product-versions|prices|redemption-batches|redemption-codes|entitlements|redemptions|feedback|audit-logs',
    'admin_query_resource',
    'admin_query_catalog_resource',
    'admin_product_overview',
    'admin_catalog_resource_detail',
    ...(process.argv.includes('catalog-drafts') ? ['admin_catalog_draft_command'] : []),
    ...(process.argv.includes('catalog-commands') ? ['admin_catalog_command'] : []),
    'ServiceRpcError',
  ]) {
    if (
      !source.includes(required) &&
      !migration.includes(required) &&
      !commandMigration.includes(required)
    ) {
      throw new Error(`Admin query surface is missing ${required}.`);
    }
  }
  if (migration.includes('execute format') || migration.includes('p_table')) {
    throw new Error('Admin query projection must not accept arbitrary SQL or table names.');
  }
  console.log('Admin query projection smoke check passed.');
}

if (process.argv.includes('redemption-admin')) {
  const source = fs.readFileSync(adminApiSource, 'utf8');
  const migration = fs.readFileSync(adminRedemptionCommandMigration, 'utf8');
  for (const required of [
    '/v1/admin/redemption-batches',
    'redemptionCommandRoute',
    'admin_redemption_command',
    'redemptionPepperFromEnv',
    'codeRecords',
  ]) {
    if (!source.includes(required) && !migration.includes(required)) {
      throw new Error(`Redemption Admin command surface is missing ${required}.`);
    }
  }
  if (migration.includes('plaintext') && migration.includes('code_plaintext')) {
    throw new Error('Redemption command migration must not store plaintext code material.');
  }
  console.log('Redemption Admin command smoke check passed.');
}

if (process.argv.includes('manual-verify')) {
  const source = fs.readFileSync(adminApiSource, 'utf8');
  const migration = fs.readFileSync(adminManualOrderVerifyMigration, 'utf8');
  for (const required of [
    '/v1/admin/orders/',
    'orderCommandRoute',
    'admin_verify_order',
    'fulfill_paid_order',
    'orders.verify',
    'Idempotency-Key',
  ]) {
    if (!source.includes(required) && !migration.includes(required)) {
      throw new Error(`Manual order verification surface is missing ${required}.`);
    }
  }
  if (migration.includes('payload') && migration.includes('card_number')) {
    throw new Error('Manual order verification must not persist sensitive payment payloads.');
  }
  console.log('Manual order verification smoke check passed.');
}

if (process.argv.includes('refund')) {
  const source = fs.readFileSync(adminApiSource, 'utf8');
  const migration = fs.readFileSync(commerceRefundMigration, 'utf8');
  for (const required of [
    'order-items',
    'orderItemCommandRoute',
    'admin_refund_order_item',
    'refund_order_item',
    'order_items.refund',
  ]) {
    if (!source.includes(required) && !migration.includes(required)) {
      throw new Error(`OrderItem refund surface is missing ${required}.`);
    }
  }
  if (migration.includes('order_id = p_order_item_id')) {
    throw new Error('OrderItem refund must lock and target an order item directly.');
  }
  console.log('OrderItem refund smoke check passed.');
}

console.log(`Function shell smoke check passed for ${functionNames.length} functions.`);
