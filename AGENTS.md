# AisenHub Platform — AGENTS.md

## 1. 文档定位

本文件是 AisenHub Platform 仓库中所有 AI Coding Agent、开发 Agent 和人工开发者必须遵守的全局工程规则。

适用范围：

- `apps/account`
- `apps/admin`
- `packages/*`
- `supabase/*`
- `tests/*`
- `scripts/*`
- Platform API
- PostgreSQL
- Supabase Auth
- Edge Functions
- Contracts
- SDK
- 自动化测试
- CI/CD

本文件规定：

> 如何实现 AisenHub Platform。

正式架构文档规定：

> AisenHub Platform 应该实现什么，以及为什么这样设计。

---

# 2. 权威优先级

出现冲突时，按照以下优先级执行：

1. `docs/AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md`
2. 已批准 ADR / Architecture Decision
3. `docs/implementation/MASTER_PLAN.md`
4. 当前 Phase / Atomic Task
5. 根目录 `AGENTS.md`
6. 当前子目录自己的 `AGENTS.md`
7. 当前实现代码
8. Agent 自身判断

不得为了迁就旧代码而偏离正式架构。

不得为了实现方便自行修改：

- 数据模型
- Auth 模型
- Session 模型
- Entitlement 模型
- Redemption 模型
- API Contract
- Admin 安全边界
- Query / Command 边界

如果正式架构本身存在无法安全实施的矛盾：

必须创建：

`ARCHITECTURE_BLOCKER`

不得静默修改架构。

---

# 3. 平台定位

AisenHub Platform 是多个 AisenHub 产品和独立工具共用的平台后端。

典型域名：

```text
aisenhub.com
account.aisenhub.com
admin.aisenhub.com
api.aisenhub.com
*.aisenhub.com
```

平台负责：

- Identity
- Platform Session
- Applications
- Origins
- Features
- Products
- Product Versions
- Prices / Offers
- Orders
- Payments
- Refunds
- Entitlements
- Redemption
- Feedback
- Administration
- Audit
- 未来 Usage / Credits

核心原则：

```text
Platform Backend = 唯一业务权威

PostgreSQL = 唯一事实存储

API Contract = 前后端稳定边界
```

任何前端、SDK、Admin Framework 都不能成为第二个业务权威。

---

# 4. 当前技术路线

第一阶段平台后端采用：

- Supabase Auth
- PostgreSQL
- Row Level Security
- PostgreSQL Functions
- Supabase Edge Functions
- TypeScript
- Deno
- pnpm workspace

前端应用：

- React
- TypeScript
- Vite

具体 UI 技术栈由各应用自己的 `AGENTS.md` 决定。

其中：

```text
apps/admin
```

使用：

```text
Refine + Ant Design
```

详见：

`apps/admin/AGENTS.md`

未经正式架构变更，不得自行引入：

- 微服务
- Redis
- Kafka
- Kubernetes
- OpenFGA
- Workflow Engine
- Event Sourcing
- CQRS 基础设施
- 第二套 Auth
- 第二套核心数据库

---

# 5. 可迁移性目标

当前使用 Supabase 不代表业务代码必须绑定 Supabase。

系统必须保留未来迁移能力：

```text
Supabase Managed PostgreSQL
→ Self-hosted PostgreSQL
```

以及：

```text
Supabase Edge Functions
→ Node / Go / 其他 Platform Backend
```

因此：

- 前端不得依赖数据库表结构
- Admin 不得直接访问 Supabase Data API
- SDK 只依赖 API Contract
- Business Logic 必须位于 Platform Backend
- Contracts 必须保持清晰稳定

---

# 6. Autonomous First

Agent 默认工作模式：

```text
AUTONOMOUS
```

只要 Agent 能通过以下方式自行完成，就不得询问用户：

- 阅读代码
- 阅读架构文档
- 阅读任务
- 查看官方文档
- 安装开发依赖
- 修改代码
- 创建 migration
- 创建 seed
- 启动 Docker-compatible runtime
- 启动 Supabase Local
- 创建测试账号
- 写测试
- 执行测试
- Debug
- 修复 lint
- 修复 typecheck
- 修复 build
- 重建本地数据库
- 使用 fixture / mock
- 使用 Playwright
- 使用测试环境

普通开发问题不是 Human Gate。

---

# 7. Human Gate

只有以下情况允许要求用户介入。

## 7.1 外部账号授权

例如：

- Supabase Cloud
- GitHub
- Vercel
- Cloudflare
- 支付平台

必须先检查已有授权。

已有有效授权时不得重复询问。

## 7.2 Secret / Credential

例如：

- Supabase Access Token
- Production Database Password
- Webhook Secret
- OAuth Secret
- Payment Secret
- Redemption Pepper

不得要求用户把 Secret 写入聊天或代码。

