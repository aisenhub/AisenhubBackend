import { routePlatformAdmin } from '../_shared/admin-api.ts';
import { healthResponse } from '../_shared/health.ts';
import { withTelemetry } from '../_shared/telemetry.ts';

Deno.serve((request) =>
  withTelemetry(request, (innerRequest) => routePlatformAdmin(innerRequest, healthResponse)),
);
