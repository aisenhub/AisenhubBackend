# AisenHub Platform Architecture Changelog

## 2026-09-03 — V2 adopted

`AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md` is now the active
architecture authority. The former backend architecture, Admin architecture,
consistency check, and V1 implementation records are retained under
`archive/legacy-v1/` for historical reference only.

> 日期：2026-08-31
>
> 变更：将 Admin ADR 正式合并到 AisenHub Platform 唯一总体架构
>
> 权威文档：[AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md](./AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md)

## Added

- 正式确定 `apps/admin` 使用 React + Refine Core + AisenHub Design System。
- 增加 `packages/platform-client`、`packages/admin-client`、`packages/design-system` 及单向依赖规则。
- 增加 `AisenHubAuthProvider`、`AisenHubAccessControlProvider`、`AisenHubAdminDataProvider`、`AisenHubBusinessCommandClient` 的职责边界。
- 增加 `GET /v1/admin/session`，返回最小 Admin identity、role、AAL/MFA 和 session expiry。
- 将 Platform Admin API 分为 Resource Query 与 Business Command。
- 增加 Applications、Catalog、Users、Orders、Payments、Redemption、Entitlements、Feedback、Account Deletion、Admin Members、Audit 和 System Health 的 Admin Query 契约。
- 增加 User 360°、Order 360°、Product 360° 聚合读取 API；不增加第二套数据存储。
- 增加 Publish、Retire、Set Current、Generate/Pause/Close Codes、Grant/Revoke/Restore、Refund、Disable、Production Origin 和 Admin Member 等命名 Command。
- 增加统一危险操作协议：管理员有效、业务权限、AAL2/MFA、reason、Idempotency-Key、状态机、数据库事务、Audit、requestId 和稳定错误码。
- 增加 Admin 信息架构、四角色矩阵、Audit Timeline 和 DangerousActionDialog 的后端要求。
- 增加 Admin Provider、RBAC、Business Command 和 Admin E2E 测试要求。
- 增加 Managed PostgreSQL → Self-hosted PostgreSQL 与 Edge Functions → Node/Go 的迁移验证场景。
- 增加交错的 Platform/Admin 实施阶段，避免 UI 与 Backend 长期脱节。

## Changed

- 将原 `packages/client` 正式命名为 `packages/platform-client`，并将 Admin 能力隔离到 `packages/admin-client`。
- 将 `contracts` 明确为 API 请求、响应、错误码、分页结构和权限 Action 的唯一类型来源。
- 将 Administration 模块扩展为 Admin Members、Roles、Permissions、Admin Session、MFA/AAL 与 Administrative Commands。
- 将 `admin_members` 明确为固定 `owner / admin / support / finance` RBAC，补充 status、created_by、disabled_at 和时间字段；第一版不建立通用权限引擎。
- 将原少量 `/v1/admin/*` 路由扩展为与 Admin 页面一一对应的 Query/Command 契约。
- 将原“管理后台与 AisenLens 切换”单一阶段拆分为 Admin Phase A–E，并与 Platform Phase 0–2、Commerce 和工具接入阶段协调。
- 将 Admin Audit 明确为只读展示；权威 Audit 必须由 Backend 在业务事务或可靠事务边界中写入。
- 将 `admin架构.md` 重新定义为已采纳的 Admin ADR / Technical Evaluation；总体事实由主架构统一定义。

## Removed

- 移除 Admin 可被实现为通用 CRUD/数据库表编辑器的模糊空间。
- 移除 Admin 直接依赖 Supabase Data API、Refine Supabase Data Provider、PostgreSQL 表结构或数据库函数名的允许空间。
- 移除使用通用 `PATCH status`、Refine `update()` 或 `delete()` 伪装高风险领域动作的允许空间。
- 移除客户端权限缓存、隐藏按钮或 Refine Audit Provider 可成为后端授权/权威审计的歧义。
- 没有删除既有 App、Feature、Product、ProductVersion、Price、OrderItem、Entitlement、Redemption、Account Deletion 或 Audit 数据模型。

## Deferred

- OpenFGA、Workflow Engine、Kafka、Redis、微服务、Kubernetes、Event Sourcing、CQRS 基础设施继续不引入。
- Plugin Marketplace、Low-code Builder、通用 CMS、通用 BI、自由 SQL 和动态 Workflow Builder 继续不引入。
- 复杂 Offer/Promotion、用量计费、额度账本、独立域名 OAuth 和外部不可变审计归档仍按主架构中的现实门槛延后。
- 正式收款前仍需确定支付渠道、销售条款、部分退款商业语义和法定数据保留期限。

## Merge Conflict Resolution

| 检查项 | 合并前状态 | 最终裁决 |
| --- | --- | --- |
| Product Version / Current Version | 主架构已存在 | 保留 `products.current_version_id`；Publish、Retire、Set Current 使用命名 Command |
| Prices | 主架构已有 `product_prices` | Admin 只管理独立 Price，不引入 Offer 引擎 |
| Entitlement Restore | 主架构已定义新建 `admin_restore` Grant | 保留原 Grant 为 revoked，新 Grant 通过 `restores_grant_id` 关联 |
| OrderItem Refund | 主架构已按 OrderItem 追踪 | 退款 Command 固定作用于 OrderItem，Grant 来源保持 `order_item` |
| Admin Roles | 两文档均为四角色 | 固定 owner/admin/support/finance，不增加 OpenFGA |
| Admin Session | 主架构缺失 | 正式增加 `GET /v1/admin/session` |
| Admin API | 主架构只有少量写接口 | 扩展为 Resource Query、Overview Query 和 Business Command |
| Account Deletion | 主架构已有状态机 | 增加 Admin 查询、受理和处理入口，不改变状态模型 |
| Audit | 主架构已有追加式日志 | 明确 Backend 权威、Admin 只读、Timeline 使用脱敏摘要 |
| System Health | Admin IA 有、主架构 API 缺失 | 增加只读 `GET /v1/admin/system-health` |
| admin-client / design-system | 主仓库结构缺失 | 正式加入并定义禁止循环依赖 |

本次合并没有新增技术待确认项。仍保留的 TODO 都属于原主架构已列出的产品和商业决策。
