# AisenHub Unified Identity Platform Architecture V2

> 状态：**Active Target Architecture — Breaking Rebuild Edition**
>
> 适用仓库：`aisenhub/AisenhubBackend`
>
> 仓库基准：`main` @ `897eee2edb4010e3d049dbb851edaf944c8d0313`（2026-09-03）
>
> 核心前提：当前后端没有真实生产用户、没有需要保留的生产业务数据、没有需要兼容的外部客户端。因此本版本采用 **Breaking Rebuild**，不建设 V1/V2 双轨兼容、不做历史 Session/Membership backfill、不维护旧 Cookie Auth 兼容层。
>
> 文档权威：本文件是 AisenHub Platform 当前唯一总体架构事实来源。`docs/archive/**` 仅供历史追溯，不得作为实现权威。

---

# 1. 一句话定位

AisenHub Platform 是一个供多个彼此独立的软件共用的 **Identity & User Platform**：

```text
Global Identity
+ Application
+ Application Membership
+ OAuth/OIDC Client Binding
+ Platform API
+ Entitlement / Commerce / Admin / Audit
```

各软件可以使用完全不同的域名、用户群体和产品模型；它们共享身份基础设施，但不共享浏览器 Cookie，也不把“存在于全局账号库”解释为“属于所有应用”。

---

# 2. Breaking Rebuild 决策

本项目当前没有兼容负担，因此明确采用以下规则：

1. **不保留旧 Platform Session 兼容层。**
2. **不保留 `Origin -> Application` 作为认证权威。**
3. **不维护 `/v1` 旧语义与 `/v2` 新语义双轨。**
4. **不做旧 Session、旧用户、旧 Membership 的 backfill。**
5. **Local / Staging fixture 可以整体重建。**
6. **旧 Auth API、旧 Cookie、旧 CSRF Session 流程可以直接删除。**
7. **旧测试如果只是在证明旧架构，应删除或重写，而不是为了让测试继续通过而保留旧实现。**
8. **现有 Commerce、Entitlement、Redemption、Admin 安全、Audit、Idempotency、RLS 等已经证明有效的业务不变量继续保留。**
9. 重构完成后再将最终数据库 schema **squash 为干净 baseline migration series**，删除历史迁移噪音。
10. Production 仍然是显式 Human Gate；“没有用户”不等于允许 Agent 未经批准破坏云端 Production 资源。

这次重构的目标不是“迁移到 V2”，而是让 **V2 直接成为项目真正的第一版正式架构**。

---

# 3. API 版本策略

当前代码已经出现 `/v1/*`，但这些接口没有外部消费者，因此它们不是需要兼容的公共版本承诺。

重构后继续使用：

```text
/v1/public/*
/v1/account/*
/v1/app/*
/v1/admin/*
/v1/webhooks/*
```

原因：

```text
Git 历史里出现过 /v1
!=
已经对真实用户发布过 API v1
```

所以不人为制造 `/v2`。

重构期间允许对现有 `/v1` 请求/响应/Auth 语义进行 breaking change。重构完成、正式对外发布后，才开始执行真正的 API 版本兼容政策。

---

# 4. 技术路线

继续采用模块化单体：

- Supabase Auth
- Supabase OAuth 2.1 / OIDC Server
- PostgreSQL
- RLS
- PostgreSQL Functions
- Supabase Edge Functions
- TypeScript / Deno
- React / Vite
- pnpm workspace

继续禁止在没有真实复杂度之前引入：

- 微服务
- Redis
- Kafka
- Kubernetes
- OpenFGA
- Event Sourcing
- CQRS infrastructure
- 第二套 Auth
- 第二套核心数据库

Supabase 是当前实现，不是业务边界。未来可以替换 IdP 或 Backend runtime，但不能要求产品前端理解数据库表结构。

---

# 5. Global Identity

权威身份：

```text
auth.users.id
```

它表示“这个账号是谁”，而不是“这个账号属于哪个产品”。

`platform.profiles` 继续一对一绑定 `auth.users.id`，定义为 **Global Profile**，负责：

- display name
- avatar
- locale
- global account status
- global deletion lifecycle

