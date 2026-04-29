# Instance 创建接口

## API 端点

```
POST /api/v1/instances
```

路由注册于 `backend/cmd/server/main.go:185`。

## 请求参数 (JSON Body)

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✅ | 实例名称，长度 3~50 |
| `type` | string | ✅ | 类型：`openclaw`, `ubuntu`, `debian`, `centos`, `custom`, `webtop`, `hermesagent` |
| `cpu_cores` | float64 | ✅ | CPU 核数，0.1~32 |
| `memory_gb` | int | ✅ | 内存 GB，1~128 |
| `disk_gb` | int | ✅ | 磁盘 GB，10~1000 |
| `os_type` | string | ✅ | 操作系统类型 |
| `os_version` | string | ✅ | 操作系统版本 |
| `description` | string | ❌ | 描述 |
| `gpu_enabled` | bool | ❌ | 是否启用 GPU |
| `gpu_count` | int | ❌ | GPU 数量，0~4 |
| `image_registry` | string | ❌ | 镜像仓库 |
| `image_tag` | string | ❌ | 镜像标签 |
| `environment_overrides` | map[string]string | ❌ | 环境变量覆盖 |
| `storage_class` | string | ❌ | 存储类 |
| `openclaw_config_plan` | object | ❌ | OpenClaw 配置计划 |
| `skill_ids` | number[] | ❌ | 关联的技能 ID 列表 |

## 调用流程

1. **前端** — `frontend/src/services/instanceService.ts:27` 调用 `api.post("/instances", data)`
2. **Handler** — `backend/internal/handlers/instance_handler.go:182` 接收 JSON，做验证，映射到 service 层
3. **Service** — `backend/internal/services/` 中的 `InstanceService.Create()` 处理业务逻辑（创建 DB 记录 + K8s 资源）

## 前端 TypeScript 类型定义

位置：`frontend/src/types/instance.ts:109`

```typescript
interface CreateInstanceRequest {
  name: string;
  type: "openclaw" | "ubuntu" | "debian" | "centos" | "custom" | "webtop" | "hermesagent";
  cpu_cores: number;
  memory_gb: number;
  disk_gb: number;
  os_type: string;
  os_version: string;
  description?: string;
  gpu_enabled?: boolean;
  gpu_count?: number;
  image_registry?: string;
  image_tag?: string;
  environment_overrides?: Record<string, string>;
  storage_class?: string;
  openclaw_config_plan?: OpenClawConfigPlan;
  skill_ids?: number[];
}
```
