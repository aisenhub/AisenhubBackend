# AisenHub Admin ADR：技术选型与开源借鉴矩阵

> 状态：已采纳（Accepted）；作为 Admin 技术评估与设计依据保留
>
> 适用范围：`admin.aisenhub.com`
>
> 评估日期：2026-08-31
>
> 唯一上位架构：[AisenHub Platform Backend Architecture](./AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md)
>
> 文档关系：本文件保存 Refine/React-admin/Appsmith/ToolJet/NocoBase/Directus 的比较、许可证与选型理由；数据模型、API、RBAC、安全、测试和实施顺序以唯一上位架构为准，如有冲突以上位架构为最终权威。

## 1. 最终结论

**首选 Refine，第二选择 React-admin。AisenHub Admin 不采用 Appsmith、ToolJet、NocoBase 或 Directus 作为技术底座。**

最终形态不是部署一个第三方 Admin 产品，而是在 AisenHub 仓库中开发一个自己的 React 应用：

```text
admin.aisenhub.com
        ↓
React + Refine Core + AisenHub Design System
        ↓
AisenHub Auth Provider
AisenHub Access Control Provider
AisenHub Admin Data Provider
AisenHub Business Command Client
        ↓
/v1/admin/*
        ↓
AisenHub Platform Backend
        ↓
PostgreSQL platform schema
```

这里有三个不可颠倒的权威关系：

1. Refine 只是前端开发框架，可以替换。
2. Admin UI 只负责展示、输入、确认和调用 API，不决定最终权限与业务状态。
3. Platform Backend 才是订单、支付、权益、兑换、管理员权限、事务和审计的唯一业务权威。

