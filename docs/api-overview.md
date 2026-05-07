# API 端点总览

本文档汇总 ClawManager 后端当前对外暴露的全部 HTTP / WebSocket 接口,按用途分组。所有路由的统一前缀为 `/api/v1`,注册入口在 `backend/cmd/server/main.go:144`。

> 本文为索引型参考文档。具体请求/响应字段以代码为准 —— `handler` 列指向真实实现,可直接跳转查看 DTO 与业务逻辑。

## 1. 鉴权机制

| 标记 | 中间件 / 实现 | 说明 |
|---|---|---|
| **公开** | 无 | 任何人可调,无需令牌 |
| **JWT** | `middleware.Auth()` + `middleware.SetUserInfo(userRepo)` | Header `Authorization: Bearer <access_token>`,access token 由 `/auth/login` 颁发 |
| **JWT+Admin** | 上面两者 + `middleware.NewAdminAuth(userRepo)` | 在 JWT 基础上额外检查 `users.role == "admin"`,非 admin 返回 403 |
| **Gateway Token** | `middleware.GatewayAuth(instanceRepo)` | Header 里的网关令牌,由 instance 实例(Pod 内的 agent / runtime)使用,不是用户 JWT |
| **Agent token (handler 内部)** | 无 Gin 中间件;handler 内 `authenticateAgentSession` 自行校验 | bootstrap token + session token,只允许 Pod 内的 agent 调用 |
| **Token 受控代理** | 无中间件;短期 access token 通过 cookie 或 query 携带 | 仅用于 `/instances/:id/proxy`,token 由 `POST /instances/:id/access` 颁发,有效期 1h |

中间件实现位置:
- `backend/internal/middleware/auth_middleware.go:15` — `Auth`
- `backend/internal/middleware/auth_middleware.go:54` — `GatewayAuth`
- `backend/internal/middleware/rbac_middleware.go:17` — `NewAdminAuth`

## 2. 路由分组速查

| 分组 | 前缀 | 鉴权 | 用途 |
|---|---|---|---|
| Auth | `/auth` | 公开 / JWT | 登录、注册、刷新、改密 |
| Users | `/users` | JWT / JWT+Admin | 用户与配额管理 |
| Instances | `/instances` | JWT | 实例生命周期、运行时、技能挂载、工作区导入导出、Pod exec |
| Admin Instances | `/admin/instances` | JWT+Admin | 跨用户列实例 |
| OpenClaw Configs | `/openclaw-configs` | JWT | 资源 / Bundle CRUD,编译预览,注入快照 |
| Skills | `/skills` | JWT | 技能 CRUD、版本、扫描结果 |
| System Settings | `/system-settings` | JWT / JWT+Admin | 镜像配置、集群资源 |
| Admin Models | `/admin/models` | JWT+Admin | LLM 模型管理 |
| Admin AI Audit | `/admin/ai-audit` | JWT+Admin | AI 调用审计 |
| Admin Costs | `/admin/costs` | JWT+Admin | 成本概览 |
| Admin Risk Rules | `/admin/risk-rules` | JWT+Admin | 风险规则 |
| Admin Skills | `/admin/skills` | JWT+Admin | 跨用户技能列表 |
| Admin Security | `/admin/security` | JWT+Admin | 技能安全扫描配置/作业 |
| AI Gateway | `/gateway/llm` | Gateway Token | 给实例使用的 OpenAI 兼容代理 |
| Agent | `/agent` | Agent token | Pod 内 agent 注册、心跳、命令拉取/上报 |
| Instance Proxy | `/instances/:id/proxy` | 短期 access token | 反向代理到 Pod 端口(iframe / WebSocket 用) |
| WebSocket | `/ws` | JWT | 事件推送 |
| Egress Proxy | NoRoute / NoMethod | — | 未匹配路径的出站代理(`egress_proxy_handler.Handle`) |

---

## 3. 详细端点

### 3.1 Auth (`/api/v1/auth`)
注册位置:`main.go:147-155`。Handler:`backend/internal/handlers/auth_handler.go`。

