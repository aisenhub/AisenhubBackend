# Staging 预检环境变量填写模板

> 请直接填写下面四个“值”字段。
>
> 这是敏感配置模板：填写真实值后不要提交到 Git、不要截图、不要粘贴到聊天中。
> 配置完成后请保存文件，并告诉 Codex“已填写模板”，我会读取并导入到受保护的用户环境变量中。

## 1. Supabase Staging anon/public key

变量名：`STAGING_SUPABASE_ANON_KEY`

变量值：sb_publishable_fyu1H6nROAYa3a0l5rsLBA_mGuXUJ-I

```text
请粘贴 Supabase Staging 项目 Settings → API → anon/public key
```

## 2. Supabase Staging service_role key

变量名：`STAGING_SUPABASE_SERVICE_ROLE_KEY`

变量值：

```text
请粘贴 Supabase Staging 项目 Settings → API → service_role key
```

## 3. Redemption Pepper

变量名：`STAGING_REDEMPTION_PEPPER`

变量值：

```text
请填写你在 Supabase Edge Function Secrets 中 REDEMPTION_PEPPER 对应的完全相同的值
```

## 4. Payment Webhook Secret

变量名：`STAGING_PAYMENT_WEBHOOK_SECRET`

变量值：

```text
请填写你在 Supabase Edge Function Secrets 中 PAYMENT_WEBHOOK_SECRET_LOCAL 对应的完全相同的值
```

## 填写检查

- [ ] 四个变量值都已填写
- [ ] `STAGING_REDEMPTION_PEPPER` 与 `REDEMPTION_PEPPER` 的值完全一致
- [ ] `STAGING_PAYMENT_WEBHOOK_SECRET` 与 `PAYMENT_WEBHOOK_SECRET_LOCAL` 的值完全一致
- [ ] 没有多余的空格或引号
- [ ] 未将文件提交到 Git
- [ ] 未将 service_role key 配置到 Vercel 前端项目