应要求用户配置到指定：

- Secret Manager
- CI Secret
- Supabase Secret
- Environment

## 7.3 外部资源

例如：

- Staging Supabase Project
- Production Supabase Project
- DNS Record
- Vercel Project

只有 Agent 没有足够权限时才触发 Human Gate。

## 7.4 产品商业决策

例如：

- 价格
- 买断范围
- 是否包含未来版本
- Refund Policy
- 全站权益范围

技术细节不得伪装成产品决策。

## 7.5 Production 风险

必须明确 Human Gate：

- Production migration
- Production 数据删除
- Production DNS 修改
- Production Secret 修改
- 正式支付切换
- 大规模权益操作

---

# 8. Local First

默认开发环境：

```text
Docker-compatible runtime
+
Supabase CLI
+
Supabase Local
```

Docker 只属于：

> 本地开发与测试基础设施。

不代表 Production 必须 Docker 化。

Agent 应自行完成：

- Supabase Local 启动
- database reset
- migrations
- seed
- Auth test users
- SQL tests
- RLS tests
- Edge Functions
- API tests
- contract tests
- type generation
- Playwright E2E

Local 阶段目标：

```text
Human Interaction = 0
```

## 8.1 软件安装路径

凡支持自定义安装路径的软件、开发工具和本地运行时，统一安装到 `D:\APP\Codex` 下对应的软件独立目录中，例如：

```text
D:\APP\Codex\<SoftwareName>
```

不得将 `D:\APP\Codex` 本身作为单个软件的根目录。安装前必须优先确认安装器支持自定义目录，并显式指定对应子目录。不得主动将新软件安装到 `C:\` 或使用安装器默认路径。若安装器不支持自定义路径，必须暂停并报告，不能默认为符合本规则；已有安装不因本规则自动迁移。

---

# 9. 环境隔离

必须严格区分：

```text
Local
Staging
Production
```

不得共享：

- Database
- Service Role Secret
- Webhook Secret
- Redemption Pepper
- Payment Secret
- OAuth Secret

Local 使用：

- 固定 Seed
- 测试账户
- 测试商品
- 测试兑换码
- 测试支付事件

不得默认使用 Production 数据进行本地开发。

---

# 10. 仓库边界

典型仓库结构：

```text
AisenHub-platform/