禁止把产品角色、购买状态或 Membership 塞进 Global Profile。

---

# 6. Application

`platform.platform_apps` 继续作为 Application Registry。

一个 Application 是一个独立的软件/服务，不等于一个域名。

一个 Application 可以拥有：

```text
Web Production Client
Web Staging Client
Desktop Client
Mobile Client
CLI Client
```

建议 `platform_apps` 增加：

```text
registration_policy
membership_policy
default_locale
terms_version
privacy_version
```

第一版注册策略：

```text
open
invite_only
admin_created
closed
```

第一版 Membership 创建策略：

```text
explicit
create_on_first_authorization
create_on_verified_purchase
```

---

# 7. Application Membership

新增核心表：

```text
platform.application_memberships
```

建议字段：

```text
id
application_id
user_id
status
created_source
joined_at
activated_at
suspended_at
suspended_reason
left_at
deleted_at
created_by
created_at
updated_at
```

唯一约束：

```text
unique(application_id, user_id)
```

状态：

```text
pending
active
suspended
left
deleted
```

核心不变量：

```text
Global Identity exists
DOES NOT imply
Application Membership exists
```

例如：

```text
USER-001
  ├── AisenFlow       active
  ├── Writer          active
  └── FinanceTool     no membership
```

FinanceTool 必须把该用户视为“不是本应用用户”。

---

# 8. Membership 与 Entitlement

两者必须永久分离：

```text
Membership = 这个人是不是这个 Application 的用户
Entitlement = 这个用户在该 Application 拥有什么能力/商品权益
```

退款：

```text
Membership remains active
Entitlement may be revoked
```

Membership suspend：

```text
Entitlement history remains
Application access denied
```

Global Identity disable：

```text
All Application access denied
```

---

# 9. OAuth Provider

Supabase Auth 当前承担 Identity Provider / OAuth Provider。

AisenHub 只依赖标准能力：

- OAuth 2.1 Authorization Code + PKCE
- Refresh Token
- OpenID Connect
- JWKS
- `client_id` claim
- public / confidential client
- exact Redirect URI

实现前必须重新核实 Supabase 官方能力，因为 Provider 功能会演进。

官方参考：

- `https://supabase.com/docs/guides/auth/oauth-server`
- `https://supabase.com/docs/guides/auth/oauth-server/getting-started`
- `https://supabase.com/docs/guides/auth/oauth-server/oauth-flows`
- `https://supabase.com/docs/guides/auth/oauth-server/token-security`

OIDC/第三方 JWT 验证必须使用可通过 JWKS 分发的非对称 signing key。

AisenHub 不复制 Provider 内部的：

```text
authorization_codes
refresh_tokens
oauth_grants
```

---

# 10. OAuth Client Binding

新增：

```text
platform.application_oauth_clients
```

最小字段：

```text
id
application_id
provider
external_client_id
client_type
environment
name
status
created_at
updated_at
```

核心约束：

```text
external_client_id -> exactly one application
```

环境：

```text
development
staging
production
```

Client type：

```text
public
confidential
```

为了减少重复配置，第一版 **不建立 `oauth_redirect_uris` 业务表**。Redirect URI 的协议配置由 Supabase OAuth Provider 负责，AisenHub 只在实现/部署检查中验证 exact redirect 配置。

等未来真正需要 Admin 自助管理 OAuth Client 时，再评估是否镜像 Provider 配置。

---

# 11. Origin 的职责

保留 `platform.app_origins`，但重新定义职责：

```text
Origin = browser security / CORS evidence
Origin != authenticated Application identity
```

Authenticated request：

```text
verified access token.client_id
  -> application_oauth_clients
  -> application_id
```

如果请求是浏览器请求并存在 `Origin`：

```text
token-derived application
AND
Origin belongs to same application
```

不一致则拒绝。

Desktop / CLI 等无 Origin 客户端仍可正常工作。

Public anonymous browser API 可以继续通过可信 Origin 推导 Application，但所有敏感写操作不得只靠 Origin。

---

# 12. Session 模型

