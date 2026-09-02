# Staging 环境检查说明（中文）

更新时间：2026-09-02  
当前状态：HG-001 部分完成，等待剩余配置
检查范围：只检查 Staging 能力，没有修改任何远程资源

## 先说结论

Local、Docker、WSL 和项目代码目前都正常。你已经完成 Supabase 登录并创建了独立 Staging 项目；现在只剩托管地址和环境变量配置。

这不是 Docker 启动失败，也不是代码测试失败。

## 已经完成的工作

- 本地数据库、权限、接口、前端、自动化测试和构建全部通过。
- 已生成可重复的 Staging 发布包。
- 发布包固定来自 Git 提交 `0b139e855046aea909a31814925a4c9e25fd2695`。
- 已检查 41 个数据库迁移、14 个 Edge Function 源文件，以及 Account/Admin 前端构建产物。
- 发布包不包含本地密钥。
- 发布包和校验文件连续生成两次，结果一致。

## 为什么显示这些问题

### 1. Supabase CLI 授权（已完成）

Supabase CLI 是连接 Supabase 项目的工具。当前 Codex 环境中：

- 没有可用的已保存 Supabase 登录状态；
- 也没有 `SUPABASE_ACCESS_TOKEN` 环境变量。

现在已经可以列出项目。已确认 Staging 项目如下：

```text
项目名称：workendstaging
项目 Ref：egsokuicabbxspkdccqe
项目地址：https://egsokuicabbxspkdccqe.supabase.co
状态：ACTIVE_HEALTHY
```

现在的检查程序同时支持两种登录方式：

- 执行 `supabase login` 后保存的登录状态；
- 环境中的 `SUPABASE_ACCESS_TOKEN`。

### 2. Staging 项目（已完成）

你已经创建了独立的 Staging 项目，项目编号和地址已经确认。它与 Local、Production 分开，符合环境隔离要求。

Local 项目和 Staging 项目必须分开，不能把 Local 当成 Staging，也不能使用 Production 项目代替。

### 3. 托管和 DNS 未配置

仓库中没有现成的 Vercel、Cloudflare 或其他托管平台配置，也没有可用的 Staging 网站地址。

自定义域名不是必须的。测试阶段可以先使用托管平台自动提供的临时地址；只有需要正式域名时才配置 DNS。

### 4. `STAGING_*` 配置不存在

这些配置按安全规则不能提交到 Git，所以仓库里不会有真实值。当前 Codex 进程也没有读取到它们，因此预检显示为“不存在”。

预检只检查“有没有配置”，不会显示配置内容。

## 你需要做什么

### 第一步：授权 Supabase CLI

在项目目录打开 PowerShell，执行：

```text
pnpm exec supabase login
```

按提示完成登录。Token 不要发到聊天，也不要提交到 Git。

如果你在另一个窗口设置环境变量，完成后需要重启 Codex，确保 Codex 进程能读取到新配置。

### 第二步：准备独立的 Staging Supabase 项目

请使用一个独立的 Staging 项目，并在安全的环境配置中设置：

```text
STAGING_SUPABASE_PROJECT_REF
STAGING_SUPABASE_URL
STAGING_SUPABASE_ANON_KEY
STAGING_SUPABASE_SERVICE_ROLE_KEY
```

其中 `STAGING_SUPABASE_SERVICE_ROLE_KEY` 是高敏感密钥，只能放在 Secret Manager 或受保护的服务器环境中。

### 第三步：配置业务机密

在同一个受保护的 Secret Manager 中设置：

```text
STAGING_REDEMPTION_PEPPER
STAGING_PAYMENT_WEBHOOK_SECRET
```

这两个值必须是 Staging 专用值，不能复用 Production，也不能放进聊天、代码或提交记录。

### 第四步：准备网站地址

配置以下三个地址：

```text
STAGING_API_ORIGIN
STAGING_ACCOUNT_ORIGIN
STAGING_ADMIN_ORIGIN
```

可以使用托管平台生成的临时地址，不一定要先购买或配置自定义域名。托管平台和 DNS 的账号授权也必须由你在本机或平台后台完成。

## 我会如何确认配置成功

你配置完成后，我会运行：

```text
pnpm staging:preflight --check-only
```

这个检查只会显示“已配置/未配置”等状态，不会打印密钥。确认通过后，我会继续完成 Staging 部署、迁移、接口测试、浏览器测试和安全验证。

## 你完成后只需要告诉我

```text
Staging 配置已完成
```

不需要把任何 Token、Service Role Key、Pepper 或 Webhook Secret 发给我。

## 当前代码记录

- Staging 发布包记录：[`P7-T002-staging-bundle.md`](reports/P7-T002-staging-bundle.md)
- Staging 预检脚本：[`staging-preflight.mjs`](../../scripts/staging-preflight.mjs)
- 当前预检修复已推送：`ce90666`

架构偏离：无。
