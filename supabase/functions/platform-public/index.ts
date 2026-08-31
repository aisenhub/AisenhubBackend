import { healthResponse } from '../_shared/health.ts';

Deno.serve(() => healthResponse('platform-public'));
