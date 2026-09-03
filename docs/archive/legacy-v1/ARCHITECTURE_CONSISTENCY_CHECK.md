# AisenHub Platform 架构一致性检查

> 检查日期：2026-08-31
>
> 检查对象：[主架构](./AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md) 与 [Admin ADR](./admin架构.md)

## 结论

**通过。** Admin 架构已经合并到唯一主架构；Admin ADR 仅保留技术评估和设计依据。没有发现两份文档继续定义不同数据模型、API 权威、权限权威或实施顺序的情况。

## 检查矩阵

| 检查项 | 结果 | 依据 |
| --- | --- | --- |
| 数据模型与 Admin Action 一致 | 通过 | Product Current Version、Price、Grant/Revoke/Restore、OrderItem Refund 均有对应字段、约束和命名 Command |
| Admin API 与页面一致 | 通过 | Overview、Catalog、Commerce、Growth & Access、Customers、Platform 均有 Resource Query 或 Business Command |
| RBAC 与 API 权限一致 | 通过 | owner/admin/support/finance 使用同一业务 Action 集；Refine 只控制 UI，Backend 每次最终授权 |
| Entitlement 与 Refund 一致 | 通过 | OrderItem 以 `source_type = order_item` 产生 Grant；全额退项撤销对应 Grant；恢复创建新的 `admin_restore` Grant |
| Admin 不直接依赖数据库 | 通过 | Admin 只通过 `admin-client` 调用 `/v1/admin/*`；明确禁止 Supabase Data Provider、SQL、表结构和 Service Role Key |
| Refine 不成为业务权威 | 通过 | Refine 仅为可替换前端框架；权限、MFA、事务、幂等、状态机和 Audit 均由 Backend 负责 |
| 权威 Audit 唯一 | 通过 | Business Command 在 Backend 事务/可靠边界写 `audit_logs`；Admin 和 Refine Audit Provider 不能生成唯一权威记录 |
| 后端迁移目标成立 | 通过 | `admin-client` 只依赖 HTTP contracts；保持 `/v1/admin/*` 兼容即可迁移 PostgreSQL 或 Edge Functions 实现 |
| 实施阶段依赖合理 | 通过 | Platform 先交付下一 Admin 阶段的最小契约，Admin 随后消费；Commerce UI 在 Commerce 状态机后实施 |
| 没有引入重型基础设施 | 通过 | 未引入 OpenFGA、Workflow Engine、Kafka、Redis、微服务、Kubernetes、Event Sourcing 或 CQRS 基础设施 |

## 关键领域闭环

### Product

```text
Product
→ ProductVersion draft
→ Publish Command
→ ProductPrice
→ Set Current Command
→ products.current_version_id
```

已发布版本不可原地修改；Retire 不破坏历史快照权益。

### Entitlement

```text
Grant → active
Revoke Command → 原 Grant 变为 revoked
Restore Command → 新建 admin_restore Grant → restores_grant_id 指向原 Grant
```

不存在前端直接修改 status，也不存在原 Grant 原地复活。

### Refund

```text
Order → OrderItem → source_type=order_item 的 Entitlement Grant
                         ↓
                 OrderItem Refund Command
                         ↓
       退款状态机 + 对应 Grant 撤销 + Audit
```

多商品订单可以逐项退款，不再使用 `source_type = order / source_id = order.id`。

### Admin Security

```text
Platform Session
→ GET /v1/admin/session
→ Admin status + role
→ Business Action permission
→ MFA/AAL2（高风险）
→ Idempotency + state machine + transaction
→ Audit + requestId
```

前端 Route、菜单、按钮和二次确认只用于体验与防误操作，不替代服务端授权。

## 文档权威关系

```text
AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md
  = 唯一总体架构事实来源

admin架构.md
  = 已采纳的 Admin ADR / Technical Evaluation

ARCHITECTURE_CHANGELOG.md
  = 本次正式合并的变更记录
```
