# ADR-C91 LLM 多账号管理（批次 D-1）

- 状态：**已接受**
- 日期：2026-09-10
- 决策者：主 Agent（经用户 2431 排期确认，批次 1 = 多账号）
- 关联：ADR-C83（多模型预设）/ 批次 E-1（免费测试模式）/ ADR-C90（批次 B-2）

## 背景

当前 LLM 配置为**单账号形态**：`LlmConfigStorage` 在 flutter_secure_storage 存
三键（api_key / api_base_url / api_model）+ 备选端点链（fallbacks）。用户需要
管理多套 `{名称, baseUrl, model, apiKey}` 配置（不同供应商/不同 key）并切换
默认——外来设计《APIKey管理与多账号切换.md》提供 ai_accounts 表 + 路由集成
蓝图，但针对固定供应商列表（deepseek/openai/...），月笙是**通用 OpenAI 兼容**
（baseUrl 自定义 + 模型预设，见 ADR-C83），需适配。

## 决策

**账号 = 命名配置 {名称, baseUrl, model, apiKey}，全局唯一默认账号**（不按
provider 分组——月笙无固定供应商概念）。

### 1. drift v28：ai_accounts 表（元信息，密钥零 DB 面）

```sql
CREATE TABLE ai_accounts (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  base_url    TEXT NOT NULL,
  model       TEXT NOT NULL,
  is_default  INTEGER NOT NULL DEFAULT 0,
  is_enabled  INTEGER NOT NULL DEFAULT 1,
  created_at  INTEGER NOT NULL DEFAULT (unixepoch())
);
```

- **api_key 不进 DB**（R-029 最小密钥面）：key 存 flutter_secure_storage 的
  JSON map（`account_id → api_key`），与现有三键同仓。
- 默认账号约束：应用层保证同表至多一个 `is_default=1`（不依赖 DB UNIQUE，
  与现有「设默认清除其他」语义一致）。
- created_at 用 unix 秒（与全库时间戳惯例一致）。

### 2. 服务层：AIAccountRepository

- `listAccounts()` / `getDefaultAccount()` / `getAccount(id)`
- `createAccount(...)`：写表 + key 入 secure storage map；首个账号自动设为默认；
  `isDefault=true` 时清除其他默认标记（同一事务）
- `setDefault(id)`：清除其他 + 置默认
- `deleteAccount(id)`：**至少保留一个**（删除后无账号则拒绝，对齐外来
  LAST_ACCOUNT 语义）；默认账号被删 → 首个剩余账号接管默认
- key map 与表行删除联动

### 3. LlmClient 配置源升级（不破坏现有接口/测试）

- `LlmClient` 构造新增可选 `Future<LlmConfigValues?> Function()? configLoader`；
  为 null 时回退现有 `_configStorage.getLlmConfig()`（旧行为，既有测试零改动）。
- 生产组装（app_providers）注入新 loader：**默认账号优先 → 无账号回退旧三键
  （兼容未迁移）**。

### 4. 旧配置迁移（幂等，读时惰性）

- loader 发现无任何账号但旧三键存在 → 自动创建「默认」账号（名称=旧 model），
  迁移后旧三键保留不删（回退安全），后续配置源只走账号。
- 不迁移的场景：旧三键为空 / 已有账号（此时旧键被忽略——账号优先）。

### 5. 设置页多账号 UI（功能入口，非视觉改造）

- 账号列表（名称 + model + 默认标记 + 启用状态）
- 添加账号表单（复用现有预设点选：选中预设自动填 baseUrl+model）
- 设默认 / 删除（至少保留一个）
- 测试连接复用 `testLlmConnection`（传选中账号配置）
- **样式沿用现有设置页视觉**（UI 视觉改造后置，批次 C）

## 被否方案

- **DB 加密列存 key**（外来原样）：引入加密依赖 + 迁移复杂度 + 密钥面扩大，
  与 R-029 冲突；secure storage 已提供系统级加密。
- **按 provider 分组 + 余额/告警**：月笙无固定供应商/无余额系统，属 D-2 范畴。

## 验证

- 六道门禁 6/6 + 全量测试
- 迁移测试：旧三键 → 自动建默认账号（幂等、不重复建）
- 路由测试：有账号走默认账号配置；无账号回退旧键
- 删除守卫：最后账号拒绝删除

## 后续（批次 D-2，未做）

- 余额查询/告警（自定义兼容端点多数无余额 API，按需评估）
- 账号级失败自动降级（现有备选端点链之上扩展）
- 免费测试账号与账号体系融合展示（批次 E-1 已有无 key 免费模式）
