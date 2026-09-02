# P8-T001 Commercial Decision Record

Date: 2026-09-02
Status: deferred
Environment scope: Staging and non-production test fixtures only

## Decision

The first release scope does not enable real sales, real payment collection,
or Production cutover. HG-002 is therefore deferred rather than used to block
technical readiness.

No commercial value was invented or frozen. The following remain intentionally
unresolved until a real-sale launch is approved:

- official price, currency, and payment channel;
- future-version and all-site access wording;
- ad-removal promise;
- AI/cloud/third-party cost model;
- redemption-code sales channel;
- partial-refund semantics;
- jurisdiction-specific retention periods.

The existing state-machine and contract tests continue to use non-production
fixtures only. A future real-sale launch must resolve these items together in
HG-002 before creating formal Production products or accepting money.

Architecture Deviations: None.