| 方法 | 路径 | 鉴权 | 功能 | Handler |
|---|---|---|---|---|
| POST | `/auth/register` | 公开 | 注册账户 | `auth_handler.go:46` `Register` |
| POST | `/auth/login` | 公开 | 用户名密码登录,返回 access + refresh token | `auth_handler.go:63` `Login` |
| POST | `/auth/refresh` | 公开 | 用 refresh token 换新 access token | `auth_handler.go:80` `RefreshToken` |
| POST | `/auth/logout` | 公开 | 注销(撤销 token) | `auth_handler.go:97` `Logout` |
| GET | `/auth/me` | JWT | 当前用户 | `auth_handler.go:104` `GetCurrentUser` |
| POST | `/auth/change-password` | JWT | 修改密码 | `auth_handler.go:121` `ChangePassword` |

### 3.2 Users (`/api/v1/users`)
注册位置:`main.go:158-178`。Handler:`backend/internal/handlers/user_handler.go`。

| 方法 | 路径 | 鉴权 | 功能 |
|---|---|---|---|
| GET | `/users` | JWT+Admin | 列出全部用户 |
| POST | `/users` | JWT+Admin | 创建用户 |
| POST | `/users/import` | JWT+Admin | 批量导入 |
| DELETE | `/users/:id` | JWT+Admin | 删除用户 |
| PUT | `/users/:id/role` | JWT+Admin | 修改角色 |
| PUT | `/users/:id/quota` | JWT+Admin | 修改配额 |
| GET | `/users/:id` | JWT | 用户信息(本人或 admin) |
| PUT | `/users/:id` | JWT | 更新用户信息(本人或 admin) |
| GET | `/users/:id/quota` | JWT | 查看配额 |

### 3.3 Instances (`/api/v1/instances`)
注册位置:`main.go:181-209`。Handler:`backend/internal/handlers/instance_handler.go`。**全部 JWT,且默认要求"属主或 admin"**(由 `requireOwnedInstance` / `resolveOwnedInstance` 强制)。

| 方法 | 路径 | 功能 | Handler |
|---|---|---|---|
| GET | `/instances` | 列出当前用户实例(workspace 视图) | `instance_handler.go:123` `ListInstances` |
| POST | `/instances` | 创建实例(分配 K8s Pod / PVC / Service) | `instance_handler.go:200` `CreateInstance` |
| GET | `/instances/:id` | 实例详情 | `instance_handler.go:244` `GetInstance` |
| PUT | `/instances/:id` | 更新实例元数据 | `instance_handler.go:282` `UpdateInstance` |
| DELETE | `/instances/:id` | 删除实例(同步删 K8s 资源) | `instance_handler.go:330` `DeleteInstance` |
| POST | `/instances/:id/start` | 启动 | `instance_handler.go:367` `StartInstance` |
| POST | `/instances/:id/stop` | 停止 | `instance_handler.go:404` `StopInstance` |
| POST | `/instances/:id/restart` | 重启 | `instance_handler.go:441` `RestartInstance` |
| GET | `/instances/:id/status` | 实例运行状态 | `instance_handler.go:478` `GetInstanceStatus` |
| GET | `/instances/:id/runtime` | 运行时(agent)详情 | `instance_handler.go:522` `GetRuntimeDetails` |
| POST | `/instances/:id/runtime/:command` | 给 agent 入队一条命令(`:command` 为受控枚举,**不是任意 shell**) | `instance_handler.go:551` `CreateRuntimeCommand` |
| GET | `/instances/:id/config/revisions` | 列出配置版本 | `instance_handler.go:595` `ListConfigRevisions` |
| POST | `/instances/:id/config/revisions/publish` | 发布新配置版本 | `instance_handler.go:611` `PublishConfigRevision` |
| POST | `/instances/:id/access` | 颁发 1h 短期访问 token + 写 cookie | `instance_handler.go:702` `GenerateAccessToken` |
| GET | `/instances/:id/access` | 校验 token,返回访问 URL | `instance_handler.go:783` `AccessInstance` |
| POST | `/instances/:id/sync` | 强制与 K8s 状态同步 | `instance_handler.go:815` `ForceSync` |
| GET | `/instances/:id/openclaw/export` | 导出 `.openclaw` 工作区(tar.gz,经 Pod exec) | `instance_handler.go:912` `ExportOpenClaw` |
| POST | `/instances/:id/openclaw/import` | 导入 `.openclaw` 工作区 | `instance_handler.go:988` `ImportOpenClaw` |
| GET | `/instances/:id/hermes/export` | 导出 `.hermes` 工作区 | `instance_handler.go:950` `ExportHermes` |
| POST | `/instances/:id/hermes/import` | 导入 `.hermes` 工作区 | `instance_handler.go:1043` `ImportHermes` |
| **POST** | **`/instances/:id/exec`** | **在 Pod 中执行一次性 shell 命令,返回 stdout/stderr/exit_code** | `instance_handler.go:1097` `ExecuteCommand` |
| GET | `/instances/:id/skills` | 列出实例已挂载技能 | `skill_handler.go:164` `ListInstanceSkills` |
| POST | `/instances/:id/skills` | 给实例挂技能 | `skill_handler.go:177` `AttachSkillToInstance` |
| DELETE | `/instances/:id/skills/:skillId` | 卸载技能 | `skill_handler.go:195` `RemoveSkillFromInstance` |

