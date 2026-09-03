# AisenHub Unified Identity Platform Architecture V2

> 状态：**Active / Authoritative**
>
> 目标：将当前 AisenHub Platform 从“同一父域下多个工具共用 Platform Cookie Session”升级为“可服务任意独立软件、任意域名、不同用户群体的统一身份与用户管理平台”。
>
> 适用仓库：`aisenhub/AisenhubBackend`
>
> 基准分支：`main`
>
> 架构日期：2026-09-03
>
> 权威说明：本文件现已正式采纳，替代旧版 `docs/archive/legacy-v1/AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md`，成为身份、Application、Session、OAuth/OIDC、Membership 与跨产品接入模型的总体架构事实来源。旧版实施记录仅供历史追溯，不再作为新的实现依据。

---

# 1. 决策摘要

AisenHub Platform 的长期目标不是让多个网站共享同一个 Cookie，而是成为所有 AisenHub 软件以及未来独立品牌软件共用的 **Identity & User Platform**。

核心模型：

```text
Global Identity
    +
Application Membership
    +
OAuth/OIDC Client
    +
Application-local Session
    +
Platform API
```

关键决策：

1. `auth.users` 只表达 **Global Identity**：这个自然人/账号是谁。
2. `platform.profiles` 继续作为 Global Identity 的平台级资料与生命周期记录。
3. `platform.platform_apps` 继续作为 Application Registry，但 Application 不再假设属于 `*.aisenhub.com`。
4. 新增 `application_memberships`，表达“某个 Global Identity 是否属于某个 Application”。
5. 用户存在于 `auth.users` **不代表**用户自动属于所有软件。
6. 每个独立软件拥有自己的 OAuth/OIDC Client、Redirect URI、注册策略、Membership 集合和 Session。
7. 不再使用跨域共享 Cookie 作为多软件登录基础。
8. Web 应用优先采用 **Authorization Code + PKCE + BFF/App-local HttpOnly Cookie**。
9. SPA、Desktop、Mobile、CLI 等 public client 采用 Authorization Code + PKCE，并使用短生命周期 Bearer Token。
10. AisenHub Platform API 对认证请求的 Application 身份以经过验证的 `client_id` / OAuth Client Binding 为权威，不再以浏览器 `Origin` 为应用身份权威。
11. `Origin` 继续保留，但职责调整为 CORS、CSRF、浏览器来源校验和环境配置，不再单独证明调用方 Application 身份。
12. Application Membership 与 Entitlement 必须严格分离：
    - Membership：是不是这个软件的用户；
    - Entitlement：这个用户在这个软件中拥有了什么功能/商品权益。
13. Admin Membership 继续独立于普通 Application Membership。
14. Commerce、Entitlement、Redemption、Audit、Idempotency 等现有领域模型继续保留，不因身份架构升级而重写。
15. PostgreSQL 继续是唯一业务事实存储，Platform Backend 继续是唯一业务权威。
16. 继续采用模块化单体，不因为支持多个独立软件而引入微服务、Kafka、Redis、Kubernetes 或第二套核心数据库。
17. Supabase Auth 是当前 Identity Provider / OAuth Provider 实现，不是不可替换的业务边界。
18. AisenHub 对外承诺的是 OAuth/OIDC + Platform API Contract，而不是 Supabase 专有浏览器 Session 行为。

---

# 2. 当前仓库基线

本架构基于当前仓库已经存在并验证的以下能力。

## 2.1 已有 Identity

当前：

```text
auth.users
    │
    └── platform.profiles
```

`platform.profiles` 已经正确表达：

- 一对一绑定 `auth.users.id`
- `active`
- `disabled`
- `deletion_pending`
- `deleted`
- display name
- avatar
- locale

这一层应继续保留，并正式定义为 **Global Identity Profile**。

对应当前实现：

```text
supabase/migrations/20260901013710_profiles_schema.sql
```

---

## 2.2 已有 Application Registry

当前：

```text
platform.platform_apps
platform.app_origins
```

已经具备：

- 稳定 `app.slug`
- Application status
- Application metadata
- 环境区分
- 精确 Origin allow-list
- 不允许通配 Origin
- 引用后 slug 不可变
- Origin identity 不可原地修改

这套模型可以继续使用。

需要改变的是：

```text
旧语义：
Origin -> Application Identity

新语义：
OAuth client_id -> Application Identity
Origin -> Browser Security Boundary
```

对应当前实现：

```text
supabase/migrations/20260901015042_applications_origins_schema.sql
```

---

## 2.3 已有 Platform Session

当前：

```text
platform.platform_sessions
```

保存：

- user_id
- token_hash
- csrf_hash
- expires_at
- revoked_at
- idempotency linkage
- ip_hash

原设计适用于：

```text
account.aisenhub.com
admin.aisenhub.com
api.aisenhub.com
*.aisenhub.com
```

这种同一站点体系下的 Platform API Cookie Session。

但是未来 Application 可能是：

```text
aisenflow.com
some-video-tool.io
another-ai-app.ai
desktop app
mobile app
CLI
```

因此 `platform_sessions` 不能继续承担所有软件统一 Session 的职责。

V2 中它应逐步降级为：

- AisenHub 自身 Account/Admin 的内部 Session；
- 或过渡期兼容 Session；
- 最终不再作为所有第三方/独立 Application 的统一浏览器 Cookie Session。

对应当前实现：

```text
supabase/migrations/20260901020336_sessions_admin_memberships.sql
```

---

## 2.4 已有安全与业务一致性能力

以下能力继续保持：

```text
PostgreSQL transaction
RLS
SECURITY DEFINER
fixed search_path
service-role-only privileged commands
idempotency_records
audit_logs
row locking
contract validation
Admin RBAC
MFA / AAL2
Edge Function HTTP boundary
```

已经成熟的 Commerce / Redemption / Entitlement 事务模型不因为 V2 Identity 改造而重写。

---

# 3. V2 平台定位

AisenHub Platform 不再定义为：

> 多个 AisenHub 子域产品共用的后端。

重新定义为：

> **多个相互独立的软件、网站、桌面应用、移动应用、CLI 与未来服务共用的统一 Identity、User Membership、Entitlement、Commerce、Admin 与 Audit Platform。**

Application 可以：

