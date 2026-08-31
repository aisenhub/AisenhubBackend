# AisenHub Admin — AGENTS.md

## 1. 文档定位

本文件仅适用于：

```text
apps/admin/
```

AisenHub Admin 是：

> 面向 AisenHub 内部运营、客服、财务和平台管理员的管理控制前端。

它属于 Backend Operations / Administration 系统的一部分，但从技术实现来看：

> Admin 本身仍然是一个 Web Frontend Application。

真正业务逻辑位于：

```text
AisenHub Platform Backend
```

---

# 2. 规则优先级

Admin 开发同时遵守：

1. `docs/AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md`
2. `/AGENTS.md`
3. `apps/admin/AGENTS.md`
4. 当前实施 Task
5. 当前代码

如果本文件与正式架构冲突：

正式架构优先。

---

# 3. Admin 定位

`admin.aisenhub.com` 是：

```text
AisenHub Operations Control Platform
```

不是：

- PostgreSQL 管理器
- Supabase Dashboard 替代品
- Database Table Editor
- CMS
- BI Platform
- Low-code Builder
- Workflow Builder
- SQL Console

Admin 负责：

```text
展示
搜索
筛选
查看
输入
确认
发起 Business Command
展示结果
展示 Audit
```

Admin 不负责：

```text
决定最终权限
执行核心状态机
执行 Redemption Transaction
决定 Entitlement
创建权威 Audit
直接写敏感数据库
```

---

# 4. Admin 技术栈

正式采用：

```text
React
TypeScript
Vite
Refine Core
@refinedev/antd
Ant Design
pnpm
```

如 Workspace 已统一 React 19：

Admin 使用 React 19。

不得未经正式技术决策更换：

- React
- Vite
- Refine
- Ant Design

---

# 5. Ant Design 是唯一主要 UI Component System

Admin 使用：

```text
Ant Design
```

作为唯一主要 UI Component System。

禁止引入第二套完整 UI Framework，例如：

- shadcn/ui
- Material UI
- Chakra UI
- Mantine
- Arco Design
- Element
- PrimeReact

除非正式 Architecture / ADR 明确改变。

---

# 6. 为什么使用 Ant Design

Admin 是高信息密度运营后台，会大量使用：

- Table
- Form
- Select
- DatePicker
- Modal
- Drawer
- Tabs
- Descriptions
- Statistic
- Tag
- Badge
- Tooltip
- Dropdown
- Tree
- Pagination
- Steps
- Alert
- Result
- Notification

优先复用 Ant Design 成熟能力。

不得重复实现 Ant Design 已经稳定提供的基础组件。

---

# 7. Refine + Ant Design

优先使用：

```text
@refinedev/core
@refinedev/antd
```

可复用：

- Resource
- Router
- Auth Provider
- Access Control Provider
- Data Provider
- Notification Provider
- useTable
- useForm
- useModalForm
- useDrawerForm
- useStepsForm
- List
- Show
- Create
- Edit
- DeleteButton（只允许安全 Resource）
- RefreshButton
- Import / Export（仅适用安全资源）

不得为了“统一代码风格”绕开成熟 Refine/Ant Design 集成重新造一套。

---

# 8. AisenHub Admin Theme

Admin 不重新开发基础 UI Framework。

AisenHub 品牌化通过：

```text
Ant Design ConfigProvider
+
Ant Design Theme Token
+
AisenHub Admin Theme
+
领域业务组件
```

完成。

Theme 可以定义：

- Brand Color
- Typography
- Border Radius
- Spacing
- Layout
- Status Color
- Component Token

不得复制 Ant Button / Table / Form 重新包装一整套基础 UI。

---

# 9. Tailwind

Admin 不以 Tailwind 作为主要 UI 系统。

如果项目当前没有 Tailwind：

不要为了 Admin 单独引入。

如果 Workspace 已经存在 Tailwind：

仅允许用于少量布局或非常明确的辅助场景。

不得形成：

```text
Ant Design
+
Tailwind Component System
```

两套 UI 体系并行。

---

# 10. AisenHub Design System 在 Admin 中的含义

Admin Design System 主要负责：

```text
Theme
Layout
Design Token
Domain Components
Status Semantics
Interaction Conventions
```

不是重新实现：

- Button
- Input
- Select
- Form
- Table
- Modal
- Drawer
- DatePicker
- Dropdown

这些优先使用 Ant Design。

---

# 11. 推荐自研业务组件

以下属于 AisenHub Admin 领域能力，可以自行实现：

