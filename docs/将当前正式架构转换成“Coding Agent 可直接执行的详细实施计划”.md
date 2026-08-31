现在 AisenHub Platform 总体架构已经确定。

下一步不要继续优化架构，也不要开始直接写业务代码。

你的任务是：

# 将当前正式架构转换成“Coding Agent 可直接执行的详细实施计划”

目标不是给人看的项目计划，而是给 AI Coding Agent / Codex / Claude Code 等开发 Agent 使用的施工计划。

最重要的目标：

> 尽可能减少开发过程中对我的询问和人工参与。

除非遇到明确的 Human Gate，否则 Agent 应自主执行、测试、修复和继续下一任务。

---

# 一、唯一架构依据

以当前正式版本：

`docs/AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md`

作为唯一总体架构事实来源。

Admin 部分参考：

`docs/admin架构.md`

但如果两者冲突：

`AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md`

优先。

不要重新设计架构。

不要自行改变：

- 数据模型
- API 边界
- Auth 模型
- Entitlement 模型
- Admin 安全边界
- Query / Command 分离
- Refine 技术选择
- Supabase + PostgreSQL + RLS + Edge Functions 的第一阶段技术路线

如果实施过程中发现真正的架构阻塞问题：

不得由执行 Agent静默修改架构。

必须创建：

`ARCHITECTURE_BLOCKER`

并说明：

- 当前架构规定
- 实现为什么无法继续
- 最小修改建议
- 影响范围

只有这种情况才升级到架构层。

---

# 二、总体执行原则：Autonomous First

请把整个实施计划按照：

`AUTONOMOUS`
`HUMAN_GATE`
`BLOCKED`

三种状态设计。

默认必须是：

`AUTONOMOUS`

也就是说，如果 Agent 可以通过以下方式自行解决：

- 阅读现有代码
- 阅读架构文档
- 查看官方文档
- 安装开发依赖
- 修改代码
- 创建本地配置
- 启动 Docker
- 启动 Supabase Local
- 创建 migration
- 创建 seed
- 写测试
- 运行测试
- Debug
- 修复 lint
- 修复 typecheck
- 修复测试
- 调整实现但不改变架构
- 创建模拟数据
- 使用测试用户
- 使用本地环境
- 创建本地开发证书
- 使用 Playwright 自动操作浏览器

就不得询问我。

禁止执行 Agent 遇到普通开发问题时问：

“你希望我怎么做？”

它应该依据：

架构
→ 现有代码
→ 测试
→ 最小复杂度原则

自主决定。

---

# 三、什么情况下才允许 Human Gate

请严格限制 Human Gate。

只有以下类型允许要求我介入：

## H1 外部账户认证

例如：

- Supabase Cloud 登录
- Cloudflare 登录
- Vercel 登录
- GitHub 权限授权
- 支付平台账户授权

如果 Agent 已经拥有有效授权，则不得再次询问。

---

## H2 Secret / Credential

例如：

- Supabase Access Token
- Production Project Ref
- Database Password
- Webhook Secret
- OAuth Secret
- Payment Secret

Agent 不得让我把 Secret 写入聊天或代码。

应告诉我：

“请在指定 Secret Manager / Environment 中配置变量 XXX。”

然后 Agent自行验证变量是否存在。

---

## H3 外部资源创建

例如：

- 创建 Supabase Staging Project
- 创建 Production Project
- 创建 Vercel Project
- 创建 Cloudflare DNS Record

如果 Agent 拥有对应 API/CLI 权限，可以自行创建。

只有权限不足时才触发 Human Gate。

---

## H4 域名 / DNS

例如：

- `api.aisenhub.com`
- `account.aisenhub.com`
- `admin.aisenhub.com`

需要真实 DNS 修改时才触发。

本地开发不得因此阻塞。

应使用：

localhost
或本地测试 Origin

继续完成绝大部分开发。

---

## H5 Product Decision

只有真正属于商业承诺的问题才可以询问，例如：

- 正式价格
- 买断是否包含未来版本
- Refund Policy
- 全站版是否包含未来工具

普通技术问题不是 Product Decision。

---

## H6 Production Risk

以下行为必须在生产执行前触发 Human Gate：

- Production migration
- 删除生产数据
- Production Secret 变更
- Production DNS 变更
- 正式支付切换
- 大规模权益变更