├── apps/
│   ├── account/
│   └── admin/
│
├── packages/
│   ├── platform-client/
│   ├── admin-client/
│   ├── contracts/
│   ├── design-system/
│   └── config/
│
├── supabase/
│   ├── migrations/
│   ├── functions/
│   ├── tests/
│   ├── seed.sql
│   └── config.toml
│
├── docs/
├── tests/
├── scripts/
├── package.json
├── pnpm-workspace.yaml
└── pnpm-lock.yaml
```

实际结构如果已经确定不同：

以正式架构与当前仓库为准。

不得为了符合示例而进行无价值目录重构。

---

# 11. Root 目录规则

新增文件前：

1. 优先寻找已有合适目录。
2. 不创建职责不明确的根目录。
3. Supabase Backend 放在 `supabase/`。
4. 稳定共享能力放入 `packages/`。
5. 文档放入 `docs/`。
6. 开发自动化放入 `scripts/`。
7. scripts 不得承载正式业务逻辑。

只有真正稳定、可独立测试、具有明确消费者边界的能力才创建 package。

---

# 12. 模块化单体

Platform Backend 使用模块化单体。

领域：

```text
Identity
Application
Catalog
Commerce
Entitlement
Redemption
Feedback
Administration
Audit
Usage
```

允许：

- 同一 PostgreSQL
- 同一事务
- 外键关系

禁止：

```text
user.is_pro
user.supporter
user.is_pdf_pro
user.is_lens_pro
```

禁止：

- Product 直接存用户权限
- Redemption Code 直接修改 Role
- 前端根据订单状态自己推断权益
- 各 Tool 自建独立用户体系

---

# 13. 数据库变更

所有数据库结构修改必须通过 migration。

禁止：

- 手工改数据库后不创建 migration
- 修改已经发布的 migration
- Application startup 自动修改正式 schema
- Production 临时修改后不进入代码仓库

正确流程：

```text
Migration
↓
Local DB Reset
↓
Database Test
↓
RLS Test
↓
Type Generation
↓
Integration Test
```

已发布 migration：

不可修改。

后续变化：

创建新 migration。

---

# 14. Schema 与安全边界

按照正式架构区分：

- 可公开 API 的 schema
- private / platform schema
- 敏感业务表

敏感领域不得因为 Supabase 使用方便而全部暴露到浏览器 Data API。

尤其：

- sessions
- payments
- entitlement grants
- redemption codes
- admin members
- audit

必须遵守正式安全边界。

---

# 15. RLS

不能认为：

```text
启用 RLS = 自动安全
```

Migration 必须同时考虑：

- ENABLE RLS
- Policy
- GRANT
- REVOKE
- Constraint
- Index

重要 Policy 必须有：

```text
ALLOW Test
DENY Test
```

至少覆盖：

- anon
- authenticated
- owner
- other user
- privileged backend

---

# 16. Service Role

Service Role：

只能存在于安全服务端环境。

禁止：

- 浏览器
- Account 前端
- Admin 前端
- localStorage
- public environment variable

前端不得因为 Admin 属于内部系统就持有 Service Role。

---

# 17. PostgreSQL Functions

涉及强一致性操作时优先由 Backend / PostgreSQL Transaction 保证。

例如：

- Redemption
- Entitlement Grant
- Refund
- Payment Fulfillment
- Audit
- Idempotency

`SECURITY DEFINER` 函数必须：

- 固定安全 `search_path`
- 最小执行权限
- 有明确调用者
- 有 SQL Tests
- 有并发 Tests
- 有失败 Rollback Tests

---

# 18. API-first

Platform API 使用：

```text
/v1/*
```

Admin API：

```text
/v1/admin/*
```

API 必须：

- Stable Contract
- Stable Error Code
- `requestId`
- Runtime Validation
- Authorization
- 安全错误映射

不得向客户端暴露：

- SQLSTATE
- Stack Trace
- Database Table
- Service Role Secret
- Redemption Hash
- Payment Secret

---

# 19. Query 与 Command

必须区分：

```text
Query
→ 查询当前事实

Command
→ 请求改变业务状态
```

不得为了前端 CRUD 框架方便，将业务 Command 强行实现为普通 Update。

例如：

```text
publish product version
refund order item
grant entitlement
revoke entitlement
generate redemption codes
```

必须通过正式 Business Command。

---

# 20. Contracts

`packages/contracts` 是以下内容的唯一类型来源：

- Request
- Response
- Error Code
- Permission Action
- API Shared Types

禁止：

- Admin 重复定义 User API 类型
- Account 复制另一份错误码
- Edge Function 和 Client 分别维护类型
- SDK 自己猜测 Response

Contract 修改必须检查所有消费者。

---

# 21. platform-client

普通产品和 Account 使用：

```text
packages/platform-client
```

它只依赖：

- HTTP/API Contract

不得知道：

- 数据库表名
- RLS 细节
- SQL
- Service Role

---

# 22. admin-client

Admin 使用：

```text
packages/admin-client
```

只依赖：

```text
HTTP
+
packages/contracts
```

禁止依赖：

- Supabase Data SDK
- PostgreSQL Driver
- Service Role
- Database Schema

未来 Backend 从 Edge Functions 迁移到 Node / Go 时：

只要 `/v1/admin/*` Contract 保持兼容，

Admin 不应大规模修改。

---

# 23. Auth

统一身份来源：

```text
Supabase Auth
```

禁止：

- 自己保存 Password
- 自己实现 Password Hash
- Tool 自建账号
- Admin 创建第二套 Login DB

Platform Session 由 Platform Backend 管理。

---

# 24. Session

统一登录：

```text
account.aisenhub.com
+
api.aisenhub.com
```

不得随意扩大 Cookie Domain。

不得为了方便让所有 `*.aisenhub.com` 接收敏感 Session Cookie。

具体 Cookie / Session 规则遵循正式架构。

---

# 25. CORS / CSRF

带 Credential 的 Platform API 必须验证：

- Origin
- App
- Session
- CSRF
- Permission

客户端 Header 不是可信身份来源。

服务端必须独立确认。

不得：

```text
Access-Control-Allow-Origin: *
```

与 Credential 同时使用。

---

# 26. Entitlement

付费权限不是 Role。

权限统一通过：

```text
entitlement_grants
+
features
+
checkAccess()
```

实现。

来源可以包括：

- order
- redemption
- admin
- promotion

前端不得自行计算最终 Entitlement。

---

# 27. Redemption

兑换码必须：

- 使用安全随机数
- 数据库仅保存安全摘要
- 明文只在首次生成时返回
- 后续只展示 hint
- 不进入日志

兑换流程必须考虑：

- transaction
- row lock
- idempotency
- batch status
- expiry
- per-user limit
- grant
- audit

---

# 28. Audit

权威 Audit 必须由 Backend 产生。

浏览器不能成为权威 Audit 来源。

Audit 不允许：

- 编辑
- 删除
- 覆盖

日志不得记录：

- Password
- Token
- Authorization
- Cookie
- Redemption Plaintext
- Payment Secret

---

# 29. Secret

禁止提交：

- `.env`
- API Key
- Service Role Key
- JWT Secret
- Payment Secret
- OAuth Secret
- Redemption Pepper
- Database Password

`.env.example`：

只保存变量名称和安全示例。

---

# 30. Package Manager

统一使用：

```text
pnpm
```

必须提交：

```text
pnpm-lock.yaml
```

不得手工修改 lockfile。

不得擅自切换：

- npm
- yarn
- bun

除非正式技术决策改变。

---

# 31. Dependency

新增依赖前：

1. 检查已有能力。
2. 检查现有 package。
3. 检查标准库。
4. 检查维护状态。
5. 检查许可证。
6. 判断是否真正必要。

禁止为了很小的能力引入大型依赖。

禁止引入重复实现相同职责的框架。

---

# 32. TypeScript

保持 Strict Type Safety。

避免：

- `any`
- `@ts-ignore`
- 关闭 strict
- 重复定义 Contract

外部输入必须 Runtime Validation。

TypeScript 类型不能替代运行时校验。

---

# 33. 代码职责分离

保持：

```text
UI
≠
Business Logic
≠
Data Access
≠
Protocol
```

不要创建巨大万能：

```text
utils.ts
helpers.ts
common.ts
```

拆分按照职责，而不是单纯按照文件行数。

---

# 34. Test First for Critical Areas

以下领域优先：

```text
Test
→ Implementation
→ Test Pass
```

包括：

- RLS
- Session
- CSRF
- CORS
- Redemption
- Entitlement
- Idempotency
- Refund
- Admin Permission

不得只验证 Happy Path。

---

# 35. 自动化测试

不得把以下操作交给用户作为主要验收：

- 手动创建测试用户
- 手动登录
- 手动兑换
- 手动测试退款
- 手动查看数据库
- 手动测试权限按钮

优先使用：

- SQL Test
- Unit Test
- Contract Test
- Integration Test
- API Test
- Playwright E2E

---

# 36. Quality Gate

每个 Phase 结束至少执行适用项：

```text
format
lint
typecheck
unit tests
database tests
RLS tests
contract tests
API tests
integration tests
E2E
build
```

失败：

```text
定位
→ 修复
→ 重跑
```

不得第一次失败就要求用户介入。

---

# 37. Progress

Agent 必须持续维护：

```text
docs/implementation/PROGRESS.md
docs/implementation/TASK_LEDGER.md
```

开始 Task：

```text
in_progress
```

Acceptance Criteria 全部通过：

```text
completed
```

阻塞：

```text
blocked
```

不得：

- 未运行测试就写 PASS
- 测试失败仍标 completed
- 隐藏 Blocker
- 静默偏离架构

---

# 38. Phase Checkpoint

每个 Phase 完成创建：

```text
docs/implementation/checkpoints/PHASE-XX.md
```

记录：

- Completed Tasks
- Delivered Functionality
- Migrations
- APIs
- Tests
- Quality Gates
- Known Limitations
- Deferred Items
- Architecture Deviations
- Human Interventions
- Git Range
- Next Phase

没有架构偏离：

明确写：

```text
Architecture Deviations: None
```

---

# 39. Architecture Blocker

如果无法在当前架构内安全完成：

创建：

```text
docs/implementation/blockers/AB-XXX.md
```

不得自行修改架构。

---

# 40. Git

以 Atomic Task 或紧密 Task Group 作为 Commit 边界。

例如：

```text
feat(db): add product catalog schema
test(db): add catalog RLS tests
feat(session): add platform session exchange
feat(redemption): add redemption transaction
feat(admin): add admin session API
```

不要一个 Phase 只产生一个巨型 Commit。

---

# 41. Documentation

代码、Contract、环境配置发生正式变化时：

同步实现级文档。

但不得为了匹配错误实现反向偷偷修改 Architecture。

顺序：

```text
Architecture
→ Plan
→ Implementation
→ Documentation Sync
```

---

# 42. Production

Local：

默认自主执行。

Staging：

有授权则自主执行。

Production：

必须遵守 Human Gate。

未经明确批准禁止：

- Production reset
- DROP 数据
- 不可逆 migration
- DNS 修改
- Secret 修改
- 大规模 Entitlement 修改

---

# 43. 禁止过度工程化

第一阶段禁止无现实需求引入：

- Microservices
- Kafka
- Redis
- Kubernetes
- Event Sourcing
- CQRS Infrastructure
- OpenFGA
- Workflow Engine
- Plugin Marketplace
- Low-code Builder
- BI Platform
- 通用 CMS

---

# 44. 最终工程优先级

```text
正确架构边界
>
安全
>
数据一致性
>
自动化测试
>
可维护性
>
迁移能力
>
开发效率
>
抽象美观
```

Agent 的职责不是写最多代码。

Agent 的职责是：

> 在不偏离 AisenHub 正式架构的前提下，以最小必要复杂度持续交付安全、可测试、可审计、可迁移的平台系统。