```text
DangerousActionDialog
AuditTimeline
EntityHeader
EntityStatus
PermissionGuard
MoneyDisplay
ProductVersionDiff
EntitlementPanel
RedemptionBatchSummary
OrderTimeline
UserSummary
RequestTrace
MfaRequirement
```

这些组件可以基于 Ant Design 构建。

---

# 12. UI 组件复用顺序

实现 UI 前严格检查：

1. Ant Design 是否已有组件。
2. `@refinedev/antd` 是否已有集成能力。
3. `apps/admin/src/components` 是否已有公共组件。
4. 当前 Module 是否已有业务组件。
5. `packages/design-system` 是否已有真正跨应用共享组件。
6. 最后才新建。

原则：

```text
复用
>
扩展
>
组合
>
新增
```

不要复制近似组件。

---

# 13. 通用 UI 不包含业务逻辑

例如：

```text
DangerousActionDialog
```

可以负责：

- Warning
- Reason Form
- Confirm Text
- Loading
- Error
- Submit State

不得负责：

```text
refund logic
entitlement logic
product publish logic
fetch API
```

业务逻辑由调用方 Business Command Hook 负责。

---

# 14. Admin 数据流

必须遵循：

```text
Page / Component
        ↓
Module Hook
        ↓
Admin Data Provider
或
Business Command Client
        ↓
/v1/admin/*
        ↓
AisenHub Platform Backend
        ↓
PostgreSQL
```

禁止：

```text
Component
→ Supabase
```

禁止：

```text
Component
→ PostgreSQL
```

禁止：

```text
Page
→ 任意散落 fetch()
```

---

# 15. 禁止 Supabase Data API

Admin Browser 代码不得：

```ts
supabase.from(...)
supabase.rpc(...)
```

访问敏感 Platform 数据。

特别禁止直接访问：

- orders
- order_items
- payments
- payment_events
- entitlement_grants
- redemption_codes
- redemptions
- platform_sessions
- admin_members
- audit_logs

发现这种实现：

视为 Architecture Violation。

---

# 16. Admin Client

所有 Platform Admin API 调用优先集中在：

```text
packages/admin-client
```

它只能依赖：

```text
HTTP
+
packages/contracts
```

不得依赖：

- Supabase Data SDK
- PostgreSQL Driver
- Service Role
- Database Schema

---

# 17. Resource Query

Resource Query 用于：

```text
List
Get
Search
Filter
Sort
Pagination
Overview
```

走：

```text
AisenHubAdminDataProvider
```

典型 Resource：

- Applications
- Products
- Product Versions
- Prices
- Users
- Orders
- Payments
- Redemption Batches
- Redemptions
- Entitlements
- Feedback
- Audit Logs

---

# 18. Business Command

改变业务状态必须通过：

```text
AisenHubBusinessCommandClient
```

例如：

- Publish Product Version
- Retire Product Version
- Set Current Product Version
- Generate Redemption Codes
- Pause Redemption Batch
- Close Redemption Batch
- Grant Entitlement
- Revoke Entitlement
- Restore Entitlement
- Refund Order Item
- Disable User
- Change Production Origin
- Manage Admin Member

不得伪装成：

```text
dataProvider.update()
```

---

# 19. 不允许 Edit Row 改状态机

以下状态不得直接编辑：

```text
order.status
payment.status
entitlement.status
redemption.status
product_version.status
user.status
admin_member.status
```

错误：

```text
PATCH entitlement
status = revoked
```

正确：

```text
POST /v1/admin/entitlements/{id}/revoke
```

---

# 20. Page 职责

页面负责：

- Page Layout
- Resource Composition
- Query Composition
- Business Component Composition
- Navigation
- User Interaction

页面不负责：

- 写 API URL
- Database Query
- Permission Engine
- Refund State Machine
- Entitlement Resolution
- Redemption Transaction
- Audit Creation

---

# 21. 推荐 Module

按领域组织：

```text
modules/

overview/
catalog/
commerce/
redemption/
customers/
governance/
```

例如：

```text
modules/catalog/
├── pages/
├── components/
├── hooks/
├── queries/
├── commands/
└── types/
```

领域逻辑优先留在对应 Module。

真正跨领域才提升为公共组件。

---

# 22. App 层

`App` 层只负责：

- Router
- Refine
- Providers
- Global Error Boundary
- Global Layout
- Initialization

不得承担：

- Product Business Logic
- User Operations
- Payment Logic
- Entitlement Logic

避免巨大 `App.tsx`。

