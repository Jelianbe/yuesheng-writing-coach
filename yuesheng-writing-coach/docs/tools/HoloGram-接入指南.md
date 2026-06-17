# HoloGram 接入指南

> 用于 RWR Phase 1 全项目代码质量审计  
> 创建于 2026-06-17 | 反馈编号 FB20260617-005  
> 仓库: https://github.com/834063245-creator/HoloGram | 版本: v0.2.0 | 许可: MIT

---

## 1. 工具能力

HoloGram 是一个**语言无关的交互式代码依赖拓扑图生成器**，把代码库变成一张可对话的 3D 星图。

| 核心能力 | 描述 |
|---------|------|
| **18 门语言统一 IR** | TypeScript/JavaScript/Rust/Go/Python/Java/C/C++/Ruby/Lua/C#/Swift/Dart/Scala/Haskell/JSON/HTML/CSS — 全部映射到同一张图 |
| **24 个原生工具** | explore / neighbors / impact / path / coupling-report / blindspots / cycle / fragile / community / history / search / check / preflight / health / diff / timeline / ... |
| **L1-L4 耦合诊断** | L1 公开 API → L2 封装穿透 → L3 数据流环 → L4 线程冲突/盲点 |
| **5 级变更破坏信号** | YAML 阈值门禁，评估改动的破坏半径 |
| **3D 星图** | 力导向 + BloomPass 发光 + 全息网格 Shader + 粒子流动 |
| **293 个 Rust 单测** | 引擎自举 |

---

## 2. 适用场景

| 月笙规则 | HoloGram 工具 | 价值 |
|---------|--------------|------|
| **R-020 循环依赖零容忍** | cycle / fragile | 自动检测 + 风险标红 |
| **R-018 变更溯源** | impact / path / neighbors | 自动评估改动影响半径 |
| **R-007 双向绑定** | community | 识别业务模块边界 |
| **R-010 最小化范围** | diff / preflight | 改前预演变更影响 |
| **R-019 代码规范** | check / health | YAML 约束门禁 |
| **R-011 记忆强化** | history / timeline | 自动追踪决策时间轴 |

---

## 3. 安装步骤（Windows）

### 3.1 下载安装包

HoloGram v0.2.0 安装包已下载到本项目 `docs/tools/releases/` 目录：

| 文件 | 大小 | SHA256 |
|------|------|--------|
| `HoloGram-0.2.0-x64_zh-CN.msi` | 12.3 MB | `b40005611894de1e21cf24f0029f4ca2bd285d50ce704eed731811bd17b34729` |

### 3.2 双击安装