Staging 和 Local 不应因为 Production Gate 阻塞。

---

# 四、特别处理 Supabase

实施计划必须把 Supabase 分成三个层级：

## Local Supabase

目标：

**完全不需要我参与。**

Agent 应自行：

- 检查 Docker
- 检查 Supabase CLI
- 安装缺失开发依赖
- `supabase start`
- reset database
- migration
- seed
- Auth test users
- RLS tests
- SQL tests
- Edge Functions
- Type generation
- API tests
- E2E

如果 Local Supabase 可以完成验证，不允许因为没有 Cloud Project 就暂停。

---

## Staging Supabase

只有完成 Local 阶段后才进入。

如果已经存在：

- Access Token
- Project Ref
- Environment Variables

Agent 自动连接和部署。

如果缺失：

触发一个 Human Gate。

要求必须一次性列出所有需要我的内容。

禁止：

今天问一个 Project Ref，
明天再问一个 Token，
后天再问一个 Secret。

必须批量列出。

---

## Production Supabase

在：

Local
+
Staging

全部通过之后才能进入。

Production 永远作为明确 Gate。

在我确认之前：

Agent 只能生成：

- migration plan
- deployment command
- smoke checklist
- rollback/recovery plan

不得自行执行高风险生产变更。

---

# 五、计划必须拆成 Atomic Tasks

不要只输出：

“Phase 1 实现 Auth。”

这无法让 Agent 稳定执行。

必须拆成原子任务。

每个 Task 必须拥有唯一 ID，例如：

```text
P0-T001
P0-T002

P1-T001
P1-T002

ADM-A-T001
```

每个任务必须包含：

```text
Task ID
Title
Phase
Type
Dependencies
Architecture References
Goal
Inputs
Files to inspect
Files to create
Files to modify
Implementation Steps
Commands
Automated Tests
Acceptance Criteria
Failure Recovery
Do Not
Outputs
Next Task
Human Gate
Commit Boundary
```

---

# 六、Task 粒度

一个 Task 应该只完成一个清晰目标。

错误示例：

```text
实现整个用户系统
```

正确示例：

```text
P1-T003
创建 profiles migration 与约束
```

然后：

```text
P1-T004
创建 profiles RLS
```

然后：

```text
P1-T005
编写 profiles RLS allow/deny tests
```

然后：

```text
P1-T006
创建 profile API contract
```

任务应该足够小，使 Agent：

执行
→ 测试
→ 验收
→ commit
→ 下一项

不会在一个任务里修改半个项目。

---

# 七、每个任务必须提供 Architecture References

例如：

```text
Architecture References:

AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md
- §8.2 profiles
- §13.3 RLS
- §16.1 Database Tests
```

这样 Coding Agent 不需要重新理解整个架构。

如果 Task 涉及 Admin：

同时引用：

```text
admin架构.md
- §5 Data Layer
- §7 RBAC
```

---

# 八、每个任务必须明确自动验收标准

禁止：

“确认功能正常。”

必须是机器可以判断的条件。

例如：

```text
Acceptance Criteria:

- supabase db reset exits 0
- profiles table exists
- authenticated user can SELECT own profile
- authenticated user cannot SELECT another profile
- anon cannot SELECT private profile
- npm run typecheck exits 0
- npm test exits 0
```

Agent 应在进入下一 Task 前自动执行验收。

失败：

自行修复。

修复后：

重新执行。

只有连续无法解决且属于架构阻塞时才升级。

---

# 九、建立 Quality Gate

每一阶段结束必须执行统一 Gate。

至少：

```text
format
lint
typecheck
unit tests
database tests
RLS tests
API contract tests
integration tests
build
```

适用时增加：

```text
Playwright E2E
Supabase local reset
Edge Function tests
```

所有 Gate 通过：

才能进入下一阶段。

---

# 十、测试优先

对于以下高风险领域：

- RLS
- Redemption
- Entitlement
- Session
- CSRF
- CORS
- Idempotency
- Refund
- Admin Permission

优先：

先写失败测试
→ 实现
→ 测试通过

尤其兑换系统必须自动覆盖：