---

# 23. Server State

以下 Server State：

- Users
- Orders
- Products
- Entitlements
- Redemptions
- Payments
- Audit

由：

```text
Refine
+
TanStack Query
```

管理。

不得复制到 Zustand 作为权威数据。

---

# 24. Client State

Admin UI 本地状态优先：

- React local state
- URL state
- Refine state

如果确实需要全局 Client Store：

才考虑 Workspace 已有 State Library。

不要为了和其他产品统一而强行在 Admin 中使用 Zustand。

---

# 25. URL 优先

以下状态优先保存在 URL：

- Pagination
- Filter
- Search
- Sorting
- Detail ID
- 可分享 Tab

支持：

- Refresh
- Back
- Forward
- Bookmark
- Deep Link

---

# 26. Auth

Admin 不建立第二套账号体系。

流程：

```text
account.aisenhub.com
        ↓
Platform Session
        ↓
api.aisenhub.com
        ↓
admin.aisenhub.com
```

Refine Auth Provider 只是对这一体系的 Adapter。

---

# 27. Admin Session

Admin 使用正式 Admin Session API。

例如：

```text
GET /v1/admin/session
```

返回 UI 必要信息：

- Admin Identity
- Role
- AAL / MFA State
- Session Expiry

普通 Platform User 即使登录：

也不能访问 Admin。

---

# 28. Access Control

Refine Access Control 负责：

```text
Menu
Route
Page
Button
Action Visibility
```

它只是 UX。

Backend 必须再次授权。

核心原则：

```text
Button Hidden
≠
Permission Granted
```

即使手工请求 API：

Backend 仍必须正确返回 403。

---

# 29. RBAC

第一阶段角色：

```text
owner
admin
support
finance
```

不得自行增加复杂 Role 系统。

权限采用业务 Action：

```text
applications.read
applications.change_production_origin

products.read
products.create

product_versions.publish
product_versions.retire
product_versions.set_current

redemption_batches.generate_codes

entitlements.grant
entitlements.revoke
entitlements.restore

orders.read
order_items.refund

admin_members.manage
audit_logs.read
```

---

# 30. 高风险操作

高风险 Business Command 使用统一：

```text
DangerousActionDialog
```

例如：

- Publish
- Retire
- Refund
- Grant
- Revoke
- Restore
- Generate Codes
- Change Production Origin
- Disable User
- Manage Admin Member

---

# 31. DangerousActionDialog

根据风险至少包含：

1. Target
2. Immutable ID
3. Current State
4. Target State
5. Impact Summary
6. Reason
7. MFA / AAL Status
8. Confirmation
9. Loading
10. Prevent Double Submit
11. Error State
12. requestId
13. Audit Link

极高风险操作可以要求输入：

- SKU
- Order Number
- App Slug

前端确认只防误操作。

Backend 仍必须完成真正安全验证。

---

# 32. Reason

需要 reason 的操作：

不得自动生成默认值。

禁止：

```text
reason = "admin action"
```

Reason 必须由管理员主动输入。

Backend 也必须重新验证。

---

# 33. Idempotency

Business Command 的：

```text
Idempotency-Key
```

由 Admin Client 统一处理。

不得让每个页面自行实现。

必须避免：

- double click
- retry
- timeout
- refresh

导致重复：

- refund
- entitlement
- code generation
- operation

---

# 34. Table

Admin 是高数据密度系统。

优先使用：

```text
Ant Design Table
+
Refine useTable
```

列表应优先：

- Server Pagination
- Server Sorting
- Server Filtering
- Search
- Loading
- Empty
- Error
- Deep Link

不得默认拉取大量数据到浏览器后自己过滤。

---

# 35. Form

优先：

```text
Ant Design Form
+
Refine useForm
```

必须：

- Runtime Validation
- Field Error
- Server Error
- Submit Loading
- Prevent Duplicate Submit
- Proper Reset
- Preserve Useful Input

TypeScript 不能替代表单校验。

---

# 36. Modal / Drawer

简单 Action：

优先 Ant Design Modal。

复杂 Edit / Detail：

可优先 Drawer。

如果适用：

使用 Refine：

```text
useModalForm
useDrawerForm
```

不要每个页面重新实现自己的 Modal State 框架。

---

# 37. Status

统一使用领域 Status Component。

例如：

```text
StatusTag
EntityStatus
```

基于：

```text
Ant Design Tag / Badge
```

不要在每个页面重复硬编码颜色。

例如：

```text
paid
pending
refunded
revoked
active
paused
```

