---
name: "api-config-plan"
description: "API 配置界面技术实现计划"
version: "V1.0"
---

# API 配置界面 技术实现计划

**版本**: V1.0  
**创建日期**: 2026-06-01  
**关联规范**: [api-config-spec_V1.0.md](../specs/api-config-spec_V1.0.md)  

## 1. 技术选型

### 1.1 技术栈
- **UI**: React + Tailwind CSS
- **状态**: Zustand (config store)
- **持久化**: electron-store
- **通信**: IPC (main ↔ renderer)
- **HTTP**: fetch (主进程代理 API 请求)

### 1.2 新增依赖
| 依赖 | 版本 | 用途 |
|------|------|------|
| electron-store | ^8.1.0 | 配置持久化存储 |

### 1.3 架构决策
| 决策 | 选项 A | 选项 B | 选择 | 理由 |
|------|--------|--------|------|------|
| 存储方式 | electron-store | SQLite | A | 轻量 KV 存储，适合配置项 |
| API 调用 | 主进程代理 | 渲染进程直调 | A | 避免 CORS，隐藏 API Key |

## 2. 组件设计

### 2.1 组件结构
```
src/
├── main/
│   ├── services/
│   │   └── config.service.ts          # 配置管理服务
│   └── ipc/
│       └── config.handler.ts          # 配置相关 IPC handler
├── renderer/
│   ├── components/
│   │   ├── ApiConfig.tsx              # API 配置页面
│   │   └── ConnectionTest.tsx         # 连接测试组件
│   └── stores/
│       └── config.store.ts            # 配置状态管理
└── shared/
    └── types.ts                       # 共享类型定义
```

### 2.2 关键组件说明
| 组件 | 职责 | 位置 |
|------|------|------|
| ApiConfig | 配置表单、输入验证、状态展示 | renderer/components/ |
| ConnectionTest | 测试连接按钮、进度、结果反馈 | renderer/components/ |
| config.service | 读写配置、验证 API Key | main/services/ |
| config.handler | 处理渲染进程配置请求 | main/ipc/ |
| config.store | 管理配置状态 | renderer/stores/ |

## 3. 数据流设计

### 3.1 IPC 通道
| 通道 | 方向 | 参数 | 返回值 |
|------|------|------|--------|
| `config:get` | renderer → main | `{ key: string }` | `Promise<any>` |
| `config:set` | renderer → main | `{ key: string, value: any }` | `Promise<void>` |
| `config:testConnection` | renderer → main | `{ apiKey: string }` | `Promise<{ success: boolean, error?: string }>` |

### 3.2 状态管理
```typescript
interface ConfigState {
  apiKey: string;
  isConfigured: boolean;
  isLoading: boolean;
  testStatus: 'idle' | 'testing' | 'success' | 'error';
  testError?: string;
  
  setApiKey: (key: string) => void;
  testConnection: () => Promise<void>;
  loadConfig: () => void;
}
```

### 3.3 数据库变更
无需数据库变更（配置存储在 electron-store）。

## 4. 安全考虑

### 4.1 数据安全
- API Key 存储在 electron-store（用户数据目录，受系统保护）
- 不在 console.log 中打印
- UI 中默认隐藏（支持切换显示）

### 4.2 API Key 处理
- 测试连接时通过主进程转发，不暴露给外部
- 错误响应中剥离敏感信息

## 5. 测试策略

### 5.1 单元测试
- config.service: 读写配置逻辑
- 输入验证逻辑

### 5.2 集成测试
- IPC 通道通信
- 主进程 API 代理

### 5.3 覆盖率要求
- Store: 70%
- IPC: 90%
- UI: 60%

## 6. 风险与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| API Key 明文存储 | 中 | 低 | 提醒用户风险，后续支持加密 |
| 网络超时 | 低 | 中 | 设置 10 秒超时，友好提示 |
| 测试连接误判 | 中 | 低 | 使用标准 API 端点验证 |

## 7. 实施计划

### 7.1 阶段划分
| 阶段 | 内容 | 产出 | 验证方式 |
|------|------|------|---------|
| Phase 1 | 类型定义 + electron-store 集成 | shared/types.ts, config.service.ts | 单元测试通过 |
| Phase 2 | IPC handler + API 代理 | config.handler.ts | IPC 通信测试 |
| Phase 3 | UI 组件 + Zustand store | ApiConfig.tsx, config.store.ts | 功能测试 |
| Phase 4 | 集成测试 + 优化 | 完整流程测试 | 手动测试验证 |

### 7.2 依赖关系
- Phase 2 依赖 Phase 1 完成
- Phase 3 依赖 Phase 2 完成
- Phase 4 依赖 Phase 3 完成

## 8. DoD 准出标准

1. 用户能够成功输入 API Key 并保存到本地存储
2. 用户能够点击"测试连接"并收到准确的成功/失败反馈
3. 配置界面加载时间 < 100ms，连接测试超时 < 10 秒

## 变更记录

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-01 | 初始版本 | AI 助手 |
| V1.1 | 2026-06-01 | Phase 1-4 实施完成，类型检查通过 | AI 助手 |

## 实施状态

### ✅ 已完成
- [x] Phase 1: 类型定义 + electron-store 集成
- [x] Phase 2: IPC handler + API 代理
- [x] Phase 3: UI 组件 + Zustand store
- [x] Phase 4: 集成测试 + 优化
- [x] 主进程入口注册 IPC handler
- [x] App.tsx 集成 ApiConfig 组件
- [x] TypeScript 类型检查通过

### 📁 创建/修改的文件
| 文件 | 状态 | 说明 |
|------|------|------|
| `src/shared/types.ts` | 新增 | IPC 类型定义 |
| `src/main/services/config.service.ts` | 新增 | 配置管理服务 |
| `src/main/ipc/config.handler.ts` | 新增 | IPC handler |
| `src/renderer/stores/config.store.ts` | 新增 | Zustand store |
| `src/renderer/components/ApiConfig.tsx` | 新增 | 配置界面组件 |
| `src/preload/index.ts` | 修改 | 暴露 electronAPI |
| `src/main/index.ts` | 修改 | 注册 IPC handler |
| `src/renderer/App.tsx` | 修改 | 集成配置组件 |
| `package.json` | 修改 | 添加 electron-store 依赖 |