**Instance Proxy(独立路由,鉴权自管)**:位于 `main.go:362-363`,**不**在 `instances` 路由组内,因此**不走** `Auth()` 中间件。鉴权完全靠 `POST /instances/:id/access` 颁发的短期 access token(cookie 或 query)。

| 方法 | 路径 | 功能 | Handler |
|---|---|---|---|
| ANY | `/instances/:id/proxy` | 反向代理到 Pod 端口(iframe 入口) | `instance_handler.go:854` `ProxyInstance` |
| ANY | `/instances/:id/proxy/*path` | 同上,带子路径 | 同上 |

### 3.4 Admin Instances (`/api/v1/admin/instances`)
注册位置:`main.go:215-221`。**JWT + SetUserInfo + NewAdminAuth**。

| 方法 | 路径 | 功能 | Handler |
|---|---|---|---|
| GET | `/admin/instances` | 跨用户列出全部实例 | `instance_handler.go:174` `ListAllInstances` |

### 3.5 OpenClaw Configs (`/api/v1/openclaw-configs`)
注册位置:`main.go:223-245`。Handler:`backend/internal/handlers/openclaw_config_handler.go`。全部 JWT。

资源(Resources):

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/openclaw-configs/resources` | 列出资源 |
| POST | `/openclaw-configs/resources` | 创建资源 |
| POST | `/openclaw-configs/resources/validate` | 校验资源 |
| GET | `/openclaw-configs/resources/:id` | 详情 |
| PUT | `/openclaw-configs/resources/:id` | 更新 |
| DELETE | `/openclaw-configs/resources/:id` | 删除 |
| POST | `/openclaw-configs/resources/:id/clone` | 克隆 |

Bundles:

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/openclaw-configs/bundles` | 列出 bundle |
| POST | `/openclaw-configs/bundles` | 创建 bundle |
| GET | `/openclaw-configs/bundles/:id` | 详情 |
| PUT | `/openclaw-configs/bundles/:id` | 更新 |
| DELETE | `/openclaw-configs/bundles/:id` | 删除 |
| POST | `/openclaw-configs/bundles/:id/clone` | 克隆 |

其它:

| 方法 | 路径 | 功能 |
|---|---|---|
| POST | `/openclaw-configs/compile-preview` | 编译预览 |
| GET | `/openclaw-configs/injections` | 列出注入快照 |
| GET | `/openclaw-configs/injections/:id` | 单个注入快照 |

### 3.6 Skills (`/api/v1/skills`)
注册位置:`main.go:247-259`。Handler:`backend/internal/handlers/skill_handler.go`。全部 JWT。

| 方法 | 路径 | 功能 | Handler |
|---|---|---|---|
| GET | `/skills` | 列出技能(本用户可见) | `skill_handler.go:38` `ListSkills` |
| POST | `/skills/import` | 导入技能包 | `skill_handler.go:23` `ImportSkills` |
| GET | `/skills/:id` | 详情 | `skill_handler.go:57` `GetSkill` |
| PUT | `/skills/:id` | 更新 | `skill_handler.go:72` `UpdateSkill` |
| DELETE | `/skills/:id` | 删除 | `skill_handler.go:92` `DeleteSkill` |
| GET | `/skills/:id/download` | 下载技能包 | `skill_handler.go:106` `DownloadSkill` |
| GET | `/skills/:id/versions` | 列出版本 | `skill_handler.go:134` `ListVersions` |
| GET | `/skills/:id/scan-results` | 扫描结果 | `skill_handler.go:149` `ListScanResults` |

### 3.7 System Settings (`/api/v1/system-settings`)
注册位置:`main.go:261-276`。**两个分组共享前缀但鉴权不同**。