```text
valid redemption
invalid redemption
expired code
paused batch
same code concurrent redemption
same request retry
same user retry
different user retry
per-user limit
grant creation
audit creation
transaction rollback
```

不要依赖人工点击确认。

---

# 十一、第一阶段目标：Zero-Human Local Foundation

请专门规划一个：

# Autonomous Bootstrap Stage

目标：

在第一次询问我之前，Agent 应尽可能完成：

```text
Repository structure
Package workspace
Tooling
Supabase Local
Baseline migration
Schemas
Seed
Contracts skeleton
Client skeleton
Database type generation
RLS test infrastructure
Database test infrastructure
Edge Function test infrastructure
CI
Local environment documentation
```

理想验收：

```text
一条命令：

pnpm platform:verify
```

或等价命令可以：

```text
start/check local Supabase
reset database
apply migrations
seed
generate types
run SQL tests
run RLS tests
run unit tests
run contract tests
typecheck
lint
build
```

全部成功。

在这个 Gate 之前：

原则上不得要求我参与。

---

# 十二、第二阶段仍然尽量 Local

Identity / Application / Session：

优先使用 Local Supabase Auth。

Agent 自动：

- 创建测试账号
- 登录
- session exchange
- Cookie tests
- CSRF tests
- CORS tests
- app origin tests
- logout
- revoke
- multi-session tests

浏览器流程使用：

Playwright

自动完成。

不要把“需要我手动登录看看”作为验收标准。

---

# 十三、Catalog / Entitlement / Redemption 仍然完全自动

在 Local 环境完成：

- applications
- origins
- features
- products
- product versions
- prices
- entitlements
- redemption
- audit

使用 Seed 创建测试数据。

使用测试用户：

```text
owner
admin
support
finance
normal-user
```

自动覆盖权限矩阵。

这一阶段也原则上不需要我参与。

---

# 十四、Admin 第一阶段也自动化

Refine Admin：

Agent 自行完成：

- project scaffold
- Router
- Auth Provider
- Access Control Provider
- Admin Data Provider
- Command Client
- Design System 基础组件
- Protected Routes
- Error Boundary
- Notification
- test infrastructure

然后使用本地 Platform API 测试。

不允许 Admin 直接访问 Supabase Data API。

使用 Playwright 测试：

```text
owner
admin
support
finance
```

对应：

菜单
Route
Button
API

权限。

---

# 十五、Human Interaction Budget

在执行计划中增加一个指标：

`Human Interaction Budget`

目标：

### Local Foundation
0 次

### Core Platform Local
0 次

### Admin Local
0 次

### Staging Bootstrap
最多 1 次集中 Human Gate

### Production
明确单独 Gate

如果某个 Phase 被规划出大量 Human Gate：

重新设计实施步骤。

优先通过：

local
mock
seed
test fixture
CLI
automation

消除人工参与。

---

# 十六、不要让我做可以自动化的“测试”

以下不是合理 Human Gate：

- “请打开页面看看”
- “请点击登录试试”
- “请兑换一个码”
- “请看看 Admin 页面有没有显示”
- “请创建测试用户”
- “请检查数据库有没有记录”
- “请看看按钮有没有隐藏”
- “请测试退款”

这些必须由：

unit test
integration test
SQL test
Playwright
API test

完成。

只有最终 UX 主观验收可以列为：

Optional Human Review

不能阻塞 Agent 执行。

---

# 十七、Agent 遇到失败时的行为

必须写进 Execution Rules：

```text
执行 Task
↓
测试
↓
失败
↓
读取错误
↓
定位
↓
修复
↓
重新测试
```

默认允许至少多轮自修复。

不得第一次测试失败就询问我。

只有：

1. 缺少外部 Credential；
2. 缺少权限；
3. 架构自身矛盾；
4. 需要产品商业决策；
5. Production 高风险操作；

才允许暂停。

---

# 十八、Git / Commit 策略

每一个完整 Atomic Task 或紧密关联 Task Group 完成后：

创建清晰 Commit。

例如：

```text
feat(db): add application schema
test(db): add application RLS coverage
feat(session): add platform session exchange
feat(admin): add Refine auth provider
```

不要让 Agent 完成整个 Phase 后一次 commit。

每个阶段结束打：

checkpoint。

这样失败时容易回退。

---

# 十九、计划依赖图

