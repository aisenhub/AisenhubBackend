# Platform Telemetry

The shared Edge Function telemetry boundary is intentionally small and does not
introduce a logging or metrics platform. Every deployed function entrypoint
generates one UUID request ID, injects it into the internal request context,
preserves it in the response header/body, and emits one JSON event after the
handler returns.

## Event shape

```json
{
  "event": "platform.request",
  "metric": "redemption_total",
  "requestId": "uuid",
  "route": "/v1/redemptions",
  "resultCode": "OK",
  "latencyMs": 12
}
```

Only normalized routes and stable result codes are logged. Optional `userId`
and `appId` fields are accepted only from a trusted server caller; client
headers are never treated as identity. Unknown routes are recorded as
`/unknown`.

## Metrics

The metric label set is bounded to the following names:

- `platform_request_total`
- `session_total`
- `session_exchange_total`
- `entitlement_check_total`
- `redemption_total`
- `payment_webhook_total`
- `admin_operation_total`
- `feedback_total`

The `resultCode` label is the stable API error code or an `HTTP_<status>`
fallback. Response bodies, SQL errors, stack traces, cookies, authorization
headers, passwords, tokens, redemption code material, payment data, and user
content are never logged.

## Nonproduction alert defaults

These values are operational starting points for Local and test dashboards,
not legal retention or production policy. Production alert thresholds must be
approved and configured outside the repository:

| Variable | Local default | Meaning |
| --- | ---: | --- |
| `PLATFORM_ALERT_REQUEST_LATENCY_P95_MS` | `1000` | Request latency alert threshold |
| `PLATFORM_ALERT_ENTITLEMENT_ERROR_RATE` | `0.05` | Entitlement error-rate threshold |
| `PLATFORM_ALERT_WEBHOOK_SIGNATURE_FAILURE_RATE` | `0.10` | Webhook signature-failure threshold |
| `PLATFORM_ALERT_SERVICE_ROLE_ANOMALY_COUNT` | `5` | Unexpected service-role call count |

The current Local implementation emits the bounded events; alert evaluation
belongs to the environment's dashboard/runner and is not a second data store.
