import { routePlatformApi } from '../_shared/platform-api.ts';
import { withTelemetry } from '../_shared/telemetry.ts';

Deno.serve((request) => withTelemetry(request, routePlatformApi));