除了线性任务列表，还必须生成 DAG。

例如：

```text
P0-T001
   ↓
P0-T002
   ↓
P0-T003
  ↙   ↘
DB     Contracts
 ↓        ↓
Tests   Client
  ↘      ↙
   Phase Gate
```

明确：

哪些任务可以并行。

如果未来多个 Agent 同时开发，可以避免修改冲突。

同时标注：

```text
parallel_safe: true/false
```

---

# 二十、多 Agent 可执行性

计划应允许未来将任务分给多个 Agent。

建议分 Track：

```text
Track A — Database
Track B — API / Edge Functions
Track C — Contracts / Clients
Track D — Account UI
Track E — Admin UI
Track F — Tests / Security
Track G — DevOps
```

但是每个 Track 必须共享统一 contracts。

不得让不同 Agent 自己发明不同 API。

---

# 二十一、生成专门的 Agent Execution Rules

请输出：

`docs/implementation/AGENT_EXECUTION_RULES.md`

包括：

- 架构优先级
- autonomous-first
- human gate rules
- test-before-next-task
- no architecture drift
- no secret in code
- no production destructive operation
- no silent scope expansion
- no dependency substitution without reason
- no TODO replacing required functionality
- commit rules
- quality gates
- blocker escalation

Coding Agent 每次执行任务前必须先阅读这个文件。

---

# 二十二、生成 Human Gates 文件

创建：

`docs/implementation/HUMAN_GATES.md`

提前列出预计可能需要我的事情。

例如：

```text
HG-001
Stage: Staging Bootstrap
Reason: Connect Supabase Staging Project

Needed:
- Supabase project authorization
- Environment variables availability

Agent must first verify:
- whether CLI is already authenticated
- whether project already exists
- whether env already contains required values

Only trigger if missing.
```

我的目标是：

**在开发开始前就知道未来大概什么时候会找我，而不是开发过程中随机出现问题。**

---

# 二十三、生成 Master Plan

创建：

`docs/implementation/MASTER_PLAN.md`

至少包含：

- Overall Goal
- Architecture Sources
- Execution Principles
- Phase Map
- Dependency Graph
- Human Gates
- Quality Gates
- Completion Definition

然后为每阶段创建：

```text
docs/implementation/phases/

00-bootstrap.md
01-identity-application-session.md
02-catalog-entitlement-redemption.md
03-admin-foundation.md
04-account-and-product-integration.md
05-commerce.md
06-staging.md
07-production-readiness.md
```

阶段编号应根据正式架构实际调整。

不要机械沿用这个示例，如果依赖关系不合理。

---

# 二十四、每个 Phase 文件的任务格式

严格统一：

```markdown
## P1-T001 — Task Title

Status: pending
Execution: AUTONOMOUS
Parallel Safe: yes/no

### Architecture References

### Dependencies

### Goal

### Inputs

### Files To Inspect

### Files To Create

### Files To Modify

### Implementation Steps

1.
2.
3.

### Commands

```bash
...
```

### Tests

### Acceptance Criteria

- [ ] ...

### Failure Recovery

### Do Not

### Output

### Commit

### Next
```

Human Gate Task：

```text
Execution: HUMAN_GATE
```

并且明确：

Agent 在 Gate 之前应该已经完成什么。

---

# 二十五、Definition of Done

整个第一版 Platform 完成不等于：

“代码写完”。

必须同时满足：

- Local rebuild deterministic
- migrations reproducible
- seed deterministic
- database tests pass
- RLS tests pass
- Edge/API tests pass
- contract tests pass
- SDK tests pass
- Admin RBAC tests pass
- redemption concurrency tests pass
- idempotency tests pass
- E2E pass
- build pass
- documentation matches implementation
- no secret committed
- no Admin direct DB access
- no architecture drift
- Staging smoke pass

Production deploy 可以作为独立最终 Gate。

---

# 二十六、最终要求

本次不要执行代码。

只生成详细实施计划。

计划必须达到这样的程度：

> 一个新的 Coding Agent 只读取：
>
> 1. `AGENT_EXECUTION_RULES.md`
> 2. 当前 Task
> 3. 被 Task 引用的架构章节
>
> 就可以开始工作，
> 不需要重新让我解释系统，
> 也不需要自行重新设计实现方案。