- 使用任意域名；
- 面向完全不同的用户群体；
- 使用不同注册策略；
- 使用不同登录 UI；
- 使用独立 Session；
- 有不同产品/权益；
- 有不同管理员；
- 有不同生命周期；
- 独立部署；
- 独立下线。

它们共享的是平台能力，不共享浏览器安全边界。

---

# 4. 核心术语

## 4.1 Global Identity

一个真实账号在 AisenHub Identity Platform 中的唯一身份。

权威：

```text
auth.users.id
```

Global Identity 可以同时属于 0、1 或多个 Application。

Global Identity 负责：

- 登录凭据
- 邮箱/手机号
- MFA
- 身份 Provider
- 账号级封禁
- 全局账号删除
- 全局安全事件

Global Identity **不表达产品角色或产品权益**。

---

## 4.2 Global Profile

平台级用户资料。

权威：

```text
platform.profiles
```

负责：

- display name
- avatar
- locale
- global account status
- global deletion lifecycle

不负责：

- 某个 Application 是否允许登录
- 某个 Application 的角色
- 商品权益
- 产品订阅

---

## 4.3 Application

一个独立的软件或服务。

例如：

```text
AisenFlow
AisenWriter
AisenImage
Desktop Tool X
Customer Portal Y
```

权威：

```text
platform.platform_apps
```

Application 与域名不是一一绑定。

一个 Application 可以有：

- Production Web Client
- Staging Web Client
- Desktop Client
- Mobile Client
- CLI Client
- Internal Service Client

---

## 4.4 Application Membership

表示：

> 这个 Global Identity 是不是这个 Application 的用户。

这是 V2 最关键的新领域对象。

```text
Global Identity
      │
      ├── Membership -> AisenFlow
      ├── Membership -> AisenWriter
      └── no Membership -> Tool C
```

用户存在于 `auth.users` 但没有某 Application Membership 时：

```text
不能被视为该 Application 用户。
```

---

## 4.5 OAuth Client

Application 的一个协议客户端身份。

例如：

```text
aisenflow_web
aisenflow_desktop
aisenflow_staging
writer_web
writer_mobile
```

OAuth Client 用于：

- `client_id`
- redirect URI
- client type
- environment
- token policy
- Application binding

它不是 Global Identity，也不是 Membership。

---

## 4.6 Application Session

用户在某一个具体软件里的登录状态。

核心原则：

```text
Session belongs to Application.
Cookie belongs to Application host.
Identity belongs to AisenHub.
```

Application Session 不跨独立域名共享。

---

## 4.7 Entitlement

表示：

> 用户拥有了什么产品、版本、Feature 或商业权益。

Membership 与 Entitlement 独立。

```text
Membership = user belongs to app
Entitlement = user owns capabilities in app
```

Membership 被暂停时，即使 Entitlement 仍存在，也必须阻止应用访问。

Entitlement 被撤销时，不自动删除 Membership。

---

# 5. 总体系统架构

```text
                              ┌─────────────────────────────┐
                              │     AisenHub Identity       │
                              │      Supabase Auth          │
                              │                             │
                              │ Global Identity / MFA       │
                              │ OAuth 2.1 / OIDC            │
                              └──────────────┬──────────────┘
                                             │
                                    OAuth/OIDC Protocol
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │                        │                        │
                    ▼                        ▼                        ▼
          ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
          │   AisenFlow     │      │   Software B    │      │   Software C    │
          │ aisenflow.com   │      │ tool-b.io       │      │ product-c.ai    │
          │                 │      │                 │      │                 │
          │ local Session   │      │ local Session   │      │ local Session   │
          └────────┬────────┘      └────────┬────────┘      └────────┬────────┘
                   │                        │                        │
                   │ Bearer / BFF API       │ Bearer / BFF API       │
                   └────────────────────────┼────────────────────────┘
                                             │
                                             ▼
                              ┌─────────────────────────────┐
                              │      Platform API           │
                              │                             │
                              │ Token validation            │
                              │ client_id -> app_id         │
                              │ membership enforcement      │
                              │ Entitlement / Commerce      │
                              │ Feedback / User API         │
                              └──────────────┬──────────────┘
                                             │
                                             ▼
                              ┌─────────────────────────────┐
                              │ PostgreSQL                  │
                              │                             │
                              │ profiles                    │
                              │ applications                │
                              │ memberships                 │
                              │ oauth client bindings       │
                              │ entitlements                │
                              │ commerce                    │
                              │ audit                       │
                              └─────────────────────────────┘
```

---

# 6. Identity Provider 边界

当前继续采用 Supabase Auth。

但是业务架构必须定义：

```text
Identity Provider != AisenHub Business Authority
```

Supabase Auth 负责：

- 用户凭据
- 登录
- MFA
- OAuth/OIDC protocol
- Authorization Code
- PKCE
- Refresh Token
- JWT signing
- UserInfo / discovery

AisenHub Platform 负责：

- Application Registry
- OAuth Client 与 Application 的业务绑定
- Membership
- Registration Policy
- Application suspension
- Business authorization
- Entitlement
- Commerce
- Audit
- Deletion orchestration

因此未来允许：

```text
Supabase Auth
     ↓
Other OIDC Provider / Self-hosted IdP
```

只要保持：

- `sub` / Global Identity mapping
- `client_id`
- OIDC/OAuth contract
- Platform API contract

就不应要求产品前端重写业务逻辑。

---

# 7. OAuth / OIDC 决策

截至 2026-09-03，Supabase Auth 已提供 OAuth 2.1 / OpenID Connect Server 能力，包括 Authorization Code + PKCE、Refresh Token、OIDC discovery、UserInfo 和 `client_id` claim。

当前该能力仍属于 Supabase Beta，因此：

1. AisenHub 可以采用它作为第一版实现；
2. AisenHub 不应把业务数据库模型直接绑定到 Supabase OAuth 内部表；
3. AisenHub 应维护自己的 Application/OAuth Client Binding；
4. Platform SDK 只依赖标准 OAuth/OIDC 行为；
5. 若 Supabase OAuth Server 的产品形态发生变化，可迁移 Provider，而不改变 Membership / Entitlement / Commerce 模型。

OIDC 使用时应采用非对称 JWT signing key，以便客户端通过 JWKS 验证 Token。

---

# 8. Application 数据模型

继续使用：

```text
platform.platform_apps
```

建议 V2 增加/明确以下字段：

```text
registration_policy
identity_policy
membership_policy
default_locale
terms_version
privacy_version
```