| 方法 | 路径 | 鉴权 | 功能 | Handler |
|---|---|---|---|---|
| GET | `/system-settings/images` | JWT | 列出系统镜像配置 | `system_settings_handler.go` `ListSystemImageSettings` |
| PUT | `/system-settings/images` | JWT+Admin | 增改镜像配置 | `system_settings_handler.go` `UpsertSystemImageSetting` |
| DELETE | `/system-settings/images/:instanceType` | JWT+Admin | 删除镜像配置 | `system_settings_handler.go` `DeleteSystemImageSetting` |
| GET | `/system-settings/cluster-resources` | JWT+Admin | 集群资源概览 | `cluster_resource_handler.go` `GetOverview` |

### 3.8 Admin Models (`/api/v1/admin/models`)
注册位置:`main.go:278-287`。Handler:`backend/internal/handlers/llm_model_handler.go`。JWT+Admin。

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/admin/models` | 列出 LLM 模型 |
| POST | `/admin/models/discover` | 自动发现模型 |
| PUT | `/admin/models` | 增改模型 |
| DELETE | `/admin/models/:id` | 删除模型 |

### 3.9 Admin AI Audit (`/api/v1/admin/ai-audit`)
注册位置:`main.go:289-296`。Handler:`backend/internal/handlers/ai_observability_handler.go`。JWT+Admin。

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/admin/ai-audit` | 列出审计条目 |
| GET | `/admin/ai-audit/:traceId` | 单 trace 详情 |

### 3.10 Admin Costs (`/api/v1/admin/costs`)
注册位置:`main.go:298-304`。JWT+Admin。

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/admin/costs` | 成本概览 |

### 3.11 Admin Risk Rules (`/api/v1/admin/risk-rules`)
注册位置:`main.go:306-316`。Handler:`backend/internal/handlers/risk_rule_handler.go`。JWT+Admin。

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/admin/risk-rules` | 列出规则 |
| POST | `/admin/risk-rules/test` | 用样本测试规则 |
| POST | `/admin/risk-rules/bulk-status` | 批量启停 |
| PUT | `/admin/risk-rules` | 增改规则 |
| DELETE | `/admin/risk-rules/:ruleId` | 删除规则 |

### 3.12 Admin Skills (`/api/v1/admin/skills`)
注册位置:`main.go:318-324`。JWT+Admin。

| 方法 | 路径 | 功能 | Handler |
|---|---|---|---|
| GET | `/admin/skills` | 跨用户技能列表 | `skill_handler.go:48` `ListAllSkills` |

### 3.13 Admin Security (`/api/v1/admin/security`)
注册位置:`main.go:326-337`。Handler:`backend/internal/handlers/security_handler.go`。JWT+Admin。

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/admin/security/config` | 安全扫描配置 |
| PUT | `/admin/security/config` | 保存安全扫描配置 |
| POST | `/admin/security/scan-jobs` | 触发新扫描 |
| POST | `/admin/security/skills/:id/rescan` | 单技能重新扫描 |
| GET | `/admin/security/scan-jobs` | 列出扫描作业 |
| GET | `/admin/security/scan-jobs/:id` | 单扫描作业详情 |

### 3.14 AI Gateway (`/api/v1/gateway/llm`)
注册位置:`main.go:339-344`。Handler:`backend/internal/handlers/ai_gateway_handler.go`。**鉴权:Gateway Token**(实例侧调用,非用户 JWT)。

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/gateway/llm/models` | 列出可用模型 |
| POST | `/gateway/llm/chat/completions` | OpenAI 兼容的 chat completions(支持流式) |

### 3.15 Agent (`/api/v1/agent`)
注册位置:`main.go:346-358`。**分组无 Gin 中间件**,handler 内自鉴权(`agent_handler.go:234` `authenticateAgentSession`)。Handler:`backend/internal/handlers/agent_handler.go`。