1. 打开资源管理器，进入 `d:\ai-teacher\yuesheng-writing-coach\docs\tools\releases\`
2. 双击 `HoloGram-0.2.0-x64_zh-CN.msi`
3. 按安装向导完成（默认 Next → Next → Install → Finish）
4. 安装位置：`C:\Program Files\HoloGram\`

### 3.3 启动 HoloGram

- **桌面快捷方式**：双击桌面的 HoloGram 图标
- **开始菜单**：开始 → HoloGram → HoloGram
- **命令行**：`C:\Program Files\HoloGram\hologram.exe`

启动后会：
- 自动 spawn `hologram-engine.exe`（Rust 引擎）
- 引擎在 TCP :9777 提供 JSON-RPC 服务
- 桌面应用连接引擎后渲染 3D 星图

### 3.4 打开 RWR Phase 1 项目

1. 启动 HoloGram 后，菜单 → `File` → `Open Project`
2. 选择 `d:\ai-teacher\yuesheng-writing-coach` 目录
3. 引擎自动分析（首次约 30-60 秒，增量 < 2 秒）
4. 3D 星图渲染完成

---

## 4. MCP 集成（可选,用于 IDE 内调用）

HoloGram v0.2.0 提供 **21 个 MCP 工具**，可被 Claude Code / Cursor / Trae 等 AI IDE 集成。

### 4.1 全局 MCP 配置（推荐）

位置：`%USERPROFILE%\.claude\mcp.json`（Windows）或 `~/.claude/mcp.json`（macOS/Linux）

```json
{
  "mcpServers": {
    "hologram": {
      "command": "C:\\Program Files\\HoloGram\\hologram-engine.exe",
      "args": ["serve"],
      "env": {
        "HOLOGRAM_PROJECT_ROOT": "d:\\ai-teacher\\yuesheng-writing-coach"
      }
    }
  }
}
```

### 4.2 项目级 MCP 配置

位置：项目根目录 `.mcp.json`

```json
{
  "mcpServers": {
    "hologram": {
      "command": "C:\\Program Files\\HoloGram\\hologram-engine.exe",
      "args": ["serve", "--project-root", "d:\\ai-teacher\\yuesheng-writing-coach"]
    }
  }
}
```

### 4.3 重启 IDE 后验证

- Claude Code: 输入 `mcp list` 应显示 hologram
- Cursor: Settings → MCP 应显示 21 个工具
- Trae: 工具面板应出现 hologram 工具

---

## 5. 24 个工具速查表

### 5.1 图查询工具（18 个）

| 工具 | 用途 | 月笙适用规则 |
|------|------|-------------|
| `hologram_explore` | 自然语言查询依赖链 | R-018 / R-007 |
| `hologram_neighbors` | 查询直接邻居节点 | R-020 |
| `hologram_impact` | 评估修改的爆炸半径 | R-018 / R-010 |
| `hologram_path` | 两节点最短路径 | R-020 |
| `hologram_coupling_report` | 全项目耦合度报告 | R-020 / R-007 |
| `hologram_blindspots` | 发现测试覆盖盲点 | R-013 |
| `hologram_cycle` | 循环依赖检测 | R-020 |
| `hologram_fragile` | 脆弱节点（高 fan-in）| R-010 |
| `hologram_community` | 模块社区划分 | R-007 |
| `hologram_history` | 节点变更历史 | R-011 |
| `hologram_search` | 全文本搜索（SQLite FTS5）| 通用 |
| `hologram_check` | YAML 约束门禁检查 | R-019 |
| `hologram_preflight` | 改前预演 | R-010 / R-018 |
| `hologram_health` | 项目健康度评分 | 通用 |
| `hologram_diff` | diff 模式 | R-010 |
| `hologram_timeline` | 决策时间轴 | R-011 |
| `hologram_flow` | 数据流追踪 | R-007 / R-020 |
| `hologram_blast` | 波及范围可视化 | R-018 |

### 5.2 编码工具（19 个）

文件读写、Shell、Git、WebFetch — 通用 IDE 工具，HoloGram Agent 自带。

### 5.3 记忆工具（4 个）

`memory_list` / `memory_read` / `memory_save` / `memory_delete` — 跨会话持久化。

---

## 6. 5 级变更破坏信号

HoloGram 在 `hologram_check` 中使用 5 级破坏信号评估改动：

| 级别 | 含义 | 触发条件 | 月笙对应 |
|------|------|---------|---------|
| **L1** | 信息提示 | 改名/注释 | - |
| **L2** | 内部 API 变动 | 内部函数签名变 | R-010 |
| **L3** | 公开 API 变动 | 导出函数签名变 | R-019 |
| **L4** | 数据流破坏 | 上下游类型不一致 | R-020 / R-007 |
| **L5** | 不可逆破坏 | 数据库迁移 + 删除 | R-018 |

**RWR Phase 1 实战**：每次 commit 前运行 `hologram_check`，确保变更 ≤ L3。

---

## 7. 实战：审计 RWR Phase 1

### 7.1 全项目健康度

```
hologram_health(path="d:\ai-teacher\yuesheng-writing-coach")
```

输出示例：
```json
{
  "health_score": 78,
  "total_files": 274,
  "cycles": 0,
  "fragile_nodes": 5,
  "blindspots": 12,
  "coupling_avg": 3.2
}
```

### 7.2 循环依赖扫描

```
hologram_cycle(path="d:\ai-teacher\yuesheng-writing-coach")
```

R-020 要求 0 循环，若 > 0 立即处理。

### 7.3 脆弱节点

```
hologram_fragile(path="d:\ai-teacher\yuesheng-writing-coach", top_n=10)
```

高 fan-in 节点优先处理。

### 7.4 改动前预演

```
hologram_preflight(path="d:\ai-teacher\yuesheng-writing-coach", diff="...")
```

5 级破坏信号 + 影响范围 + 冲突预演。

### 7.5 社区划分

```
hologram_community(path="d:\ai-teacher\yuesheng-writing-coach")
```

识别业务模块边界，验证 R-007 双向绑定。

---

## 8. 常见问题

### Q1: 安装失败 / 启动崩溃
- 检查 WebView2 是否安装（Win10+ 预装，Win7 需手动装）
- 检查防火墙是否阻止 TCP:9777
- 查看 `%APPDATA%\HoloGram\logs\` 日志

### Q2: 星图渲染卡顿
- 超过 5000 节点自动降级为文件级图
- 关闭 BloomPass 特效（菜单 → View → Effects）
- 缩小窗口临时使用轻量模式

### Q3: MCP 工具不显示
- 确认 `hologram-engine.exe serve` 可独立启动
- 检查 `.mcp.json` 路径是否正确
- 重启 IDE（Trae / Cursor / Claude Code）

### Q4: 与月笙规则冲突
- HoloGram 工具是**只读**审计工具，不改代码
- YAML 约束在 `hologram_check` 中可自定义
- 报告不强制 gate，可作为 R-030 输入

---

## 9. 维护信息

| 项目 | 内容 |
|------|------|
| **官方仓库** | https://github.com/834063245-creator/HoloGram |
| **最新版本** | v0.2.0（2026-06-15）|
| **本项目安装包** | `docs/tools/releases/HoloGram-0.2.0-x64_zh-CN.msi` |
| **校验信息** | SHA256: b40005611894de1e21cf24f0029f4ca2bd285d50ce704eed731811bd17b34729 |
| **月笙适配点** | 6 条核心规则 + 24 个工具对应 |
| **下次升级** | HoloGram 升级 v0.3.0 时同步更新本指南 |

---

## 10. 后续 R-030 任务

HoloGram 接入基础设施（FB20260617-005）完成后，可启动以下 R-030 任务：

1. **R-031 全项目代码质量审计**（基于本指南 Step 7）
2. **R-032 R-020 循环依赖硬扫描**（hologram_cycle 结果驱动的修复）
3. **R-033 R-019 YAML 约束文件编写**（hologram_check 的 rules.yaml）
4. **R-034 5 级破坏信号 + commit gate**（hologram_preflight 集成到 R-030 工作流）