建议语义：

```text
registration_policy:
- open
- invite_only
- admin_created
- closed

identity_policy:
- global_identity
- future_external_federation

membership_policy:
- explicit
- create_on_first_authorization
- create_on_verified_purchase
```

第一版建议：

```text
identity_policy = global_identity
```

不提前实现外部企业 IdP 多租户体系。

---

# 9. Application Membership 数据模型

新增：

```sql
platform.application_memberships
```

目标结构：

```text
id                    uuid PK
application_id        uuid FK -> platform_apps.id
user_id               uuid FK -> auth.users.id
status                text
joined_at             timestamptz
activated_at          timestamptz
suspended_at          timestamptz
suspended_reason      text
left_at                timestamptz
created_source        text
created_by            uuid nullable
created_at             timestamptz
updated_at             timestamptz
```

唯一约束：

```text
unique(application_id, user_id)
```

建议状态：

```text
pending
active
suspended
left
deleted
```

状态语义：

### pending

Membership 已创建，但尚未满足激活条件。

### active

正常 Application 用户。

### suspended

Application 层暂停。

这不会自动禁用 Global Identity，也不撤销其他 Application 的 Membership。

### left

用户主动退出某个 Application。

全局 Identity 继续存在。

### deleted

Application Membership 已完成应用级删除/去标识化流程。

---

# 10. Membership 创建规则

禁止：

```text
new auth.users
-> automatically create membership for every application
```

正确模型：

```text
Global Identity creation
        │
        └── only profile is created

Application registration / authorization
        │
        └── create membership for that application only
```

例如：

```text
USER-001
  ├── AisenFlow: active
  ├── Writer: active
  └── Finance: no membership
```

Finance API 必须把 USER-001 当作非 Finance 用户。

---

# 11. Membership 与注册

建议支持三个注册入口。

## 11.1 Open Registration

```text
Application.registration_policy = open
```

流程：

```text
Authorize
-> authenticate Global Identity
-> membership absent
-> create active membership
-> issue authorization
```

---

## 11.2 Invite Only

```text
registration_policy = invite_only
```

流程：

```text
Authorize
-> Global Identity authenticated
-> invitation exists
-> activate membership
```

无邀请：

```text
APPLICATION_MEMBERSHIP_REQUIRED
```

---

## 11.3 Admin Created

企业内部工具或后台产品：

```text
registration_policy = admin_created
```

只有 Admin Command 可以建立 Membership。

---

# 12. OAuth Client Registry

建议新增：

```text
platform.application_oauth_clients
```

目标字段：

```text
id
application_id
provider
external_client_id
client_type
environment
name
status
token_policy
created_at
updated_at
```

其中：

```text
provider = supabase
```

第一版 `client_type`：

```text
public
confidential
```

环境：

```text
development
staging
production
```

唯一业务绑定：

```text
external_client_id -> exactly one Application
```

禁止一个 `client_id` 同时代表多个 Application。

---

# 13. Redirect URI Registry

建议新增：

```text
platform.oauth_redirect_uris
```

字段：

```text
id
oauth_client_id
redirect_uri
environment
is_active
created_at
```

要求：

- exact URI match；
- 不允许 wildcard；
- HTTPS 为 Production 默认要求；
- loopback 只用于 Local/Desktop；
- custom scheme 只用于明确登记的 native client；
- Redirect URI 变更必须 Audit。

Supabase/OAuth Provider 中的实际 Client Configuration 与 AisenHub Registry 必须有自动 drift check。

AisenHub Registry 是业务期望配置。

Provider Configuration 是协议执行配置。

两者不一致时：

```text
fail closed
```

---

# 14. Origin 的新职责

当前系统使用：

```text
Origin -> resolve_app_origin -> app_slug
```

V2 中应修改为：

## 14.1 认证 API

Application Identity 权威：

```text
validated OAuth token.client_id
     -> application_oauth_clients
     -> application_id
```

Origin 只能做额外约束：

```text
token-derived application
        +
browser Origin belongs to same application
```

两者不一致：

```text
APP_ORIGIN_MISMATCH
```

---

## 14.2 Public API

没有用户 Token 的公开浏览器请求仍可通过：

```text
Origin
-> app_origins
-> application
```

解析 Application。

但是所有安全敏感写操作不得只靠 Origin 确认 Application。

---

## 14.3 Non-browser Client

Desktop / CLI / Server Client 可能没有浏览器 Origin。

因此：

```text
Origin cannot remain core Application identity primitive.
```

---

# 15. Session 架构

V2 禁止设计：

```text
one shared browser cookie
-> all independent software
```

采用：

```text
Global Identity shared
Application Session isolated
```

---

# 16. Web Application — 推荐模式

对于具有 Server/BFF 能力的 Web Application：

```text
Browser
  │
  │ GET /login
  ▼
Application BFF
  │
  │ authorization redirect + PKCE/state
  ▼
AisenHub/Supabase Authorization
  │
  │ user authenticates
  ▼
Application callback
  │
  │ exchange code
  ▼
Application BFF
  │
  │ create app-local session
  ▼
Set-Cookie:
__Host-<app>_session=...
HttpOnly
Secure
SameSite=Lax
Path=/
```

Cookie 只属于：

```text
that-application.com
```

不需要 AisenHub/Supabase 与该域名共享 Cookie。

---

# 17. SPA / Local-first Web Client

纯静态 SPA 没有 BFF 时，可作为 public OAuth Client：

```text
Authorization Code + PKCE
```

要求：

- access token 尽量只放内存；
- 不把长期高价值 token 放到 localStorage 作为首选设计；
- access token 必须短生命周期；
- refresh 策略必须明确；
- CSP 严格；
- 禁止在前端出现 confidential client secret；
- 涉及高风险业务时优先增加最小 BFF。

长期推荐：

```text
Production Web App -> tiny BFF/session adapter
```

即使产品本身是前端工具，也可以只增加一个非常薄的 Session/BFF 层，而不建设独立业务后端。

---

# 18. Desktop / Mobile / CLI

使用 public OAuth Client：

```text
Authorization Code + PKCE
```

Desktop：

- system browser authentication；
- loopback redirect 或登记的 custom URI scheme；
- token 放 OS secure storage。

Mobile：

- system browser / platform auth session；
- secure keychain/keystore。

CLI：