请重点优化：

**减少 Human Interaction。**

如果计划里某个步骤本可以通过自动化完成，却要求我手工操作，请重新设计。

完成计划后，最后额外输出：

# Expected Human Intervention Summary

告诉我：

1. Local 阶段预计需要我几次；
2. Staging 阶段预计需要我几次；
3. Production 阶段预计需要我几次；
4. 每一次分别为了什么；
5. 哪些 Gate 如果 Agent 已有授权可以自动跳过。

理想目标：

```text
Local: 0
Staging: 0–1
Production: explicit approval gates
```

# 二十七、持续更新任务进度，保证我可以随时检查

Coding Agent 在整个实施过程中必须持续维护可读、可追踪的任务进度。

目标：

> 我可以在任何时间打开仓库，快速知道：
>
> - 已经完成了什么
> - 当前正在做什么
> - 哪些任务失败或阻塞
> - 下一步准备做什么
> - 测试目前是否通过
> - 是否即将触发 Human Gate
> - 实际实现是否偏离原计划

不得只依赖 Agent 的聊天上下文记录进度。

------

## 1. 创建统一进度文件

创建：

```
docs/implementation/PROGRESS.md
```

该文件作为当前实施状态的主要进度入口。

必须至少包含：

```text
Current Phase
Current Task
Overall Status
Last Updated
Last Successful Quality Gate
Current Blockers
Pending Human Gates
Next Tasks
Recent Commits
```

例如：

```markdown
# AisenHub Platform Implementation Progress

Last Updated: 2026-xx-xx xx:xx

## Overall

Status: IN_PROGRESS

Current Phase:
P1 — Identity / Application / Session

Current Task:
P1-T006 — Implement platform session exchange

Overall Progress:
18 / 74 tasks completed

## Phase Progress

- [x] Phase 0 — Bootstrap
- [ ] Phase 1 — Identity / Application / Session (6/14)
- [ ] Phase 2 — Catalog / Entitlement / Redemption
- [ ] Phase 3 — Admin Foundation
- [ ] Phase 4 — Commerce
- [ ] Phase 5 — Staging

## Current Work

P1-T006 — Implement platform session exchange

Status:
IN_PROGRESS

Started:
...

Dependencies:
all satisfied

## Latest Verification

- lint: PASS
- typecheck: PASS
- unit tests: PASS
- database tests: PASS
- RLS tests: PASS
- build: PASS

## Current Blockers

None

## Pending Human Gates

None

## Next

1. P1-T007
2. P1-T008
3. P1-T009
```

------

## 2. 每个任务必须更新自己的状态

Phase 文件里的每个 Task 都必须包含：

```text
Status:
pending
in_progress
completed
blocked
failed
human_gate
```

Agent 开始任务前：

```text
pending → in_progress
```

验收全部通过后：

```text
in_progress → completed
```

如果遇到问题：

```text
in_progress → blocked
```

并写明原因。

不得提前标记 completed。

只有 Acceptance Criteria 全部通过才能完成。

------

## 3. Progress 更新时机

Agent 至少必须在以下节点更新 `PROGRESS.md`：

### 开始一个新 Task 时

记录：

- Current Task
- Start Time
- Goal

### 完成一个 Task 时

记录：

- Task completed
- Acceptance Criteria
- Tests
- Commit
- Next Task

### 测试失败并进行较大修复时

记录：

- 哪项测试失败
- 当前影响
- 是否已经解决

普通的一次 lint 小错误不需要记录。

### Phase Quality Gate 完成时

记录完整 Gate：

```text
lint
typecheck
unit
database
RLS
API
integration
E2E
build
```

以及 PASS / FAIL。

### 出现 Blocker 时

立即更新。

### 即将触发 Human Gate 时

立即更新。

------

## 4. 建立 Task Ledger

另外创建：

```
docs/implementation/TASK_LEDGER.md
```

它作为稳定的完整任务账本。

格式例如：

| Task    | Phase     | Status      | Started | Completed | Commit | Notes |
| ------- | --------- | ----------- | ------- | --------- | ------ | ----- |
| P0-T001 | Bootstrap | completed   | ...     | ...       | abc123 |       |
| P0-T002 | Bootstrap | completed   | ...     | ...       | def456 |       |
| P1-T001 | Identity  | completed   | ...     | ...       | ghi789 |       |
| P1-T002 | Identity  | in_progress | ...     |           |        |       |