必须拥有统一视觉语义。

---

# 38. Money

金额必须使用统一：

```text
MoneyDisplay
```

处理：

- currency
- minor units
- locale
- formatting

页面不得到处：

```ts
amount / 100
```

自行计算展示。

---

# 39. Date / Time

统一时间展示组件。

明确：

- UTC storage
- UI timezone
- Locale
- Relative time vs exact time

涉及：

- order
- payment
- redemption
- audit

通常应允许查看准确时间。

---

# 40. 360° 页面

关键对象优先使用聚合 API。

包括：

```text
User 360°
Order 360°
Product 360°
```

避免 Browser 查询十几个 API 后自己拼业务事实。

---

# 41. User 360°

根据权限显示：

- Profile
- Status
- Entitlements
- Grant History
- Orders
- Payments
- Refunds
- Redemption
- Feedback
- Session Summary
- Audit Timeline

Support / Finance 不应因为组件复用看到无权限字段。

---

# 42. Order 360°

典型内容：

- Order
- Order Items
- Price Snapshot
- Payment
- Payment Event
- Entitlement Grant
- Refund
- Chargeback
- Timeline
- Audit

不得从 Admin 前端自行推断订单最终状态。

---

# 43. Product 360°

典型内容：

- Product
- Stable SKU
- Versions
- Current Version
- Feature Diff
- Prices
- Redemption Batches
- Metrics
- Audit History

Published Product Version：

不得原地任意编辑。

---

# 44. Audit Timeline

使用领域组件：

```text
AuditTimeline
```

可基于：

```text
Ant Design Timeline
```

展示：

- actor
- action
- target
- reason
- requestId
- before summary
- after summary
- createdAt

Audit 只能读取。

不得：

- Edit
- Delete
- Create authoritative Audit

---

# 45. Redemption Code UI

历史兑换码不得再次完整展示。

只允许：

- code hint
- batch
- status
- redeemed user
- redeemed time

完整 Code：

只在首次生成后按照 Backend Contract 一次性处理。

禁止保存到：

- console
- analytics
- error tracker
- localStorage

---

# 46. Notification

优先使用：

```text
Ant Design message
Ant Design notification
```

或 Refine Notification Provider。

成功通知要说明：

- 做了什么
- 对哪个对象
- 最终结果

高风险操作适用时展示：

- requestId
- Audit Link
- Entity Link

不要只有：

```text
Success
```

---

# 47. Error Handling

稳定 Error Code 必须转换成可理解 UI。

例如：

```text
401
→ Session Expired

403
→ Permission Denied

MFA_REQUIRED
→ Require Authentication Elevation

409
→ State Conflict

422
→ Validation Error

429
→ Rate Limited

5xx
→ Retry / Support Information
```

禁止向用户直接显示：

- SQL Error
- Stack Trace
- Table Name
- Internal Exception

---

# 48. Loading / Empty / Error

所有生产页面必须处理：

- Loading
- Empty
- Error
- Permission Denied

优先使用统一 AisenHub Admin 状态组件。

不得只实现 Happy Path。

---

# 49. Saved Filters

列表可以参考 React-admin 的 Saved Query 思路。

只允许保存：

```text
structured filters
```

禁止：

- SQL
- arbitrary query
- client-defined database expression

---

# 50. Dashboard

Dashboard 用于：

```text
Actionable Operations Information
```

而不是漂亮 BI。

优先显示：

- Orders
- Revenue
- Refunds
- Pending Operations
- Redemption Failure
- Feedback
- Security Events
- System Health

每个重要指标应能 Drill-down 到对应列表。

第一阶段不建设自由 BI Builder。

---

# 51. Admin 不直接创建 Audit

即使 Refine 提供 Audit Provider：

也不能成为 AisenHub 权威审计来源。

正确：

```text
Business Command
↓
Backend Transaction
↓
audit_logs
```

Admin：

```text
GET Audit
```

只读展示。

---

# 52. API Contract

Admin 不自行发明 API 类型。

所有 Contract 来自：

```text
packages/contracts
```

发现 Contract 不足：

先检查 Architecture 与当前 Task。

不得在 Component 内创建临时后端协议逃避正式 Contract。

---

# 53. 测试

Admin 至少覆盖：

- Component Tests
- Data Provider Contract Tests
- RBAC Tests
- Business Command Tests
- Playwright E2E

高风险操作不得只靠人工验证。

---

# 54. Data Provider Tests

覆盖：