- 第一版可使用浏览器 Authorization Code + PKCE；
- 不在 V2 第一阶段自行发明长期静态用户 API Key；
- 后续出现 Agent/API automation 需求时再设计 scoped credentials。

---

# 19. Token Trust Model

Platform API 收到：

```http
Authorization: Bearer <access_token>
```

必须依次验证：

```text
1. signature
2. issuer
3. expiration
4. audience / expected token class
5. client_id exists
6. client_id active
7. client_id -> application active
8. global profile active
9. application membership active
10. endpoint-specific authorization
```

任何一步失败：

```text
fail closed
```

---

# 20. Application Context

认证请求的 Application Context：

```text
OAuth access token
       │
       └── client_id
               │
               ▼
application_oauth_clients
               │
               ▼
application_id
```

这是 V2 唯一可信 Application Context 来源。

`X-AisenHub-App` 可以继续作为：

- diagnostics
- SDK declaration
- observability label

但必须满足：

```text
X-AisenHub-App == token-derived app.slug
```

否则拒绝。

---

# 21. Membership Enforcement

建议统一 Backend Kernel：

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
authSessionId
```

所有 Application-scoped API 共用这一层。

禁止每个 Handler 自行实现：

```text
JWT decode
client mapping
membership lookup
status validation
```

---

# 22. Access Decision

访问某产品能力必须同时满足：

```text
Global Identity Active
        AND
Application Active
        AND
OAuth Client Active
        AND
Membership Active
        AND
Entitlement/Feature condition (when required)
```

写成逻辑：

```text
Identity
   ∩ Application
   ∩ Membership
   ∩ Authorization
   ∩ Entitlement
```

任何一个不是允许状态：

```text
deny
```

---

# 23. Membership 与 Entitlement

这是 V2 必须长期保持的边界。

错误：

```text
paid = application user
```

正确：

```text
Membership:
用户是不是这个 Application 的用户

Entitlement:
用户拥有什么功能
```

例：

```text
AisenFlow Membership = active

Entitlements:
- flow.basic = true
- flow.ai_monthly_tokens = 100000
```

退款后：

```text
Membership = active
Entitlement = revoked
```

用户仍然可以登录，只是回到免费层或失去付费能力。

---

# 24. Membership 与 Commerce

购买某 Application 产品时：

```text
Order
-> OrderItem
-> ProductVersion
-> Entitlement Grant
```

是否自动创建 Membership 由 Application Policy 决定。

建议默认：

```text
购买者已有 Global Identity
+
购买目标明确属于 Application
+
membership_policy = create_on_verified_purchase
```

则支付成功事务可以确保 Membership 存在。

但是：

```text
Commerce transaction must not silently create membership
unless policy explicitly allows it.
```

---

# 25. Admin Membership

现有：

```text
platform.admin_members
```

继续保留。

Admin Membership 表示：

```text
这个 Global Identity 是否可以管理 AisenHub Platform。
```

它不是：

```text
Application Membership
```

也不是：

```text
某个产品购买权限
```

所以继续保持：

```text
Global Identity
   ├── Admin Membership
   └── Application Membership(s)