删除“所有产品共用一个 Platform Cookie Session”的概念。

最终不再把：

```text
platform.platform_sessions
__Host-aisenhub_session
```

作为产品认证基础。

各客户端选择：

## SPA / Local-first Web

```text
Authorization Code + PKCE
-> short-lived Bearer access token
```

Token 首选内存保存；不能把 confidential secret 放到浏览器。

## Web + BFF

```text
Authorization Code + PKCE
-> BFF token exchange
-> application-local Host-only HttpOnly cookie
```

Cookie 归属于产品自己的 host。

## Desktop / Mobile / CLI

```text
Authorization Code + PKCE
-> system browser
-> secure OS token storage
```

AisenHub 可以提供 SDK/BFF helper，但 Platform Backend 不需要保存所有产品的浏览器 Session。

---

# 13. Token Trust Model

Platform API 收到：

```http
Authorization: Bearer <access_token>
```

必须验证：

```text
1. signature / JWKS
2. issuer
3. expiration
4. expected token class / audience policy
5. client_id exists
6. OAuth Client active
7. Application active
8. Global Profile active
9. Application Membership active
10. endpoint authorization
11. Entitlement when endpoint requires it
```

所有失败默认 deny。

不要把动态业务状态全部塞入 JWT 作为唯一权威。Membership、Application status、Entitlement 都可以在 Token 生命周期中变化，因此数据库仍是动态业务权威。

---

# 14. Application Context Kernel

Backend 必须只有一个共享入口：

```text
resolveAuthenticatedApplicationContext()
```

返回：

```text
requestId
userId
profileStatus
clientId
applicationId
applicationSlug
membershipId
membershipStatus
aal
```

所有 authenticated Application handler 都依赖它。

禁止每个 Handler 自行：

- decode JWT
- trust request app slug
- map client
- lookup membership
- 判断 profile status

---

# 15. 正式 API 结构

统一使用新的 `/v1`：

```text
/v1/public/*
/v1/account/*
/v1/app/*
/v1/admin/*
/v1/webhooks/*
```

建议：

```text
GET  /v1/account/me
GET  /v1/account/applications
DELETE /v1/account/applications/:applicationId

GET  /v1/app/session
GET  /v1/app/me
GET  /v1/app/entitlements
GET  /v1/app/access
POST /v1/app/feedback
POST /v1/app/redemptions

GET  /v1/admin/applications/:id/members
POST /v1/admin/applications/:id/members/:userId/suspend
POST /v1/admin/applications/:id/members/:userId/restore
```

App API 不允许客户端用 URL/header 自己选择安全上下文 Application；Application 从 verified `client_id` 推导。

---

# 16. Contracts / SDK

`packages/contracts` 继续是唯一请求/响应/错误合同来源。

建议新增：

```text
identity
application-membership
oauth-client
application-context
account
```

`packages/platform-client` 重新定位为 Bearer-first Platform SDK。

新增：

```text
packages/auth-client
```

只负责 OAuth 协议客户端能力：

- authorize URL
- PKCE
- state
- nonce
- callback validation
- token exchange adapter
- refresh/logout normalization

可选新增：

```text
packages/web-session
```

为需要 BFF 的产品提供 app-local session helper。

---

# 17. Account Center

`apps/account` 成为：

```text
AisenHub Identity & Authorization Center
```

负责：

- Global Identity 登录/资料/MFA
- OAuth authorization UI / consent
- My Applications
- Application Membership lifecycle
- Global account deletion

它是 UI，不是 OAuth 协议权威；authorization code、token、refresh token 由 Supabase Auth 管理。

---

# 18. Admin

`apps/admin` 继续使用 React + Refine Core + Ant Design，并继续只访问 `admin-client -> Platform Admin API`。

Admin 身份：

```text
Global Identity
+ Admin OAuth Client/Application Context
+ platform.admin_members
```

`admin_members` 继续是固定：

```text
owner
admin
support
finance
```

Admin 新增管理视图：

- Application Members
- OAuth Client Bindings
- Registration Policy
- Membership suspend/restore/create

第一版不做通用 Application Operator / Organization RBAC。