- pagination
- sorting
- filtering
- search
- response mapping
- error mapping
- credentials
- CSRF
- requestId

---

# 55. RBAC Tests

覆盖：

```text
owner
admin
support
finance
```

测试：

- Menu
- Route
- Page
- Button
- Action
- Direct API

必须验证：

```text
前端禁止
+
后端真正禁止
```

---

# 56. Business Command Tests

至少测试：

- missing reason
- invalid confirmation
- insufficient MFA
- forbidden role
- double submit
- retry
- timeout
- idempotency
- state conflict
- successful audit
- requestId
- cache invalidation

---

# 57. E2E

按照当前 Phase 实现范围覆盖主流程。

最终可包含：

```text
Admin Login
→ MFA
→ Create Product
→ Create Version
→ Publish
→ Set Current
→ Create Price
→ Redemption Batch
→ Generate Codes
→ User Grant
→ Revoke
→ Restore
→ Refund
→ Audit Timeline
```

未进入当前 Phase 的未来功能：

不得阻塞当前 Quality Gate。

---

# 58. 用户不承担自动化测试

不得要求用户：

- 手动测试登录
- 手动查看按钮
- 手动退款
- 手动生成测试用户
- 手动检查数据库
- 手动检查 RBAC

这些属于自动化测试职责。

用户的视觉与操作体验 Review：

属于 Optional Human Review。

---

# 59. Build

修改 Admin 后执行 Workspace 当前正式：

- format
- lint
- typecheck
- test
- build

不得另建一套平行构建体系。

---

# 60. Progress

Admin Agent 同样必须更新：

```text
docs/implementation/PROGRESS.md
docs/implementation/TASK_LEDGER.md
```

完成任务后记录：

- Task
- Tests
- Result
- Commit
- Next

---

# 61. 禁止的 Admin 技术

未经正式架构变更不得加入：

- shadcn/ui
- Material UI
- Appsmith Runtime
- ToolJet Runtime
- NocoBase Runtime
- Directus Runtime
- Low-code Builder
- Workflow Builder
- Database Editor
- SQL Builder
- Generic CMS
- Generic BI Platform

参考项目只能作为：

```text
UX / Architecture Inspiration
```

不是 Runtime Dependency。

---

# 62. Refine 不决定领域模型

必须保持：

```text
AisenHub Domain
→ 决定业务语义

Refine
→ 适配业务语义
```

禁止：

```text
Refine CRUD
→ 反向决定 Backend API
```

例如：

退款不是：

```text
Edit Order
```

而是：

```text
Refund OrderItem Command
```

---

# 63. Ant Design 不决定业务逻辑

同理：

```text
Ant Design
```

只负责：

- UI
- Interaction
- Layout
- Data Presentation

不能因为某个 Ant Design 组件方便：

就改变领域模型。

---

# 64. 架构变更

以下属于 Architecture Change：

- Admin 绕过 Platform API
- Admin 直接访问 Supabase
- 修改 Auth
- 修改 RBAC
- 修改 Query / Command 分离
- 修改 Business Command 语义
- 引入第二套数据访问
- 更换 Refine
- 更换 Ant Design
- 更改 Admin Client Contract Strategy

必须通过正式架构变更。

---

# 65. Admin 开发优先级

```text
安全边界
>
Business Command 正确性
>
权限
>
可审计性
>
错误处理
>
自动化测试
>
运营效率
>
视觉精细度
```

不要优先做：

```text
漂亮 Dashboard
```

而延后：

```text
Auth
RBAC
Command
Audit
```

---

# 66. 最终架构边界

必须始终保持：

```text
admin.aisenhub.com
        ↓
React
        ↓
Refine
        ↓
@refinedev/antd + Ant Design
        ↓
AisenHub Admin Data Provider
AisenHub Business Command Client
        ↓
/v1/admin/*
        ↓
AisenHub Platform Backend
        ↓
PostgreSQL
```

其中：

```text
Ant Design = UI Component System

Refine = Admin Frontend Framework

Admin Client = Protocol Adapter

Platform Backend = Business Authority

PostgreSQL = Fact Storage
```

任何实现都不得颠倒这一关系。

---

# 67. 最终原则

Admin 不是“数据库的漂亮前端”。

Admin 是：

> AisenHub Platform Backend 的安全运营控制界面。

因此所有实现优先考虑：

```text
操作是否安全
↓
业务状态是否正确
↓
权限是否正确
↓
是否可审计
↓
是否可追踪
↓
是否容易运营
↓
最后才是页面是否漂亮
```