# AisenHub Platform Environment Configuration

本文档说明 Local、Staging、Production 的配置隔离方式，以及部署时如何自动选择对应环境。

## 1. 核心原则

三个环境使用相同的配置结构，但不能共享实际资源和敏感值：

```text
Local       → 本地 Supabase / 测试数据
Staging     → Staging Supabase / 测试云环境
Production  → Production Supabase / 正式数据
```

部署同一个 Git 提交时，环境由部署目标决定，环境变量由对应平台注入。代码不通过手动修改 `.env` 来回切换。

## 2. 配置归属

| 配置内容 | Local | Staging | Production |
| --- | --- | --- | --- |
| Supabase 项目 | 本地项目 | 独立 Staging 项目 | 独立 Production 项目 |
| Project Ref | 本地/测试 Ref | `STAGING_SUPABASE_PROJECT_REF` | `PRODUCTION_SUPABASE_PROJECT_REF` |
| 前端域名 | `localhost` | Staging 域名 | 正式 HTTPS 域名 |
| Origin 白名单 | development | staging | production |
| OAuth Client | Local Client | 独立 Staging Client | 独立 Production Client |
| 数据库 | 可重置测试数据 | 可按计划重建 | 正式数据，不得随意重置 |
| 支付 | 测试或关闭 | 测试或关闭 | 正式支付配置 |
| 操作权限 | Agent 可自主操作 | 有目标确认后可自主操作 | 必须经过 Human Gate |

## 3. 电脑系统环境变量

电脑系统或 CLI 环境主要用于 Agent 和 Supabase CLI 的授权，不用于保存某一个环境的全部运行配置。

### Supabase CLI 授权

```text
SUPABASE_ACCESS_TOKEN=<通过安全凭据管理器提供>
```

该变量表示 CLI 操作 Supabase 的账号授权，不绑定某一个项目。实际目标由 Project Ref、当前项目链接或部署命令决定。

建议使用 `supabase login` 或安全的 CI Secret 注入授权，不要把 Token 写入代码、聊天、日志或提交文件。

### 项目目标选择

执行云端操作前必须明确目标环境：

```text
Staging     → STAGING_SUPABASE_PROJECT_REF
Production  → PRODUCTION_SUPABASE_PROJECT_REF
```

不得依赖模糊的“当前项目”执行 Production 变更。部署脚本应先验证 Project Ref 与 Supabase URL 匹配，并验证 Staging 与 Production 不是同一个项目。

## 4. 前端环境变量

前端变量在 Vercel 的项目环境中分别配置。相同的变量名可以存在于多个环境，但值必须不同。

### Account

```text
VITE_SUPABASE_URL
VITE_PLATFORM_API_URL
VITE_PLATFORM_PUBLIC_API_URL
VITE_ACCOUNT_OAUTH_CLIENT_ID
```

### Admin

```text
VITE_PLATFORM_ADMIN_API_ORIGIN
VITE_ACCOUNT_ORIGIN
```

配置示例：

```text
Vercel Preview/Staging → Staging Supabase、Staging API、Staging OAuth Client
Vercel Production      → Production Supabase、Production API、Production OAuth Client
```

Vite 会在构建时注入变量，因此切换环境的本质是选择不同的 Vercel Environment，而不是修改业务代码。

## 5. Edge Functions 和后端变量

后端运行时变量通过 Supabase Function Secrets、CI Secret 或其他服务端 Secret Manager 提供。

常见变量包括：

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_AUTH_ISSUER
SUPABASE_AUTH_JWKS_URL
REDEMPTION_PEPPER
REDEMPTION_PEPPER_VERSION
PAYMENT_WEBHOOK_SECRET_LOCAL
PLATFORM_RUNTIME_ENVIRONMENT
```

其中：

- `SUPABASE_SERVICE_ROLE_KEY` 只能存在于安全服务端环境；
- `REDEMPTION_PEPPER`、Webhook Secret、支付密钥必须按环境分别生成；
- 不得将服务端密钥放入 Account/Admin 浏览器代码；
- 不得在 Local、Staging、Production 之间共享数据库密钥或业务 Secret。

## 6. 自动切换流程

标准流程如下：

```text
1. 本地使用 Local 配置开发
2. 提交代码并构建固定 Git SHA
3. 将同一个 SHA 部署到 Staging
4. Staging 平台注入 Staging 环境变量
5. 完成 OAuth、Origin、权益、Admin 和业务链路验证
6. 获准后将同一个 SHA 部署到 Production
7. Production 平台注入 Production 环境变量
```

因此不需要：

```text
手动修改 .env → 部署 Staging → 再手动改回 Production
```

同一个代码版本可以使用不同环境配置运行，但数据库、OAuth Client、域名和 Secret 必须始终隔离。

## 7. Staging 与 Production 的操作边界

### Local

Agent 可以自主执行：

- Supabase Local 启停；
- 数据库 reset；
- migration、seed 和测试；
- 本地前端构建和 E2E。

### Staging

确认目标项目确实是 Staging 且没有需要保留的数据后，Agent 可以自主执行：

- 部署 migration 和 Edge Functions；
- 更新 Staging Secret；
- 配置 Staging OAuth Client 和回调地址；
- 部署 Vercel Staging；
- 运行远程测试和恢复演练。

### Production

Agent 可以先进行只读检查、生成发布资料、构建和测试，但以下操作必须经过对应 Human Gate：

- Production migration 或重建；
- Production Secret 修改；
- DNS 修改；
- OAuth/支付正式切换；
- 大规模权益操作。

即使电脑中配置了 `SUPABASE_ACCESS_TOKEN`，也不能绕过 Production 审批。

## 8. 必须保持独立的内容

以下内容不得在环境之间复用：

- Supabase 项目和数据库；
- `SUPABASE_SERVICE_ROLE_KEY`；
- OAuth Client Secret 或其他 OAuth 配置凭据；
- Webhook Secret；
- `REDEMPTION_PEPPER`；
- Production 支付密钥；
- Production 数据和备份。

可以复用的是：

- 代码结构；
- migration 文件；
- 配置变量名称；
- 构建流程；
- 测试脚本；
- 已验证的发布流程。

## 9. 安全检查

每次云端部署前至少确认：

1. Git SHA 正确；
2. Project Ref 与 URL 匹配；
3. Staging 和 Production 项目不同；
4. OAuth Client 与环境匹配；
5. 回调地址使用正确域名；
6. Origin 白名单没有混入其他环境；
7. Secret 未被输出、提交或打包进浏览器；
8. Production 变更已获得明确授权。

当前仓库的 Staging/Production preflight 脚本应作为部署前的自动检查入口，不应以手工修改环境变量代替验证。