---

# 19. Commerce / Entitlement / Redemption

这些成熟领域不重写业务语义，只接入 Application Context。

保留：

- Product / ProductVersion / Price
- Order / OrderItem
- Payment / Refund / Chargeback
- Entitlement Grant append-only history
- Redemption hashed code + atomic redeem
- idempotency
- audit

新增/强化：

- Product/Feature 必须能够明确解析 Application 或 platform scope；
- authenticated Entitlement/Redemption 从 server-resolved Application Context 进入；
- 跨 Application Product/Feature/Grant 组合必须被数据库约束/命令拒绝。

---

# 20. Feedback / Audit

Authenticated Feedback：

```text
application_id = token-derived Application
user_id = token sub
membership_id = resolved Membership
```

Audit 建议显式拥有 nullable：

```text
application_id
```

Global 事件允许 null；Application 事件必须带 application_id。

禁止仅通过 target string 推断应用归属。

---

# 21. Account Deletion

分两种：

## Application-level deletion

```text
terminate/delete membership
+ cleanup/anonymize application-specific data
+ preserve Global Identity
+ preserve legally required commerce/audit facts
```

## Global Identity deletion

```text
all application cleanup
+ global profile lifecycle
+ Supabase Auth identity deletion
+ retention rules
```

删除一个产品账号绝不能误删用户在其他产品的身份。

---

# 22. PostgreSQL Security Boundary

继续：

```text
platform schema = sensitive business facts
controlled query/command functions
RLS = defense in depth
SECURITY DEFINER = audited capability boundary
fixed search_path
explicit revoke/grant
```

`service_role` 不应被当作“允许随便通过 Data API CRUD”的架构许可。

所有 privileged function 自动测试：

- SECURITY DEFINER 期望
- fixed search_path
- public/anon/authenticated execute grants
- service_role grants
- input validation
- transaction rollback

---

# 23. Clean Database Baseline

因为没有生产数据，本次重构不维护历史迁移兼容性。

步骤：

```text
先在现有 migration history 上实现并验证最终模型
        ↓
所有 DB/RLS/Integration/E2E 通过
        ↓
生成干净 baseline migration series
        ↓
从空数据库连续 rebuild 两次
        ↓
删除旧历史迁移
```

Baseline 不建议变成一个 100k 行大文件，而应按稳定领域拆成少量顺序文件，例如：

```text
0001_platform_core
0002_identity_applications_memberships
0003_catalog_entitlements
0004_redemption
0005_commerce
0006_administration_audit
0007_operations
```

最终历史里不再保留旧 `platform_sessions`、旧 session exchange、旧 Origin-auth 权威等已经失效的 schema/functions。

---

# 24. Edge Function 内部结构

当前巨大的 `_shared/platform-api.ts` / `admin-api.ts` 在重构时同步模块化，但仍然是模块化单体。

目标：

```text
supabase/functions/_shared/
  http/
    response.ts
    cors.ts
    request-context.ts
  auth/
    identity-provider.ts
    token-verifier.ts
    application-context.ts
    admin-context.ts
  db/
    read-rpc.ts
    privileged-rpc.ts
  domains/
    identity/
    applications/
    memberships/
    catalog/
    entitlements/
    redemption/
    commerce/
    account-deletion/
  routers/
    public-router.ts
    account-router.ts
    app-router.ts
    admin-router.ts
```

`serviceRoleKey` 必须收敛到 privileged DB gateway。

---

# 25. 测试策略

必须建立：

## Database

- membership lifecycle
- unique app/user
- app/client binding
- cross-app ownership constraints
- privileged function capabilities

## Integration

```text
App A member + App A client -> allowed
App A member + App B client -> membership required
Suspended membership -> denied
Disabled app/client -> denied
Wrong browser Origin + valid token -> denied
No Origin desktop client -> allowed
```

## OAuth E2E

- Authorization Code + PKCE
- state mismatch
- redirect mismatch
- code replay
- login/consent/deny
- refresh/logout

## Cross-domain Browser E2E

至少两个不同 site/origin，证明：

```text
no shared Cookie dependency
```

