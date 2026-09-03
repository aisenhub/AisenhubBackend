# Legacy V1 Architecture Summary

Historical source: `docs/archive/legacy-v1/AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md`.

## Valuable decisions retained in the new architecture

- modular monolith;
- PostgreSQL as business source of truth;
- private `platform` schema and RLS defense in depth;
- controlled SECURITY DEFINER commands;
- Application / Origin registry;
- Product / ProductVersion / Price separation;
- append-only Entitlement Grants;
- atomic Redemption transaction and hashed codes;
- OrderItem-level Commerce/Refund semantics;
- Admin backend authority, four-role RBAC, MFA and audit;
- contracts/clients as frontend boundary;
- no premature microservices/OpenFGA/Kafka/Redis.

## Decisions superseded

- all products assumed primarily under AisenHub domains;
- Platform Host Cookie Session as multi-product auth foundation;
- Origin-derived Application identity for authenticated product traffic;
- separate session exchange/CSRF model for the Platform API.

The exact original is recoverable using `SOURCE_MANIFEST.md` and Git history.