`PROGRESS.md`：

用于快速看当前情况。

`TASK_LEDGER.md`：

用于查看完整历史。

------

## 5. 不得重写历史进度

Agent 更新进度时：

可以更新当前状态，

但不得为了让结果看起来更整洁而删除：

- 曾经出现的重要 Blocker
- Failed Quality Gate
- Architecture Blocker
- Human Gate
- 已完成任务记录

需要保留足够的信息让我事后检查实施过程。

但也不要记录大量低价值 Debug 日志。

原则：

> 记录决策和结果，不记录每一次尝试。

------

## 6. 每次 Commit 后同步进度

完成 Task 并创建 Commit 后：

必须把：

```text
Task ID
Commit SHA
Result
```

写入 Task Ledger。

例如：

```text
P1-T006
completed
commit: a83fd27
```

这样可以实现：

```text
Architecture
↓
Master Plan
↓
Task
↓
Commit
```

完整追踪。

------

## 7. Architecture Blocker 单独记录

如果出现：

```
ARCHITECTURE_BLOCKER
```

除更新 `PROGRESS.md` 外，还需要创建：

```text
docs/implementation/blockers/
AB-001.md
```

内容：

```text
Blocker ID
Task
Architecture Reference
Problem
Evidence
Why Agent Cannot Safely Decide
Minimal Proposed Change
Affected Tasks
Current Workaround
Status
```

不得只在聊天里告诉我。

------

## 8. Human Gate 单独记录

如果出现 Human Gate：

更新：

```
HUMAN_GATES.md
```

状态：

```text
planned
ready
waiting
resolved
skipped
```

例如：

```text
HG-001 — Connect Supabase Staging

Status: READY

Agent already verified:
✓ Local environment passes
✓ migrations pass
✓ tests pass
✓ CLI checked
✗ no staging credentials available

Human action required:
Authorize Supabase CLI

After completion:
Agent can continue automatically.
```

这样我可以快速判断：

究竟是真的需要我，

还是 Agent 没有先把自动化工作做完。

------

## 9. 增加 Progress Checkpoint

每完成一个 Phase，Agent 必须创建：

```text
docs/implementation/checkpoints/
PHASE-00.md
PHASE-01.md
...
```

Checkpoint 至少包括：

```text
Phase
Completed Tasks
Delivered Functionality
Migrations Added
API Added
Tests Added
Quality Gate Results
Known Limitations
Deferred Items
Architecture Deviations
Human Interventions
Git Range
Next Phase
```

如果：

```text
Architecture Deviations
```

不是：

```text
None
```

必须说明依据。

不得出现静默偏离架构。

------

## 10. 我检查进度时不应阻塞 Agent

我的查看行为：

不是 Human Gate。

Agent 不需要因为我可能检查：

```
PROGRESS.md
```

就暂停工作。

除非我明确要求：

```text
暂停
stop
hold
不要继续
```

否则 Agent 应继续按照 Master Plan 执行。

------

## 11. 任务完成信息要简洁

Agent 对外更新任务进度时，不需要每完成几行代码就通知。

建议按照：

- Atomic Task 完成
- 重要测试失败
- Phase 完成
- Blocker
- Human Gate

这些节点更新。

目标：

**可观察，但不产生大量噪音。**

------

## 12. 进度真实性规则

严禁：

- 没运行测试却写 PASS
- 测试部分失败却标 completed
- 使用 “应该可以” 作为验收
- 用 TODO 代替 Acceptance Criteria
- 因为代码已写就认为 Task 完成
- 隐藏失败测试
- 隐藏架构偏离

必须以真实命令执行结果为依据。

------

## 13. 最终形成五层可追踪关系

整个实施过程必须能够追踪：

```text
Architecture
    ↓
MASTER_PLAN
    ↓
Phase
    ↓
Atomic Task
    ↓
Commit + Tests
```

并由：

```text
PROGRESS.md
TASK_LEDGER.md
checkpoints/
```

提供当前状态和历史记录。

这样即使更换 Coding Agent，新 Agent 也可以通过这些文件立即判断当前实施位置，而不依赖之前的聊天记录。