import { routePlatformAdmin } from '../_shared/admin-api.ts';
import { healthResponse } from '../_shared/health.ts';

Deno.serve((request) => routePlatformAdmin(request, healthResponse));