| 方法 | 路径 | 功能 | Handler |
|---|---|---|---|
| POST | `/agent/register` | Agent 注册(用 bootstrap token 换 session) | `agent_handler.go:33` `Register` |
| POST | `/agent/heartbeat` | 心跳 | `agent_handler.go:54` `Heartbeat` |
| GET | `/agent/commands/next` | 拉取下一条命令 | `agent_handler.go:77` `NextCommand` |
| POST | `/agent/commands/:id/start` | 标记命令开始 | `agent_handler.go:91` `StartCommand` |
| POST | `/agent/commands/:id/finish` | 提交命令结果 | `agent_handler.go:120` `FinishCommand` |
| POST | `/agent/state/report` | 上报状态 / metrics | `agent_handler.go:143` `ReportState` |
| POST | `/agent/skills/inventory` | 上报技能清单 | `agent_handler.go:183` `ReportSkillInventory` |
| POST | `/agent/skills/upload` | 上传技能包 | `agent_handler.go:204` `UploadSkillPackage` |
| GET | `/agent/skills/versions/:skillVersion/download` | 下载技能版本 | `skill_handler.go:123` `DownloadSkillVersionForAgent` |
| GET | `/agent/config/revisions/:id` | 获取配置版本 | `agent_handler.go:161` `GetConfigRevision` |

### 3.16 WebSocket (`/api/v1/ws`)
注册位置:`main.go:366-372`。Handler:`backend/internal/handlers/websocket_handler.go`。JWT。

| 方法 | 路径 | 功能 | Handler |
|---|---|---|---|
| GET | `/ws` | 升级为 WebSocket(事件总线) | `websocket_handler.go:24` `HandleWebSocket` |
| GET | `/ws/stats` | 当前活跃连接数 | `websocket_handler.go:36` `GetConnectionCount` |

### 3.17 Egress Proxy (NoRoute / NoMethod)
注册位置:`main.go:140-141`。所有未匹配的路径会落到 `egress_proxy_handler.Handle`(`backend/internal/handlers/egress_proxy_handler.go`),作为出站代理使用。**不是** Pod exec,**不是**反向代理到实例。

---

## 4. 通用响应约定

### 成功

```json
{
  "success": true,
  "message": "<短描述>",
  "data": { ... }
}
```

由 `utils.Success(c, status, message, data)`(`backend/internal/utils/response.go:14`)统一输出。

### 失败

```json
{
  "success": false,
  "error": "<message>"
}
```

由 `utils.Error(c, status, message)`(`response.go:23`)输出。`utils.HandleError(c, err)`(`response.go:31`)负责把已知 err 文本映射到合适的 HTTP 状态码,默认走 500。

### 常见 HTTP 状态码

| 码 | 触发场景 |
|---|---|
| 400 | 参数非法、JSON 解析失败、业务前置校验失败 |
| 401 | 未带或失效的 JWT / agent session |
| 403 | 已认证但无权限(非属主、非 admin、被风险策略拒绝) |
| 404 | 资源不存在(实例、用户、模型、规则、技能等) |
| 409 | 状态冲突(如实例不在 running 状态时调用 exec) |
| 502 | 出站依赖失败(LLM provider discovery、Pod exec 传输层错误) |
| 504 | 命令超时(`/instances/:id/exec`) |

## 5. 速查:每类调用方推荐入口

| 调用方 | 用什么 | 怎么拿凭据 |
|---|---|---|
| Web 浏览器 / SPA 用户 | `/auth/*`、`/instances/*`、`/skills/*`、`/users/:id` 以及 admin 视图 | `POST /auth/login` 拿 access + refresh token,放 `Authorization: Bearer ...` |
| Pod 内 agent | `/api/v1/agent/*`(以及 `/gateway/llm/*` 调 LLM) | bootstrap token(由 ClawManager 创建实例时注入)→ `POST /agent/register` 换 session token |
| 实例内 SDK 调 LLM | `/api/v1/gateway/llm/*` | Gateway token(实例创建时颁发,持久存在 instance 记录里) |
| 自动化脚本 / CI 在 Pod 里跑命令 | `POST /api/v1/instances/:id/exec`(JWT) | 同 SPA 用户,用账号 access token |
| 浏览器 iframe 嵌入桌面 | `/api/v1/instances/:id/proxy/...` | `POST /instances/:id/access` 拿短期 token,自动写 HttpOnly cookie |

---

## 6. 维护说明

- **行号变动时记得回扫本文档**:本文里 `main.go:xxx` / `instance_handler.go:xxx` 的位置随重构会漂,改动核心路由/handler 时建议 grep `api-overview.md` 同步更新。
- **新增端点必须在两处加入**:`main.go` 路由注册 + 本文档对应分组的表格。文档的目的是给调用方一个唯一的索引;漏一个就会导致排查时怀疑接口不存在。
- **不要把 DTO 字段抄进来**:DTO 易变,抄进文档就一定会错。请把 handler 链接保持准确,让读者自己跳进代码看 struct tag。