```

完全独立。

---

# 26. Application Admin / Product Operator

第一版不要把现有 Platform Admin RBAC 泛化为复杂 SaaS Organization RBAC。

如果未来某个 Application 需要自己的运营人员：

可以新增：

```text
application_operator_memberships
```

或在出现明确业务需求后设计 Application-scoped roles。

不要预先引入 OpenFGA。

当前 `owner/admin/support/finance` 继续只服务 AisenHub Platform Admin。

---

# 27. Account Center

`apps/account` 的长期职责调整为：

```text
AisenHub Identity & Account Center
```

功能：

## Global Identity

- profile
- email
- password
- MFA
- linked identities
- security
- global account deletion

## My Applications

展示：

```text
Application
Membership Status
Joined At
Last Authorization
App-specific deletion status
```

例如：

```text
AisenFlow       active
AisenWriter     active
FinanceTool     not joined
```

Account Center 不应把“Global Identity 存在”显示成“已注册所有应用”。

---

# 28. Application-level Account Deletion

必须拆成两种删除。

## 28.1 Leave/Delete One Application

目标：

```text
remove/deactivate application membership
+
delete/anonymize app-specific user data
+
preserve global identity
+
preserve legally required commerce/audit facts
```

用户仍可使用其他 Application。

---

## 28.2 Delete Global Identity

目标：

```text
all memberships
+
global profile
+
auth identity
+
app-specific deletion orchestration
+
legal retention rules
```

这才进入现有 Global Account Deletion Worker 的演进方向。

V2 必须避免：

```text
删除一个软件账号
-> 删除用户所有软件身份
```

---

# 29. API 架构

继续使用：

```text
Edge Function
-> Platform Router
-> Domain Handler
-> PostgreSQL Command / Projection
```

但认证入口需要新增 V2 Application Context Kernel。

建议：

```text
/v2/account/*
/v2/app/*
/v2/admin/*
```

示例：

```text
GET  /v2/account/me
GET  /v2/account/applications

GET  /v2/app/session
GET  /v2/app/me
POST /v2/app/membership
DELETE /v2/app/membership

GET  /v2/app/entitlements
POST /v2/app/feedback

GET  /v2/admin/applications/:id/members
POST /v2/admin/applications/:id/members/:userId/suspend
POST /v2/admin/applications/:id/members/:userId/restore
```

Application API 不要求客户端在 URL 中提供 app slug 作为安全权威。

Application 由 Token Context 推导。

---

# 30. API Error Contract

新增建议错误码：

```text
OAUTH_CLIENT_UNKNOWN
OAUTH_CLIENT_DISABLED
APPLICATION_DISABLED
APPLICATION_MEMBERSHIP_REQUIRED
APPLICATION_MEMBERSHIP_PENDING
APPLICATION_MEMBERSHIP_SUSPENDED
APPLICATION_MEMBERSHIP_DELETED
APP_CONTEXT_MISMATCH
REDIRECT_URI_NOT_ALLOWED
AUTHORIZATION_DENIED
TOKEN_APPLICATION_MISMATCH
```

继续保持：

```text
{
  "error": {
    "code": "...",
    "message": "...",
    "requestId": "..."
  }
}
```

---

# 31. Contracts

`packages/contracts` 继续作为稳定边界。

新增模块建议：

```text
identity.ts
application-membership.ts
oauth-client.ts
authorization.ts
application-session.ts
account.ts
```

Contract 不暴露：

- Supabase internal table
- GoTrue internal schema
- provider-specific refresh token storage
- Service Role
- PostgreSQL table layout

---

# 32. Platform Client

`packages/platform-client` V2 定位：

```text
AisenHub Platform API SDK
```

职责：

- Bearer Token transport
- request ID
- contract validation
- app session/profile/membership API
- entitlements
- feedback
- standard Platform errors

不负责：

- 直接调用 Supabase Data API
- 直接操作数据库
- 写 Service Role
- 决定 Membership 权限

---

# 33. Auth Client / SDK

建议新增独立：

```text
packages/auth-client
```

或在明确边界后由 `platform-client/auth` 承担。

职责：

- Authorization URL generation
- PKCE
- state
- nonce
- callback validation
- token exchange adapter
- logout/revoke
- OAuth error normalization

如果直接依赖 Supabase OAuth API：

必须封装在 adapter 内。

产品代码不应散落：

```text
<project>.supabase.co/auth/v1/...
```

---

# 34. BFF Adapter

为未来大量独立 Web Tool，建议提供：

```text
packages/web-session
```

或模板：

```text
AisenHub Web Auth Adapter
```

目标让每个工具只需要实现：

```text
/login
/auth/callback
/logout
/api/session
```

并自动得到：

- PKCE
- state
- secure cookie
- refresh
- logout
- CSRF policy
- Platform API token forwarding

这样每个新软件不需要重新实现认证协议。

---

# 35. Supabase Edge Function 模块化

当前 `_shared/platform-api.ts` 与 `_shared/admin-api.ts` 已承担大量职责。

V2 升级时建议同步拆分为内部模块，而不是拆微服务。

目标：

```text
supabase/functions/_shared/

  http/
    response.ts
    cors.ts
    request-context.ts

  auth/
    identity-provider.ts
    bearer-token.ts
    oauth-client-context.ts
    application-context.ts
    admin-context.ts

  db/
    public-rpc.ts
    privileged-rpc.ts

  domains/
    identity/
    applications/
    memberships/
    entitlements/
    redemption/
    commerce/
    account-deletion/

  routers/
    platform-router.ts
    account-router.ts
    admin-router.ts
```

部署仍然可以保持少量 Edge Function entrypoints。

---

# 36. PostgreSQL Schema 边界

继续保持：

```text
platform schema
```

作为敏感业务事实存储。

建议新增：

```text
platform.application_memberships
platform.application_oauth_clients
platform.oauth_redirect_uris
platform.application_authorization_events   (可后置)
```

不建议直接复制 OAuth Provider 的内部：

```text
authorization_codes
refresh_tokens
oauth_grants
```

除非 AisenHub 自己成为协议实现者。

当前第一版由 Supabase Auth 管理协议层 Token/Grant。

---

# 37. RLS 与 Capability Boundary

继续采用：

```text
private tables
+
controlled projections
+
controlled commands
+
RLS defense in depth
```

Membership 核心表：

```text
authenticated
anon
service_role
```

不应因为“service_role”存在就自动获得任意 Data API CRUD。

继续使用受控 `SECURITY DEFINER` 函数和固定 `search_path`。

---

# 38. App-scoped Query

所有返回 Application 用户数据的 Query 必须强制带服务端解析后的：

```text
application_id
```

禁止：

```text
SELECT all global users
-> frontend filter by application
```

正确：

```text
Backend Context
-> application_id
-> membership scoped query
```

Admin 的 Application User List：

```text
application_memberships
JOIN profiles
WHERE application_id = resolved/authorized target
```

---

# 39. App-scoped Write

任何应用级写操作必须绑定：

```text
user_id
application_id
membership_id
request_id
```

至少在事务上下文中可追踪。

典型 Audit：

```text
actor_type = user
actor_id = global user id
application_id = target app
action = ...
target_type = ...
target_id = ...
request_id = ...
```

建议逐步给 `audit_logs` 增加显式 `application_id`，避免仅靠 target 推断所属产品。

---

# 40. Feedback

现有 Feedback 应明确 Application scope。

未来：

```text
feedback.application_id
feedback.user_id
feedback.membership_id nullable
```

Public/anonymous feedback 如果允许：

Application 可从：

```text
trusted Origin
```

解析。

Authenticated feedback：

Application 必须从：

```text
OAuth client_id
```

解析。

---

# 41. Entitlement Scope

Feature / Product / ProductVersion 模型继续保留。

建议确保所有可被 Application 消费的 Feature 最终可明确解析所属 Application 或 Global Platform scope。

例如：

```text
feature.scope_type:
- application
- platform

feature.application_id:
nullable for platform scope
```

不要仅依赖字符串前缀决定安全边界。

---

# 42. Global Entitlement

未来确实需要：

```text
All Apps Access
```

这类权益时，可以保留 Platform-level Feature。

但：

```text
Global Entitlement
!= Membership
```

拥有全站权益的用户访问一个新 Application 时，仍应根据该 Application Membership Policy 创建/激活 Membership。

---

# 43. Commerce

Commerce 继续是 Platform 能力。

订单归属于 Global Identity。

OrderItem 关联 ProductVersion。

Product/Feature 最终映射 Application。

因此可以支持：

```text
一个 Identity
-> AisenFlow order
-> Writer order
-> Bundle order
```

而各 App Membership 仍彼此隔离。

---

# 44. Payment Webhook

现有设计继续保持：

```text
Edge Function:
raw body
signature verification
provider normalization

PostgreSQL:
event uniqueness
locking
state machine
fulfillment
audit
```

OAuth/Membership 改造不应把支付业务逻辑搬到前端或 Auth Provider。

---

# 45. Admin

Admin 仍只能使用：

```text
/v1/admin/*
或未来 /v2/admin/*
```

Admin 不直接访问：

- Supabase Data API
- auth.users table
- application_memberships table
- provider OAuth internal tables

所有 Admin User Management 都通过 Backend Commands。

新增能力：

```text
Applications
  -> Members
  -> OAuth Clients
  -> Redirect URIs
  -> Registration Policy
```

---

# 46. Admin User 360

Global User 360：

```text
Identity
Profile
Security status
Admin membership
Application memberships
Entitlements
Orders
Payments
Redemptions
Deletion state
Audit
```

Application User 360：

```text
Application
Membership
App-specific Entitlements
App-specific Orders
App-specific Feedback
App-specific Audit
```

这两个视图必须区分。

---

# 47. Security Principles

V2 强制：

1. 不共享独立域名 Cookie。
2. Production Cookie 使用 Host-only / `__Host-`。
3. Web OAuth 使用 Authorization Code + PKCE。
4. 每个 OAuth authorization request 使用 `state`。
5. OIDC 使用 `nonce`。
6. Redirect URI exact match。
7. Confidential secret 只存在 Server/Secret Manager。
8. Public Client 不允许 secret。
9. Access Token 短生命周期。
10. Refresh Token rotation/revocation 由 Provider 策略控制。
11. Platform API 验证 `client_id`。
12. `client_id` 必须映射 Active Application。
13. 每次 App API 请求验证 Membership。
14. Origin 不能单独证明身份。
15. User supplied app slug 不能覆盖 Token app identity。
16. Service Role 永不进入浏览器。
17. OAuth Provider errors 不直接泄露内部敏感详情。
18. Membership status change 必须 Audit。
19. OAuth Client / Redirect URI change 必须 Audit。
20. Application suspension 应立即阻断 Token 对 Platform API 的业务访问。

---

# 48. Token Claims

业务最低可信 claims：

```text
sub
client_id
aal
exp
iss
```

不要把所有业务状态塞进 JWT。

尤其不要把：

```text
membership_status
all entitlements
all roles
```

长期缓存到 Access Token 作为唯一权威。

原因：

- Membership 可被即时 suspend；
- Entitlement 可退款/撤销；
- Application 可停用；
- 权限可能变化。

因此 Platform API 应通过数据库快速验证关键动态状态。

允许通过 Custom Access Token Hook 添加：

```text
app_id hint
app_slug hint
```

但只能作为优化/声明。

数据库 Binding 仍是业务权威。

---

# 49. Revocation

必须支持四个层级。

## Global Identity Disable

```text
deny all applications
```

## Application Suspend

```text
deny one application only
```

## OAuth Client Disable

```text
deny one client/environment
```

## Membership Suspend

```text
deny one user in one application
```

这些操作互不替代。

---

# 50. Logout

定义：

## App Logout

删除 App-local Session / local token。

不影响其他软件。

## Identity Provider Logout

可结束中央 IdP Session。

不必强制删除其他 App 已建立的本地 Session，但后续 token refresh / Platform API 策略必须遵循安全要求。

## Global Security Logout

用户选择“退出所有设备”时：

- revoke Identity Provider sessions/tokens；
- invalidate platform-managed session state；
- App BFF 通过短 token 生命周期或 introspection-like check 最终失效。

V2 第一阶段不要求实现实时 websocket logout 广播。

---

# 51. Multi-Application User Isolation

必须有自动测试证明：

```text
User A:
membership in App A
no membership in App B

Token:
client_id = App B

Result:
403 APPLICATION_MEMBERSHIP_REQUIRED
```

即使：

```text
auth.users contains User A
profile is active
```

也必须拒绝。

---

# 52. Cross-client Isolation

同一 Application 的：

```text
web
desktop
mobile
```

可以共享同一个 Membership。

不同 `client_id`：

```text
-> same application_id
-> same membership
```

但可以有不同：

- redirect URIs
- token policy
- environment
- client status

---

# 53. Environment Isolation

Development / Staging / Production OAuth Client 必须分离。

禁止：

```text
Production client_id
+
localhost redirect URI
```

建议：

```text
aisenflow_web_dev
aisenflow_web_staging
aisenflow_web_prod
```

AisenHub Registry 必须知道环境。

---

# 54. Domain Independence

架构不得再包含：

```text
所有产品必须 *.aisenhub.com
```

Application Origin 可以是：

```text
https://aisenflow.com
https://app.otherbrand.io
https://tool.example.ai
```

OAuth Client Redirect URI 同理。

AisenHub 自己可以继续：

```text
account.aisenhub.com
admin.aisenhub.com
```

这只是平台 UI 域名，不是所有产品域名约束。

---

# 55. Supabase Custom Domain

V2 不把 Supabase Custom Domain 当作认证正确性的必要条件。

即使 Identity Provider 仍暴露：

```text
<project-ref>.supabase.co
```

独立 Application 也通过标准 OAuth redirect/token flow 工作。

Custom Domain 只影响：

- branding
- issuer URL
- cookie/provider domain aesthetics
- 部分企业集成体验

它不再是多产品用户管理的架构前提。

---

# 56. Current Platform Cookie Migration

当前：

```text
__Host-aisenhub_session
```

不应立即删除。

迁移期：

```text
Account/Admin
-> continue current Platform Session

New independent App
-> OAuth/OIDC V2

Existing AisenHub child-domain App
-> gradually move to OAuth V2
```

等所有 Application 完成迁移后再评估：

```text
platform_sessions
```

是否只保留 Account/Admin，或被完全替代。

禁止 Big Bang 删除。

---

# 57. Current Origin Migration

当前 `app_origins` 不删除。

迁移：

```text
Phase 1:
Origin still resolves app for current /v1 cookie APIs

Phase 2:
/v2 authenticated APIs derive app from client_id
Origin becomes secondary browser check

Phase 3:
legacy Origin-as-identity paths retired
```

---

# 58. Current Profile Migration

`platform.profiles` 无需重建。

需要做的只是正式修改定义：

```text
old:
platform user profile

new:
global identity profile
```

表结构大概率只需增量字段，不需数据搬迁。

---

# 59. Existing User Migration

现有 Global Users 需要生成 Membership 的策略必须显式。

例如当前只有 AisenLens/AisenHub 用户：

```text
for each existing user
-> create membership for historically used application(s)
```

不能：

```text
for each user
-> membership for every platform app
```

迁移脚本必须有可验证的来源规则。

---

# 60. Application Membership Backfill

建议 migration/backfill 分两步：

```text
1. schema only
2. deterministic data backfill
```

Backfill 来源可以是：

- historical app session
- application-specific feedback
- entitlement
- order item
- explicit legacy user base

如果无法安全推断：

```text
do not invent membership
```

记录 migration exception。

---

# 61. API Versioning

现有 `/v1` 不立即破坏。

新增：

```text
/v2
```

原因：

V2 Auth Context 的安全语义发生变化：

```text
Origin identity
->
OAuth client identity
```

这属于协议级变化，应显式版本化。

---

# 62. Compatibility Window

推荐：

```text
/v1
legacy Platform Session
read-only compatibility / existing apps

/v2
OAuth Client + Membership
new default
```

当：

- 所有应用迁移；
- Staging 验证；
- Production usage telemetry 确认；
- 无 `/v1` consumer；

再删除 legacy auth paths。

---

# 63. Observability

每个认证请求日志至少包含安全可公开字段：

```text
requestId
route
resultCode
applicationId
oauthClientId hash/alias
membershipStatus
authMethod
aal
```

不得日志：

- raw access token
- refresh token
- client secret
- authorization code
- session cookie
- password
- MFA secret

---

# 64. Audit

新增 Audit Action：

```text
identity.application_joined
identity.application_left
identity.application_suspended
identity.application_restored

oauth.client_created
oauth.client_disabled
oauth.redirect_uri_added
oauth.redirect_uri_disabled

application.registration_policy_changed
```

高风险 Admin Mutation：

- MFA required where appropriate；
- reason required；
- idempotency required；
- audit in same reliable boundary。

---

# 65. Rate Limits

OAuth Provider 层使用 Provider 限制。

Platform API 还应支持：

```text
per user
per client_id
per application
per IP where appropriate
```

第一阶段可以先做可观测性和简单限制。

不为了限流单独引入 Redis。

---

# 66. Testing Strategy

## Database

新增：

```text
application membership schema
membership lifecycle
unique(app,user)
suspension
deletion
client binding
redirect exactness
privilege matrix
audit
```

## RLS / Privilege

验证：

```text
authenticated cannot directly list memberships
anon cannot read OAuth clients
public cannot mutate redirect URIs
service role cannot bypass intended public entrypoints through accidental grants
SECURITY DEFINER fixed search_path
```

## Integration

至少覆盖：

```text
App A member -> App A 200
App A member -> App B 403
suspended membership -> 403
disabled app -> 403
disabled client -> 403
wrong Origin + valid client -> 403 in browser flow
no Origin + valid desktop client -> allowed
invalid client_id -> 401/403
```

## OAuth E2E

覆盖：

```text
Authorization Code + PKCE
state mismatch
redirect URI mismatch
code replay
expired code
login
consent
callback
refresh
logout
```

## Cross-domain Browser E2E

至少准备两个真正不同 site：

```text
app-a.localhost-style test host
app-b different test host
```

验证：

```text
no shared Cookie dependency
```

---

# 67. CI Gate

现有 `platform:verify` 继续保留。

V2 增加：

```text
oauth contract tests
membership integration tests
provider config drift tests
cross-application isolation tests
```

建议把关键 Playwright 浏览器流程从：

```text
--list only
```

升级为 PR smoke。

Release Candidate 必须运行完整 OAuth + Membership journey。

---

# 68. Production Gate

继续保持现有 P8 的核心治理原则：

```text
Infrastructure authorization
!=
Deployment approval
!=
DNS/payment cutover approval
```

V2 Identity 升级应新增独立 Production Gate：

```text
OAuth Provider Enablement
OAuth Client Registration
JWT signing key migration
Redirect URI production registration
Account authorization UI deployment
App pilot cutover
```

不得因为这是“Auth 配置”而绕过 Production approval。

---

# 69. Recommended Migration Program

建议不在当前 P8 Production Release 中临时插入 V2 大改。

更安全的做法：

```text
Current Architecture Production Baseline
        ↓
V2 Architecture Adoption
        ↓
New Implementation Program
```

---

# 70. V2 Phase A — Architecture Freeze

目标：

- 正式采纳本文件；
- 更新 `AGENTS.md` 权威顺序；
- 创建 Architecture Changelog；
- 明确 `/v1` compatibility；
- 不改 Production。

输出：

```text
Architecture V2 adopted
```

---

# 71. V2 Phase B — Membership Foundation

新增：

```text
application_memberships
membership commands
membership projections
Admin membership management
audit actions
```

此阶段仍不改变现有登录。

验证：

```text
DB
RLS
integration
Admin
```

---

# 72. V2 Phase C — OAuth Client Registry

新增：

```text
application_oauth_clients
oauth_redirect_uris
provider bindings
drift verification
```

启用 Supabase OAuth Server 只属于实现步骤，不成为数据库业务权威。

---

# 73. V2 Phase D — Auth Context Kernel

新增 Backend Kernel：

```text
Bearer validation
client_id binding
application resolution
membership validation
```

新增：

```text
/v2/app/*
```

现有 `/v1` 不变。

---

# 74. V2 Phase E — Account Authorization UI

升级：

```text
apps/account
```

使其承担：

- Global Identity
- OAuth authorization UI
- consent
- My Applications
- Membership lifecycle

不要把 OAuth Provider protocol state 自己重新实现到 PostgreSQL。

---

# 75. V2 Phase F — SDK / BFF

交付：

```text
auth-client
platform-client V2
web-session adapter
```

目标：

新软件接入认证时不复制安全代码。

---

# 76. V2 Phase G — Pilot Application

选择一个非关键 Application：

```text
Application OAuth Client
-> login
-> membership
-> app-local session
-> Platform API
-> entitlement
-> logout
```

Staging 全流程通过。

---

# 77. V2 Phase H — Existing Application Migration

逐一迁移：

```text
Account-consumer apps
AisenFlow
其他 tools
```

每个应用独立 cutover。

禁止一次切换所有工具。

---

# 78. V2 Phase I — Legacy Session Retirement

只有当：

```text
no legacy app consumer
no required /v1 auth consumer
Production telemetry verified
rollback window passed
```

才允许：

```text
retire Origin-as-identity
retire cross-product Platform Cookie assumptions
```

---

# 79. Architecture Boundary Rules

正式采纳后应加入自动 boundary check。

禁止：

```text
apps/* directly import @supabase/supabase-js for Platform business data
apps/* inspect database schema
apps/* trust app slug from user input
apps/* create their own global identity database
apps/* share parent-domain cookies as SSO mechanism
```

允许：

```text
auth adapter uses provider SDK
BFF uses OAuth protocol
platform-client uses Platform API
```

---

# 80. New Application Onboarding Contract

以后新增一个软件只需要完成：

```text
1. Create Application
2. Choose registration policy
3. Create OAuth Client(s)
4. Register exact redirect URI(s)
5. Register browser Origin(s), if web
6. Configure Application products/features, if needed
7. Integrate auth-client/BFF adapter
8. Integrate platform-client
9. Pass isolation/security E2E
10. Production approval
```

不需要：

- 新建用户数据库；
- 复制 Supabase Project；
- 共享 Cookie；
- 复制 Account 系统；
- 直接访问 AisenHub PostgreSQL。

---

# 81. Example — AisenFlow

```text
Application:
aisenflow

Clients:
aisenflow_web_prod
aisenflow_web_staging
aisenflow_desktop

Origins:
https://aisenflow.com
https://staging.aisenflow.com

Membership:
USER-001 + AISENFLOW -> active

Entitlements:
flow.basic
flow.pro
flow.ai_credits
```

---

# 82. Example — Independent Tool B

```text
Application:
tool-b

Domain:
https://tool-b.io

User:
USER-900

Membership:
USER-900 + TOOL_B -> active

AisenFlow membership:
none
```

即使两个 Application 使用同一个 AisenHub Identity Backend：

```text
Tool B cannot list or treat AisenFlow-only users as Tool B users.
```

---

# 83. Example — Same Person Uses Two Products

```text
Global Identity:
USER-001

Memberships:
USER-001 -> AisenFlow
USER-001 -> Writer

Sessions:
aisenflow.com cookie
writer.example cookie

Identity:
same sub

Application context:
different client_id
```

这就是 V2 期望的统一用户平台。

---

# 84. Failure Model

## Provider unavailable

现有 App-local Session 可按短暂容忍策略继续工作。

需要新登录/refresh 时失败。

Platform API 不应因此绕过 Token validation。

## Membership DB unavailable

Authenticated Application API fail closed。

## OAuth client registry drift

停止新的授权流程并告警。

不要自动扩大 redirect URI。

## Application suspended

所有该 Application API 业务请求立即拒绝。

## Global account disabled

所有 Application 请求拒绝。

---

# 85. Non-goals

V2 第一阶段不实现：

- Organizations / Teams
- arbitrary tenant-defined applications
- OpenFGA
- SAML enterprise federation
- SCIM
- custom OAuth grant types
- client_credentials for user identity
- generic API key platform
- device fingerprinting
- cross-domain shared cookie
- microservices
- event sourcing
- Kafka
- Redis dependency
- Kubernetes
- second business database

这些能力只有在真实消费者出现后再设计。

---

# 86. Future Extension Points

预留但不提前实现：

```text
Organization Membership
Team Membership
Enterprise SSO
SCIM
API Credentials
MCP OAuth
Usage/Credits
Application-specific Roles
Service Accounts
Developer Portal
Third-party OAuth Apps
```

其中任何一项都必须建立在：

```text
Global Identity
Application
Membership
OAuth Client
```

这四个 V2 基础对象之上。

---

# 87. Final Architecture Invariants

正式实现过程中，不允许破坏以下不变量。

## Identity

```text
auth.users = Global Identity
```

## Profile

```text
profile status != application membership
```

## Application

```text
application != domain
```

## Membership

```text
global identity exists
does not imply
application membership exists
```

## OAuth

```text
client_id -> exactly one application
```

## Browser

```text
Origin is security evidence
not authenticated application identity
```

## Session

```text
independent applications do not share cookies
```

## Authorization

```text
active identity
AND active application
AND active client
AND active membership
```

## Entitlement

```text
membership != entitlement
```

## Database

```text
PostgreSQL = business source of truth
```

## Frontend

```text
frontend never becomes auth/business authority
```

## Provider

```text
Supabase Auth = replaceable identity implementation
```

## Architecture

```text
OAuth/OIDC Contract
+
Platform API Contract
=
stable integration boundary
```

---

# 88. Recommended Repository Target Structure

```text
apps/
  account/
  admin/

packages/
  contracts/
  auth-client/
  platform-client/
  admin-client/
  web-session/
  design-system/
  config/

supabase/
  functions/
    _shared/
      auth/
      http/
      db/
      domains/
        identity/
        applications/
        memberships/
        entitlements/
        commerce/
      routers/
    platform-api/
    platform-admin/
    platform-public/
    payment-webhook/
    account-deletion-worker/
    retention-cleanup/

  migrations/
  tests/
  types/

docs/
  AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md
  ARCHITECTURE_CHANGELOG.md
  implementation/
```

---

# 89. Existing Component Disposition

| Current component | V2 decision |
| --- | --- |
| `auth.users` | Keep; define as Global Identity |
| `platform.profiles` | Keep; define as Global Profile |
| `platform.platform_apps` | Keep and extend |
| `platform.app_origins` | Keep; change from identity authority to browser security boundary |
| `platform.platform_sessions` | Keep during migration; stop treating as universal multi-app session |
| `platform.admin_members` | Keep; separate Platform Admin membership |
| `packages/contracts` | Keep; add Membership/OAuth V2 contracts |
| `packages/platform-client` | Keep; evolve to Bearer/App-context Platform SDK |
| `packages/admin-client` | Keep |
| `apps/account` | Evolve into Identity + Authorization + My Applications UI |
| `apps/admin` | Keep; add Application Members/OAuth Client management |
| Entitlement model | Keep |
| Redemption model | Keep |
| Commerce model | Keep |
| Audit model | Keep and add application context |
| Idempotency model | Keep |
| RLS/security tests | Keep and extend |
| `Origin -> app` authenticated authority | Deprecate for V2 |
| cross-product Cookie SSO assumption | Retire |
| modular monolith | Keep |

---

# 90. Adoption Decision

如果本架构正式采用，下一步不是立即修改全部代码。

正确顺序：

```text
1. Approve Architecture V2
2. Update architecture authority references
3. Create V2 implementation master plan
4. Build dependency graph / atomic tasks
5. Implement Membership before OAuth cutover
6. Add /v2 in parallel with /v1
7. Pilot one Application
8. Staging
9. Production gate
10. Migrate applications one by one
11. Retire legacy session assumptions
```

最终目标：

> **One Identity Platform, many independent applications.**
>
> AisenHub 统一管理“这个人是谁”和“他属于哪些软件”，每个软件独立管理自己的 Session、域名和产品体验；平台统一提供安全、Membership、Entitlement、Commerce、Admin 与 Audit 能力。
