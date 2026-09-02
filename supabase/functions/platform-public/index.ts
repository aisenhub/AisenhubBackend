import { routePlatformPublic } from '../_shared/public-api.ts';
import { withTelemetry } from '../_shared/telemetry.ts';

Deno.serve((request) => withTelemetry(request, routePlatformPublic));