选择 Refine 的根本原因不是它“功能最多”，而是它的 Headless Provider 架构恰好位于低代码平台和完全手写之间：保留代码所有权，又提供 Resource、Data Provider、Auth Provider、Access Control、路由、表单、列表和查询状态等通用骨架。Refine Core 使用 MIT 许可证，并明确支持自定义 REST Data Provider、Auth Provider 和 Access Control Provider。[Refine 官方仓库](https://github.com/refinedev/refine)、[Data Provider](https://refine.dev/core/docs/data/data-provider/)、[Access Control Provider](https://refine.dev/core/docs/authorization/access-control-provider/)

## 2. 评价基线

本次评价不奖励“内置数据库、工作流、CMS、AI Builder、插件市场”等额外能力。对 AisenHub 而言，这些能力往往意味着重复后端、重复权限和新的迁移负担。

采用以下判断顺序：

1. 能否严格通过 `/v1/admin/*` 工作，而不读取 Supabase 表。
2. Supabase 迁移为自建 PostgreSQL、Edge Functions 迁移为 Node/Go 后，Admin 是否基本不变。
3. 能否把退款、发码、发布版本、赠送和撤销权益表达为 Business Command，而不是 Edit Row。
4. 是否完全自托管，且不依赖第三方 Cloud、专有编辑器或运行时数据库。
5. 是否适合 TypeScript、代码评审、自动测试和 AI 辅助长期维护。
6. 是否会引入第二套 Auth、RBAC、Audit、Workflow 或数据模型。

## 3. 总借鉴矩阵

表中“高风险”不一定表示项目本身不好，而表示它与 AisenHub 的既有边界不匹配。

| 维度 | Refine | React-admin | Appsmith | ToolJet | NocoBase | Directus |
| --- | --- | --- | --- | --- | --- | --- |
| 项目定位 | Headless React 元框架，面向 CRUD-heavy Admin/B2B | 有明确 UI 约定的 React Admin 框架 | 拖拽式内部工具平台 | 低代码应用、工作流、Agent 平台 | No-code 业务系统与全栈插件平台 | 数据库镜像、动态 API、Data Studio/CMS |
| 与 AisenHub 定位 | **高度一致**：只提供前端骨架 | **高度一致**：但 UI 和 CRUD 约定更强 | 冲突：引入第二个内部工具运行时 | 冲突：引入 Builder、DB、Workflow、权限运行时 | 冲突：引入全栈后端、数据源和工作流 | 严重冲突：核心价值就是直接映射数据库 |
| 前端技术 | React/TypeScript，Headless，可选 Ant/MUI/shadcn 等 | React/TypeScript，默认 Material UI | React 前端 + 自有可视化运行时 | React 前端 + NestJS/自有运行时 | React + Node，全栈微内核插件 | Vue Studio + Node API |
| 当前许可证 | Core MIT，风险低 | Core MIT；部分高级模块商业授权 | Community Apache-2.0；高级治理商业版 | Community AGPL-3.0；企业能力分层 | 当前仓库许可信息存在 AGPL 与“Apache+补充限制”并存，补充条款限制品牌与平台用途，风险高 | 2026 当前版为 MSCL-1.0-GPL，限制竞争用途，四年后转 GPL；非宽松开源许可 |
| 完全自托管 | 是；实际只是自己的前端构建产物 | 是；可构建为静态 SPA | 是，但需运行整套 Appsmith 服务 | 是，但需运行整套 ToolJet 服务 | 是，但需运行 NocoBase 服务和元数据 | 是，但需运行 Directus API、系统表和 Studio |
| 脱离官方 Cloud | 完全可以 | 完全可以 | Community 可以，部分治理能力需商业版 | Community 可以，部分治理能力需企业版 | 可运行，但商业插件和当前许可证形成依赖 | 可运行，但许可证、Key、Seat/Collection 分层需持续复核 |
| 社区与成熟度 | 活跃、规模大、文档新，框架仍处于较快演进 | 最成熟之一，长期维护记录和文档最佳 | 活跃且产品化成熟，但重点是低代码平台 | 活跃，但平台能力快速扩张，升级影响面较大 | 活跃、插件生态强，但产品和许可变化快 | 成熟、数据管理 UX 强，但商业与许可变化显著 |
| 文档质量 | 高；Provider、Hook、UI Integration 清晰 | **很高**；细节、示例和升级文档最完整 | 中高；偏平台配置和产品功能 | 中高；版本/套餐差异增加判断成本 | 中高；插件开发深入，但体系庞大 | 高；Data Studio、API、扩展文档成熟 |
| API-first | **10/10**；Data Provider 可完全映射自有 API | **10/10**；Data Provider 可适配 REST/GraphQL/RPC | 7/10；能接 REST，但请求存于平台配置中 | 7/10；能接 REST，但由 ToolJet Server 代理 | 4.5/10；外部 REST Data Source 当前是商业插件 | 4/10；擅长生成自己的 API，不擅长作为纯前端消费 AisenHub API |
| 是否强依赖数据库 | 否 | 否 | 平台自身依赖其数据库；应用可只接 API | 平台自身带数据库和数据源层 | 是，全栈数据层是核心 | **是**，数据库镜像是核心能力 |
| 安全边界风险 | 低；可强制所有调用经过 Platform API | 低；可强制所有调用经过 Platform API | 中高；容易顺手增加数据库 Datasource 或平台内查询 | 高；内置 DB、Datasource、Workflow 都可能绕开 Platform API | 高；自身 ACL、Workflow、Resource API 与平台重叠 | **很高**；直接接业务库会绕过 Edge/API 的命令、幂等和审计边界 |
| Business Action | **高**；自定义 Mutation 与页面容易组合 | 高；Data Provider 可扩展自定义方法和 Custom Routes | 中；能做按钮和 JS 流程，但治理分散在 Builder 配置 | 中；能做 Query/Workflow，但会形成第二个业务编排层 | 中高；Action/Workflow 强，但正因太强而重复后端 | 中；更自然的是 Collection CRUD，复杂业务动作需扩展 |
| RBAC 适配 | 高；`can(resource, action)` 可直接映射四个角色 | 高；Core `canAccess` 足够，官方细粒度 `ra-rbac` 属商业模块 | Community 仅基础角色；细粒度权限和 Audit 偏商业版 | 细粒度规则与多项治理能力有套餐边界 | ACL 很强，但会形成第二套权限权威 | Collection/Field 权限强，但围绕数据库，不是平台 Command 权限 |
| Branding | **最高**；Headless，最终完全是 AisenHub UI | 高；可改主题和 Layout，但默认 Material 痕迹较强 | Community 品牌去除/高级白标有限制 | 白标与域名可用，但与许可证/订阅绑定 | 当前补充条款限制移除多处品牌信息 | Studio 可主题化，但仍明显是 Directus 产品 |
| AI 开发友好度 | **最高**；TS 源码、Provider 接口、模块边界明确 | 很高；成熟约定、文档和示例丰富 | 中；AI 可帮写 JS，但可视化配置不利于 diff、类型和测试 | 中；Builder 配置、查询和平台运行时分散 | 中低；元数据、插件、FlowEngine 和全栈运行时复杂 | 中；扩展代码可生成，但大量行为由数据库元数据决定 |
| 部署复杂度 | 低；Vite 静态部署或轻量 Node | 低；静态 SPA/Vite/Next/Remix | 中高；需平台服务及内部持久化组件 | 中高；需平台服务、数据库和版本升级 | 高；完整 Node、DB、插件与元数据生命周期 | 中高；Node/Docker、系统表、扩展和许可管理 |
| 后端迁移影响 | **极低**；API 契约不变即可 | **极低**；API 契约不变即可 | 中；REST 可保持，但平台配置和 Session 适配需维护 | 中；同左，且服务端代理身份复杂 | 高；数据源与自身 API/ACL 耦合 | 高；它本身就是后端和数据模型的一部分 |
| 锁定风险 | 低；业务代码仍是普通 React/TS | 低到中；组件和 Hook 使用较深时迁移成本高于 Refine | 高；页面、Query、JS 和权限存于 Appsmith 模型 | 高；页面、Query、Workflow 和环境存于 ToolJet | 很高；插件、元数据、FlowEngine、商业插件 | 很高；Directus 系统表、权限、扩展和动态 API |
| 最终角色 | **技术底座** | **第二选择/设计参考** | 只借鉴运营 Dashboard 与快捷操作 UX | 只借鉴内部工具交互和多环境提示 | 只借鉴模块注册与扩展组织方式 | 只借鉴数据浏览、详情侧栏、Activity/Revisions UX |

许可证判断依据：Refine 与 React-admin Core 均为 MIT；Appsmith Community 为 Apache-2.0，但其官方定价将细粒度权限、Audit、品牌等能力放在更高套餐；ToolJet 仓库使用 AGPL-3.0；NocoBase 的 2026 `LICENSE.txt` 声明 Apache-2.0 加优先适用的补充限制，同时仓库 `package.json` 仍声明 AGPL-3.0，许可信号不统一；Directus 当前采用 MSCL-1.0-GPL，并在官方定价中设置 Seat、Collection、SSO 等层级。[Refine LICENSE](https://github.com/refinedev/refine/blob/main/LICENSE)、[React-admin LICENSE](https://github.com/marmelab/react-admin/blob/master/LICENSE.md)、[Appsmith LICENSE](https://github.com/appsmithorg/appsmith/blob/release/LICENSE)、[Appsmith Pricing](https://www.appsmith.com/pricing)、[ToolJet LICENSE](https://github.com/ToolJet/ToolJet/blob/develop/LICENSE)、[NocoBase LICENSE](https://github.com/nocobase/nocobase/blob/main/LICENSE.txt)、[Directus LICENSE](https://github.com/directus/directus/blob/main/license)、[Directus Pricing](https://directus.com/pricing)

## 4. Admin 基础能力对比

| 能力 | Refine | React-admin | Appsmith | ToolJet | NocoBase | Directus |
| --- | --- | --- | --- | --- | --- | --- |
| Resource 抽象 | 强，Resource 连接路由、菜单和 Provider | **很强且成熟**，Resource 是核心 | 弱，主要是页面、Datasource、Query | 弱，主要是 App/Page/Query | Collection/Block 抽象强但绑定自身平台 | Collection 抽象强但直接映射数据库 |
| List/Show/Create/Edit | 有基础 View 与 Hook，UI 可自由组合 | **最完整**，默认体验成熟 | 拖拽组件自行组合 | 拖拽组件自行组合 | 自动化强 | **数据库 CRUD 最强** |
| Table/Form | 支持 Ant/MUI/shadcn、React Hook Form、React Table | Material UI 体系成熟，表格/表单组件丰富 | 内置 Widget 丰富 | 内置 Widget 丰富 | Block/Field 配置丰富 | 数据布局、Field Interface 很成熟 |
| 分页/过滤/排序/搜索 | Provider 参数标准化，适合服务端实现 | **成熟且细致**，Saved Queries 值得借鉴 | 可配置，但易散落为页面 Query | 可配置，但易散落为页面 Query | 自动生成能力强 | 自动生成能力强 |
| Bulk Action | Hook 支持；需要自己限制危险批量操作 | 成熟；应只用于低风险任务 | 通过组件/JS | 通过 Query/Workflow | Action/Workflow | 批量 CRUD 强，但不符合敏感命令边界 |
| Validation | 可接 React Hook Form/Zod，服务端错误映射清晰 | 表单体系成熟，支持服务端校验映射 | JS/Widget 规则 | JS/组件规则 | Schema/Block 规则 | Field Validation 强 |
| Loading/Error/Empty | TanStack Query + UI Integration | 内置成熟 | 内置 | 内置 | 内置 | 内置 |
| Routing/i18n/Notification | Provider 化，适合自定义 | 成熟、约定更强 | 平台内置 | 平台内置 | 平台内置 | 平台内置 |
| AisenHub 采用方式 | 使用 Core Hook 和 Provider，UI 使用自己的设计系统 | 若改选则使用 Core，避免依赖 Enterprise 私有模块 | 不直接使用 | 不直接使用 | 不直接使用 | 只观察 UX |

React-admin 的 Saved Queries、过滤器、列表状态和详情导航比 Refine 更“开箱即用”，值得参考其交互，但不值得为了这些体验牺牲 Refine 的 Headless 自由度。[React-admin Data Provider](https://marmelab.com/react-admin/doc/5.4/DataProviders.html)、[Saved Queries](https://marmelab.com/react-admin/SavedQueriesList.html)

## 5. Data Layer：最重要的边界

### 5.1 推荐的数据流

```text
Page / Resource Component
        ↓
Query Hook 或 Business Command Hook
        ↓
AisenHub Admin Data Provider / Command Client
        ↓  credentials: include + CSRF + Idempotency-Key
/v1/admin/*
        ↓
Platform Backend 权限、MFA、事务、审计
```

Admin 不使用 Refine 自带 Supabase Data Provider，也不生成“表名到 REST 路径”的通用映射。应实现一个显式的 `AisenHubAdminDataProvider`：

- `getList("orders")` → `GET /v1/admin/orders`。
- `getOne("users")` → `GET /v1/admin/users/{id}`。
- `getList("auditLogs")` → `GET /v1/admin/audit-logs`。
- `create("productVersions")` → `POST /v1/admin/products/{productId}/versions`。
- 发布、退款、发码、赠送和撤销不伪装成通用 `update`，交给独立 Command Client。

Refine Data Provider 的 `custom` 方法支持非标准 REST 操作；但 AisenHub 应在其上再封装有类型的命令函数，避免页面散落 URL 字符串。[Refine REST Data Provider](https://refine.dev/core/docs/data/packages/rest-data-provider/)

### 5.2 Resource Query 与 Business Command 分离

```ts
// Resource Query：读取和普通草稿编辑
adminDataProvider.getList("products", params)
adminDataProvider.getOne("orders", { id })

// Business Command：不可逆或高风险动作
adminCommands.publishProductVersion(input)
adminCommands.generateRedemptionCodes(input)
adminCommands.grantEntitlement(input)
adminCommands.refundOrderItem(input)
```

每个 Command 都必须由 `packages/contracts` 生成或校验输入/输出类型，并自动附加：

- `credentials: include`；
- CSRF Token；
- `Idempotency-Key`；
- `requestId`；
- 稳定错误码映射；
- 超时和一次安全重试策略。

不得在 Data Provider 中放置真正的业务判断。Provider 只负责协议适配、分页/过滤映射、错误转换和缓存失效。

## 6. Authentication 与统一会话

Refine 和 React-admin 都允许自定义 Auth Provider，因此都能适配：

```text
account.aisenhub.com 登录
        ↓
api.aisenhub.com Host-only Platform Session Cookie
        ↓
admin.aisenhub.com 调用 /v1/admin/session
```

`GET /v1/admin/session` 是本方案要求 Platform Admin API 补充的专用契约：它在统一 Platform Session 之上返回当前管理员身份、角色、AAL/MFA 状态与会话到期时间；普通用户即使拥有有效平台会话，也必须在此接口被拒绝。它不建立第二套登录体系，也不向前端返回完整权限表或任何服务角色密钥。

推荐 `AisenHubAuthProvider` 行为：

| 方法 | 行为 |
| --- | --- |
| `login` | 跳转 `account.aisenhub.com`，Admin 不保存密码 |
| `check` | 调用 `/v1/admin/session`，要求管理员有效且会话满足策略 |
| `getIdentity` | 返回管理员 ID、显示名、角色、AAL、会话到期时间 |
| `logout` | 调用 Platform Session 撤销接口并跳转账号中心 |
| `onError` | 401 退出；403 展示权限拒绝；`MFA_REQUIRED` 进入升阶认证 |

Admin 不把 JWT、权限列表或服务角色密钥放入 localStorage。浏览器只持有 API Host Cookie 和内存 CSRF Token。MFA 是否满足必须由每次高风险 API 请求在服务端重新验证，不能相信 Auth Provider 的旧缓存。

## 7. Authorization 与 RBAC

Refine `accessControlProvider.can({ resource, action })` 用于控制菜单、页面和按钮，但只是 UX 层。服务端必须再次按照相同权限矩阵拒绝越权请求。Refine 官方也明确说明，配置 Access Control Provider 本身不会自动保护所有路由，需要显式使用 `CanAccess`/路由包装；因此 AisenHub 必须建立统一的受保护路由组件和自动化测试，不能依赖开发者记忆。[Refine Authorization](https://refine.dev/core/docs/guides-concepts/authorization/)

### 7.1 第一版角色矩阵

| 领域/动作 | owner | admin | support | finance |
| --- | --- | --- | --- | --- |
| Dashboard 与只读运营指标 | 允许 | 允许 | 允许 | 允许 |
| Applications / Origins | 全部 | 管理 | 只读 | 无 |
| Features / Products / Versions / Prices | 全部 | 管理 | 只读 | 只读价格 |
| Publish/Retire/Set Current Version | 允许 | 允许 | 禁止 | 禁止 |
| Redemption Batch / Generate Codes | 允许 | 允许 | 查询 | 禁止 |
| Users / Feedback | 全部 | 管理 | 管理 | 只读必要信息 |
| Grant/Revoke Entitlement | 允许 | 允许 | 允许但必须 reason + MFA | 禁止 |
| Orders / Payments | 全部 | 查询 | 查询 | 管理 |
| Refund / Chargeback | 允许 | 受策略限制 | 禁止 | 允许 + MFA |
| Admin Members | 管理 | 禁止 | 禁止 | 禁止 |
| Audit Logs | 全部 | 查询 | 查询自身相关 | 财务范围 |
| Account Deletion | 批准/执行 | 管理 | 受理 | 财务保留确认 |

权限动作使用业务语言，例如：

```text
products.read
product_versions.publish
product_versions.retire
redemption_batches.generate_codes
entitlements.grant
entitlements.revoke
order_items.refund
applications.change_production_origin
admin_members.manage
```

不要只使用 `create/update/delete`。`support` 能查看 Entitlement 不等于能修改 Grant；`finance` 能退款不等于能编辑 Order 状态。

## 8. Business Action 设计

### 8.1 标准危险操作组件

以下动作统一使用 `DangerousActionDialog`：

- Publish/Retire Product Version；
- Set Current Product Version；
- Generate Redemption Codes；
- Pause/Close Redemption Batch；
- Grant/Revoke/Restore Entitlement；
- Refund Order Item / Mark Chargeback；
- Disable User；
- Change Production Origin；
- Add/Disable Admin Member。

对话框固定包含：

1. 操作对象和不可变 ID。
2. 当前状态 → 目标状态。
3. 影响预览，例如受影响用户、价格、权益或 Origin。
4. 不可逆性与恢复方式说明。
5. 必填 `reason`，不得用默认占位值代替。
6. MFA/AAL2 状态；不足时先升阶认证。
7. 二次确认，极高风险操作要求输入 SKU、订单号或应用 Slug。
8. 自动生成 Idempotency Key，提交中禁止重复点击。
9. 成功后展示 `requestId`、Audit ID 和目标对象链接。

### 8.2 不能做成 Edit Row 的动作

| 动作 | 专用 API | 为什么不能直接编辑字段 |
| --- | --- | --- |
| 发布版本 | `POST /v1/admin/product-versions/{id}/publish` | 要冻结版本、校验 Feature/Price 并审计 |
| 设置当前版本 | `POST /v1/admin/products/{id}/set-current-version` | 要校验归属、published 状态和当前价格 |
| 生成兑换码 | `POST /v1/admin/redemption-batches/{id}/generate` | 明文只返回一次，涉及批量事务和安全下载 |
| 赠送权益 | `POST /v1/admin/users/{userId}/entitlement-grants` | 要统一 Grant 函数、来源和审计 |
| 撤销权益 | `POST /v1/admin/entitlements/{id}/revoke` | 只能追加撤销事实，不允许删除 Grant |
| 恢复权益 | `POST /v1/admin/entitlements/{id}/restore` | 必须走专用恢复事务，不允许原地改回有效状态 |
| 退款 | `POST /v1/admin/order-items/{id}/refund` | 要驱动 Payment/Order/Grant 状态机和事务 |
| 修改生产 Origin | 专用 Command | 要重新验证 Origin、风险确认和审计 |

Refine 对自定义 Action 很友好；React-admin 也允许 Data Provider 增加额外方法和 Custom Routes。Appsmith/ToolJet 虽然能把按钮绑定 Query，但逻辑容易分散在 Builder、页面 JS 和平台 Workflow 中，难以保证每个动作都复用同一个 TypeScript Command、测试和错误模型。[React-admin Custom Routes](https://marmelab.com/react-admin/CustomRoutes.html)

## 9. Admin 信息架构与运营 UX

### 9.1 一级导航

```text
Overview
Catalog
  Applications
  Origins
  Features
  Products
  Product Versions
  Prices
Commerce
  Orders
  Payments
  Refunds / Exceptions
Growth & Access
  Redemption Batches
  Redemption Codes
  Redemptions
  Entitlements
Customers
  Users
  Feedback
  Account Deletion
Platform
  Admin Members
  Audit Logs
  System Health
```

第一版不单独建立可配置插件系统。模块使用代码注册：

```ts
type AdminModule = {
  id: string;
  routes: RouteObject[];
  resources: ResourceDefinition[];
  navItems: NavItem[];
  requiredPermission: Permission;
};
```

这借鉴 NocoBase“模块注册”的思想，但不引入其微内核、动态插件安装、FlowEngine 或 Marketplace。NocoBase 的插件可同时注册前后端、数据、权限和生命周期，适合通用业务平台，却会让 AisenHub Admin 重新拥有一套后端。[NocoBase Plugin Architecture](https://docs.nocobase.com/plugin-development)

### 9.2 三类关键详情页

**User 360°**：基础资料与状态、有效权益和历史 Grant、订单/支付/退款、兑换、反馈、会话摘要、Audit Timeline，以及 Grant/Revoke/Disable 受控动作。

**Order 360°**：订单金额、OrderItem 与成交快照、Payment/外部事件摘要、每项对应 Grant、退款/拒付/异常时间线，以及可执行动作和前置条件。

**Product 360°**：稳定 SKU、当前版本、历史版本及 Feature Diff、Prices、兑换批次、销售/激活指标和发布操作历史。

这类“资源中心 + 关系 Drill-down + 时间线”的设计应借鉴 Directus Data Studio 的左到右层级、上下文 Action、Sidebar 和 Activity/Revisions 体验，但数据仍来自 AisenHub 聚合 API，不连接 Directus。[Directus Data Studio](https://directus.io/docs/user-guide/overview/data-studio-app)

### 9.3 Dashboard 原则

借鉴 Appsmith/ToolJet 的卡片、表格和快捷操作布局，但 Dashboard 只展示可行动信息：今日订单/收入/退款、待核验订单、Webhook 异常、兑换失败异常、批次风险、待处理反馈与删除请求、最近高风险操作和系统健康。

每个指标必须能 Drill-down 到带固定筛选条件的列表。第一版不建设通用 BI、自由 SQL 或任意图表 Builder。

## 10. Audit 与安全操作

Refine 自带 Audit Log Provider 概念，但它允许客户端在 CRUD 后发送日志。这不能作为 AisenHub 的权威审计，因为浏览器日志可遗漏、伪造或因网络失败丢失。[Refine Audit Log Provider](https://refine.dev/core/docs/audit-logs/audit-log-provider/)

AisenHub 的规则是：

- Admin 前端不创建权威 Audit Log；
- Business Command 在 Platform Backend 的同一事务中写 Audit；
- Admin 只通过 `GET /v1/admin/audit-logs` 读取；
- Before/After 只展示服务端脱敏摘要；
- Audit 记录不可在 Admin 中编辑或删除；
- 每个成功动作都可从 `requestId` 跳转到对应 Audit；
- 每个资源详情页显示不可变 Timeline。

## 11. Plugin、扩展与品牌策略

采用代码化 `AdminModule` 注册以及公共 `EntityPage`、`DataTable`、`FilterBar`、`Timeline`、`DangerousActionDialog`。每个领域模块提供自己的页面、Command Hook 和测试，并编译进同一个 Admin 应用。

不采用运行时插件、插件市场、拖拽业务页面、在线 JS/SQL、动态 Workflow Builder，或插件直接访问数据库。Refine Headless 允许完全使用 AisenHub 自己的品牌和 Design Token；视觉目标应是“状态清晰、风险突出、可追溯”，而不是第三方后台换 Logo。

## 12. 各项目三类结论

### 12.1 Refine

**可以直接采用**

- `@refinedev/core`；
- Resource 注册；
- Data/Auth/Access Control/Router/Notification Provider；
- TanStack Query 数据状态和缓存失效；
- List/Show/Create/Edit 基础 Hook；
- `useCustomMutation` 作为底层能力；
- Vite 静态部署方式。

**只借鉴设计思想**

- Audit Provider 的读取接口与 Timeline 组合；
- Inferencer/CLI 的脚手架思路；
- 多 UI Library 的解耦方式。

**不建议采用**

- Supabase Data Provider 直接查表；
- 客户端自动写权威 Audit；
- 自动推断数据库结构生成敏感 CRUD；
- 为当前需求购买或绑定 Refine Enterprise 能力。

### 12.2 React-admin

**可以直接采用（仅在改选第二方案时）**

- Resource、Data Provider、Auth Provider；
- List/DataTable/Form/Show；
- Filter、Saved Queries、Reference 与错误处理；
- Custom Routes 和自定义 Data Provider 方法。

**只借鉴设计思想**

- 成熟的列表筛选、批量操作和详情导航；
- 默认 Loading/Empty/Error 状态；
- Resource 与 Action 权限命名。

**不建议采用**

- 为 `ra-rbac`、Audit 等私有 Enterprise 模块形成必需依赖；
- 用通用 Edit/Delete 代替 AisenHub Business Command；
- 把默认 Material UI 外观直接当成最终品牌。

React-admin Core 是 MIT，但官方高级 RBAC 包属于 Enterprise 私有模块；第一版四角色模型可以直接用 Core `canAccess` 自行实现，不需要付费模块。[React-admin Authorization](https://marmelab.com/react-admin/Permissions.html)、[ra-rbac 说明](https://github.com/marmelab/react-admin/blob/master/docs/AuthRBAC.md)

### 12.3 Appsmith

**可以直接采用**：无。它不应成为 AisenHub Admin 运行时。

**只借鉴设计思想**

- 快捷运营 Dashboard；
- 表格旁的快速动作；
- 内部工具的低学习成本；
- API Query 调试体验。

**不建议采用**

- 拖拽 Builder 作为长期源码；
- Database Datasource；
- Appsmith 内部角色作为业务权限权威；
- Appsmith Audit 替代 Platform Audit；
- Workflow、JS Query 承载订单和权益业务；
- 为品牌、细粒度权限和审计形成商业套餐依赖。

Appsmith Community 允许自托管和 REST API，但其官方产品定位就是连接数据库/API 的低代码内部工具平台，细粒度 Access Control、Audit 和品牌能力存在套餐边界。[Appsmith 官方介绍](https://docs.appsmith.com/)、[Appsmith Pricing](https://www.appsmith.com/pricing)

### 12.4 ToolJet

**可以直接采用**：无。

**只借鉴设计思想**

- 多环境状态提示；
- 运营页面的组件库布局；
- Query 执行状态、错误与调试信息；
- 页面/组件级可见性 UX。

**不建议采用**

- ToolJet Database；
- Workflow/Agent Builder；
- ToolJet Server 作为 Platform API 代理；
- Dynamic Access Rules 作为最终权限；
- 把敏感命令存为可编辑 Query；
- 承担 AGPL 修改发布义务和企业功能依赖。

ToolJet 当前官方定位已经扩展到 App、Workflow、Agent、内置数据库和大量 Datasource，远超 AisenHub 需要的前端 Admin 框架范围。[ToolJet Platform Overview](https://docs.tooljet.ai/docs/getting-started/platform-overview/)

### 12.5 NocoBase

**可以直接采用**：无。

**只借鉴设计思想**

- 模块/插件的注册结构；
- Action 使用业务名称，而不局限 CRUD；
- Block、详情关系和权限片段的组织方式；
- 插件生命周期与模块隔离文档。

**不建议采用**

- NocoBase 作为 Admin 全栈底座；
- REST API Data Source 商业插件依赖；
- Workflow/Approval/RunJS/SQL Action；
- NocoBase ACL 替代 Platform RBAC；
- FlowEngine 和运行时 UI 配置；
- 商业插件、品牌限制和许可不确定性。

NocoBase 的 REST API Data Source 当前明确标为商业插件，而其微内核插件同时覆盖前端、后端、数据、ACL 和 Workflow；这会把 AisenHub 的模块化单体再包进另一个全栈平台。[NocoBase REST Data Source](https://docs.nocobase.com/data-sources/data-source-rest-api/)、[NocoBase Workflow](https://docs.nocobase.com/workflow)、[NocoBase ACL](https://docs.nocobase.com/plugin-development/server/acl)

### 12.6 Directus

**可以直接采用**：无。

**只借鉴设计思想**

- Collection 列表密度和字段展示；
- Bookmark Preset/Saved Filter；
- 左到右层级导航和详情 Sidebar；
- Activity、Revision、Before/After Diff；
- 关系数据 Drill-down；
- 上下文 Action 布局。

**不建议采用**

- Directus 直接连接 AisenHub PostgreSQL；
- 动态 REST/GraphQL API 替代 `/v1/admin/*`；
- Directus Role/Policy 取代 Admin RBAC；
- Flow、Extension Service 承载订单/权益事务；
- Directus 系统表进入平台数据库；
- 依赖当前 MSCL、License Key、Seat 和 Collection 套餐。

Directus 的动态 API 会根据数据库 Schema 自动生成接口，这正是 AisenHub 敏感领域需要避免的路径。[Directus API Reference](https://directus.io/docs/api)、[Directus Permissions](https://directus.io/docs/user-guide/user-management/permissions)

## 13. 能力来源决策表

| AisenHub 能力 | 推荐来源 | 决策 |
| --- | --- | --- |
| Resource | Refine Core | 直接采用注册与路由骨架 |
| Data Provider | Refine + AisenHub 自研 Adapter | 只调用 `/v1/admin/*` |
| Auth Provider | Refine + AisenHub 自研 | 适配 Platform Session，不存 JWT |
| Access Control | Refine Provider + Platform API | UI 隐藏/提示；服务端最终授权 |
| CRUD 页面 | Refine Hook + AisenHub 组件 | 仅用于草稿和低风险资源操作 |
| Business Actions | AisenHub 自研 | 有类型 Command、MFA、reason、幂等、事务、审计 |
| Table/Form | AisenHub Design System，可基于 Ant/MUI/shadcn | 不把 UI Library 变成业务依赖 |
| Filter/Saved Views | 借鉴 React-admin | 服务端过滤，保存个人视图而非自由 SQL |
| Dashboard UX | 借鉴 Appsmith/ToolJet | 只做可行动指标和 Drill-down |
| User/Order/Product 360° | AisenHub 自研 | 聚合 API 返回运营视图 |
| Audit | AisenHub Backend + Admin 只读 UI | 后端同事务写入，前端不造审计 |
| Timeline/Revisions UX | 借鉴 Directus | 展示不可变历史和 Before/After 摘要 |
| 模块注册 | 借鉴 NocoBase | 代码化 `AdminModule`，不做运行时插件 |
| RBAC | AisenHub 四角色模型 | 不引入 OpenFGA，不依赖框架商业 RBAC |
| Branding | AisenHub Design System | 完全自有 `admin.aisenhub.com` 外观 |
| Deployment | Vite 静态构建 | Vercel/Cloudflare/VPS/Coolify/Docker 均可 |

## 14. 禁止借鉴清单

| 禁止能力 | 原因 |
| --- | --- |
| 通用 Database Table Editor | 绕过业务状态机、受控函数、reason、MFA 和审计 |
| SQL Query Builder / 在线 SQL 控制台 | 扩大数据泄露和误操作范围，无法做稳定 API 契约 |
| Low-code App Builder | 页面逻辑离开 TypeScript 源码、Review、测试和 AI 可理解边界 |
| Workflow Engine | 与 Platform 事务重复，产生两个业务权威和失败恢复模型 |
| Plugin Marketplace | 引入供应链、运行时代码和权限风险，当前没有真实需求 |
| Multi-tenant Admin Builder | AisenHub Admin 是自用运营系统，不是对外平台产品 |
| 通用 CMS | 产品目录不是内容管理系统，已发布版本有更严格不可变约束 |
| 通用 BI / 自由图表 Builder | 第一版只需要固定运营指标与 Drill-down |
| 内建数据库 | PostgreSQL Platform 已是唯一事实来源，不能再同步第二份数据 |
| 第二套 Auth/RBAC | Admin 权限必须来自 Platform Session 与 `admin_members` |
| 客户端权威 Audit | 浏览器事件可能丢失或伪造，必须由后端事务写入 |
| 前端直接改 Status | Status 是状态机结果，不是普通可编辑字段 |
| 绕过 `/v1/admin/*` | 会破坏迁移能力、安全边界和后端可替换性 |
| 保存服务角色密钥/API Secret | 浏览器和 Admin 配置不得拥有平台服务凭据 |

## 15. 推荐代码结构

```text
apps/admin/
├─ src/
│  ├─ app/                         Refine、Router、Error Boundary
│  ├─ providers/
│  │  ├─ auth-provider.ts
│  │  ├─ access-control-provider.ts
│  │  ├─ admin-data-provider.ts
│  │  └─ notification-provider.ts
│  ├─ commands/                    有类型 Business Command Client
│  ├─ modules/
│  │  ├─ overview/
│  │  ├─ catalog/
│  │  ├─ commerce/
│  │  ├─ redemption/
│  │  ├─ customers/
│  │  └─ governance/
│  ├─ components/
│  │  ├─ data-table/
│  │  ├─ filter-bar/
│  │  ├─ entity-page/
│  │  ├─ audit-timeline/
│  │  └─ dangerous-action-dialog/
│  ├─ permissions/
│  └─ testing/
packages/
├─ platform-client/                普通产品与 account 的平台客户端
├─ admin-client/                   Data Provider 与 Command Client
├─ contracts/                      API Schema、错误码、权限动作
├─ design-system/                  Token 与共享运营组件
└─ config/                         工具链共享配置
```

`packages/admin-client` 不依赖 Supabase SDK，只依赖 HTTP 契约。这样未来后端从 Edge Functions 改为 Node/Go 时，只要 `/v1/admin/*` 契约保持兼容，Admin 无需知道数据库和服务实现已改变。

## 16. 测试策略

### 16.1 Provider 契约测试

- 分页、筛选、排序和搜索参数映射；
- API 响应到 Refine 数据结构的转换；
- 401/403/409/422/429/5xx 稳定错误映射；
- Cookie、CSRF、Request ID 和 Idempotency-Key；
- 后端切换实现后，同一契约测试可复用。

### 16.2 权限测试

- owner/admin/support/finance 的菜单、路由、按钮矩阵；
- 直接输入 URL 不能绕过页面保护；
- 隐藏按钮后手工调用 API 仍由后端拒绝；
- MFA 不足时只允许进入升阶流程；
- 权限更新后缓存及时失效。

### 16.3 Business Action 测试

- reason 为空不能提交；
- 二次确认内容错误不能提交；
- 双击、刷新和超时重试不产生重复结果；
- 成功后相关 List/Detail/Timeline 缓存失效；
- 状态迁移失败展示可行动错误，不暴露 SQL/堆栈；
- Audit ID 和 Request ID 可追踪。

### 16.4 E2E

```text
Admin 登录 → MFA → 发布 Product Version → 设置 Current Version
创建 Price → 创建 Redemption Batch → 生成并一次性下载兑换码
查询 User 360° → Grant → Revoke → Restore
查询 Order 360° → 按 OrderItem 退款 → 验证 Grant 撤销和 Audit Timeline
```

## 17. 实施阶段

### Admin Phase A：安全壳与只读运营

- Refine Core、Router、Design System；
- Auth/Access Control/Data Provider；
- Dashboard、只读 Applications/Users/Orders/Audit；
- 四角色矩阵和路由测试。

验收：Admin 不连接 Supabase Data API；所有请求只走 `/v1/admin/*`。

### Admin Phase B：Catalog 与 Redemption

- Applications、Origins、Features；
- Products、Versions、Prices；
- Publish/Retire/Set Current；
- Redemption Batch、Generate/Pause/Close；
- Dangerous Action 标准组件。

验收：任何高风险操作都有 MFA、reason、二次确认、幂等和 Audit。

### Admin Phase C：Customer Operations

- User 360°；
- Feedback；
- Entitlement Grant/Revoke/Restore；
- Disable User；
- Account Deletion 请求和去标识化进度。

### Admin Phase D：Commerce Operations

- Order/Payment 360°；
- 人工核验；
- OrderItem Refund；
- Chargeback 和异常事件队列；
- Finance 角色视图。

### Admin Phase E：运营效率

- Saved Filters；
- 固定报表与 Drill-down；
- 异常告警入口；
- 批量低风险动作；
- 性能、可访问性和快捷键优化。

第一版不要反过来从“做一个漂亮 Dashboard”开始。优先顺序应是安全壳 → 资源详情 → 业务动作 → 审计追踪 → 指标效率。

## 18. 加权评分

评分中的 `License 安全` 和 `Lock-in 安全` 均为分数越高风险越低。

权重不是简单平均：API-first 15%、可迁移性 13%、Business Action 13%、自托管 10%、AI 开发友好 10%、长期维护 10%、技术适配 7%、自定义 6%、开发效率 5%、RBAC 4%、License 安全 4%、Lock-in 安全 3%。

| 维度 | Refine | React-admin | Appsmith | ToolJet | NocoBase | Directus |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 技术适配 | 9.5 | 9.0 | 5.5 | 4.5 | 4.0 | 3.5 |
| 自托管 | 10.0 | 10.0 | 8.0 | 7.5 | 7.0 | 7.0 |
| 可迁移性 | 9.5 | 9.5 | 6.0 | 5.5 | 4.0 | 3.5 |
| 自定义能力 | 9.5 | 8.5 | 7.0 | 6.5 | 8.0 | 7.0 |
| API-first | 10.0 | 10.0 | 7.0 | 7.0 | 4.5 | 4.0 |
| Business Action 适配 | 9.0 | 8.5 | 6.5 | 6.5 | 7.0 | 5.0 |
| RBAC | 8.5 | 7.0 | 5.5 | 6.0 | 7.0 | 8.0 |
| 开发效率 | 9.0 | 9.0 | 8.0 | 8.0 | 7.0 | 8.0 |
| AI 开发友好 | 9.5 | 9.0 | 5.5 | 5.0 | 4.5 | 5.5 |
| 长期维护 | 9.0 | 9.5 | 6.0 | 5.5 | 4.5 | 5.0 |
| License 安全 | 10.0 | 8.5 | 8.5 | 5.5 | 2.5 | 2.0 |
| Vendor Lock-in 安全 | 9.5 | 8.5 | 4.5 | 4.0 | 3.0 | 2.5 |
| **AisenHub Suitability Score** | **9.46** | **9.15** | **6.53** | **6.09** | **5.29** | **5.00** |

## 19. 最终推荐答复

### 19.1 最适合作为基础的是谁？

**Refine。**

它能直接提供 AisenHub 需要的前端生产力，又不会接管数据库、Auth、业务事务或部署。Headless 架构也最有利于形成真正的 AisenHub 品牌和长期 AI 辅助代码维护。

### 19.2 第二选择是谁？

**React-admin。**

只有在团队更重视成熟、强约定的 Material UI Admin 组件，并愿意接受更深的框架 UI 绑定时改选。即使改选，也只使用 MIT Core，自行对接 Platform RBAC 和 Business Command，不把 Enterprise 私有模块变成安全必需项。

### 19.3 其余项目主要借鉴什么？

- Appsmith：运营 Dashboard、快捷动作和低学习成本。
- ToolJet：Query 状态、多环境提示和内部工具交互。
- NocoBase：代码模块注册、业务 Action 命名和插件组织思想。
- Directus：高密度数据管理、关系 Drill-down、详情 Sidebar、Activity/Revisions。

### 19.4 哪些不适合作为技术底座？

Appsmith、ToolJet、NocoBase、Directus 均不适合。前两者是低代码运行平台，后两者同时承担后端/数据库抽象；它们都会把 Admin Framework 变成第二个平台，并增加权限、审计、迁移和许可证风险。

### 19.5 最终原则

```text
Admin Framework 可替换
Admin Design System 归 AisenHub
Admin API Contract 归 AisenHub
Business Command 归 Platform Backend
PostgreSQL 是事实存储
Platform Backend 是唯一业务权威
```

只要守住这条边界，未来无论 Admin 从 Refine 换成 React-admin/纯 React，还是后端从 Supabase Edge Functions 换成 Node/Go，订单、权益、兑换和运营流程都不需要重新设计。
