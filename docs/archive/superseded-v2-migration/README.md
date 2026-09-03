# Superseded Migration-oriented V2

Status: superseded by the Breaking Rebuild Edition.

The previous V2 correctly introduced:

```text
Global Identity
Application Membership
OAuth/OIDC Client
Application-local Session
```

But it assumed a conservative live-system migration:

```text
/v1 legacy compatibility
+ /v2 OAuth
+ membership backfill
+ pilot migration
+ one-by-one existing-app migration
+ legacy-session retirement
```

That rollout is unnecessary because the project currently has no real users/data/external consumers. The active architecture keeps the identity model and removes the compatibility machinery.