## Existing Domain Regression

- redemption concurrency
- entitlement revoke/restore
- order fulfillment/refund/chargeback
- Admin RBAC/MFA
- account deletion

---

# 26. CI

保留现有：

```text
pnpm platform:verify
pnpm db:test
pnpm rls:test
pnpm test:contract
pnpm test:integration
pnpm test:security
pnpm boundaries:check
pnpm secrets:check
```

升级：

- PR 必须真正运行关键 Playwright OAuth smoke，而不只是 `--list`；
- Full release E2E 在 release/Staging gate 执行；
- boundary checker 新增“禁止共享父域 Cookie SSO”“禁止 Origin 作为 authenticated app authority”“Provider SDK 只能在 auth adapter”等规则。

---

# 27. 环境策略

Local：允许完全 reset。

Staging：本次重构允许整体 reset/recreate，因为没有真实用户，但必须确认目标确实是 Staging。

Production：即使没有用户，也必须显式批准 destructive reset/deploy。

OAuth client 按环境独立：

```text
*_dev
*_staging
*_prod
```

Production OAuth client 不允许 localhost callback。

---

# 28. Supabase Custom Domain

Supabase Custom Domain **不是正确认证架构的前提**。

独立产品可以运行在：

```text
aisenflow.com
tool-b.io
product-c.ai
```

并通过标准 OAuth redirect/token flow 使用 `<project-ref>.supabase.co` Identity Provider。

未来购买 Custom Domain 只用于 branding / issuer / enterprise experience，不用于修补跨域共享 Cookie。

---

# 29. Documentation Policy

`docs/` 只保留四类内容：

1. 当前架构；
2. 当前实施计划/执行规则；
3. 必要运行/安全规则；
4. 已被替代的设计/计划归档。

禁止长期保留过程记录：

```text
PROGRESS.md
TASK_LEDGER.md
checkpoints/
reports/
临时 blocker 结案文件
一次性 staging/production baseline
一次性 env fill template
```

执行历史由以下系统承担：

```text
Git commits
GitHub history
CI runs/artifacts
必要的 issue/PR
```

Archive 只保存“未来可能解释为什么这样设计”的历史设计，而不是保存所有执行日志。

---

# 30. Final Invariants

```text
auth.users = Global Identity

Global Identity != Application Membership

Application != domain

client_id -> exactly one Application

Origin != authenticated Application identity

independent Applications do not share cookies

active identity
AND active application
AND active client
AND active membership
= minimum app access

Membership != Entitlement

PostgreSQL = business source of truth

Platform Backend = business authority

OAuth/OIDC + Platform API = stable integration boundary

no legacy auth compatibility code after rebuild
```

---

# 31. Target Repository Shape

```text
apps/
  account/
  admin/

packages/
  contracts/
  auth-client/
  platform-client/
  admin-client/
  web-session/        # only if BFF consumer exists
  design-system/
  config/

supabase/
  functions/
    _shared/
      http/
      auth/
      db/
      domains/
      routers/
    platform-api/
    platform-admin/
    platform-public/
    payment-webhook/
    account-deletion-worker/
    retention-cleanup/
  migrations/         # clean baseline series
  tests/
  types/

docs/
  README.md
  AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md
  ARCHITECTURE_CHANGELOG.md
  implementation/
    README.md
    MASTER_PLAN.md
    AGENT_EXECUTION_RULES.md
    HUMAN_GATES.md
    DOCS_CLEANUP_PLAN.md
    phases/
  archive/
    README.md
    legacy-v1/
    superseded-v2-migration/
```

---

# 32. Adoption Order

```text
R0 Documentation / Architecture Reset
R1 Identity + Membership + OAuth Client Foundation
R2 OAuth / Auth Kernel / API Breaking Rebuild
R3 Account + SDK + Admin + Business-domain Integration
R4 Migration Squash + Code Cleanup + Full Security Gate
R5 Fresh Staging + Production Release
```

没有 Compatibility Phase、Backfill Phase、Pilot Migration Phase、Legacy Retirement Phase。

因为本项目当前没有任何需要保护的真实消费者。
