# Production Protected Environment Template

用途：配置 HG-003 时，填写到 Codex/部署平台的受保护环境变量中。这里只
列变量名和说明，不要把真实值发到聊天或提交到 Git。

## Codex protected environment

```text
PRODUCTION_SUPABASE_PROJECT_REF=
PRODUCTION_SUPABASE_URL=
PRODUCTION_SUPABASE_ANON_KEY=
PRODUCTION_SUPABASE_SERVICE_ROLE_KEY=
PRODUCTION_REDEMPTION_PEPPER=
PRODUCTION_PAYMENT_WEBHOOK_SECRET=
PRODUCTION_API_ORIGIN=
PRODUCTION_ACCOUNT_ORIGIN=
PRODUCTION_ADMIN_ORIGIN=
```

填写规则：

- `PRODUCTION_SUPABASE_PROJECT_REF` 和 `PRODUCTION_SUPABASE_URL` 必须指向
  同一个已确认的 Production 项目。
- `PRODUCTION_SUPABASE_ANON_KEY` 和
  `PRODUCTION_SUPABASE_SERVICE_ROLE_KEY` 必须来自该 Production 项目；
  Service Role Key 只能存在于受保护的服务端环境。
- `PRODUCTION_REDEMPTION_PEPPER` 和
  `PRODUCTION_PAYMENT_WEBHOOK_SECRET` 必须是 Production 专用新值，不能
  复用 Local 或 Staging。
- 三个 Origin 使用实际的 Production API、Account、Admin 地址。若首发
  先使用托管商临时域名，可以先填写临时域名；正式 `aisenhub.com` DNS
  切换仍需经过 HG-005。

## Production Edge Function runtime names

如果在 Supabase Production 项目的 Edge Function Secrets 页面配置运行时
密钥，填写的是下面的“实际运行时名称”，不是上面的
`PRODUCTION_*` 别名：

```text
REDEMPTION_PEPPER=
REDEMPTION_PEPPER_VERSION=1
PAYMENT_WEBHOOK_SECRET_LOCAL=
PLATFORM_RUNTIME_ENVIRONMENT=production
```

其中两个 Secret 的值分别应与受保护环境中的
`PRODUCTION_REDEMPTION_PEPPER` 和 `PRODUCTION_PAYMENT_WEBHOOK_SECRET`
保持对应；不要在文档、日志、聊天或 Git 中记录值。

## Completion checklist

- [ ] 已确认 `aisenhubProject` 是否正式作为 Production 项目。
- [ ] 已配置上面 9 个受保护变量，且没有复制 Local/Staging 密钥。
- [ ] 已配置或授权 Production Account/Admin/API 托管资源。
- [ ] 已确认三项 Origin 与实际部署一致。
- [ ] 尚未进行 Production migration、部署、DNS 或支付切换；这些属于
      后续独立审批门。
