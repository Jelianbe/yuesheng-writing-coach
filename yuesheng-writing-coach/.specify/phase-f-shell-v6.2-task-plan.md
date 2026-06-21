# 月笙写作教练 — 前端 Shell V6.2 后续建设任务合集

**基线版本**: V6.2  
**基线文件**: `dev-docs/previews/phase-f-shell-v6.2.html`  
**创建日期**: 2026-06-18  
**状态**: approved

---

## 当前状态（V6.2 已验证功能）

### 布局架构
- [x] 三栏布局（左栏 / 中间 / 右栏）
- [x] 左栏收起/展开（点击 ☰ / 拖动 resize handle）
- [x] 右栏收起/展开（点击 ⤢ / 拖动 resize handle）
- [x] 拖动缩放（左右栏均有 resize handle）
- [x] 左栏收起态：月 [☰] [▼ 当前项目 ▾] 拼接在左上角
- [x] 右栏收起态：[＋][⚙] [⤢][─][□][✕] 在右上角拼接

### 左栏
- [x] [对话] / [项目] 两个 tab 切换
- [x] 搜索框（占位）
- [x] 会话列表（mock 数据）
- [x] 项目列表（mock 数据）
- [x] tab 切换清空选中状态

### 中间栏
- [x] header：项目名称 + 状态徽章 / 态度灯
- [x] 聊天消息展示（mock 数据）
- [x] 输入框 + 发送按钮（占位）
- [x] 态度档位指示灯（豆包 / 月笙如歌 / sensei）
- [x] 锁定按钮

### 右栏
- [x] header 标签栏（#toolTabs）+ [＋][⤢][─][□][✕]
- [x] 子标签栏（#subTabs），始终可见
- [x] 工作区（#rightBody）
- [x] 工具网格：技法目录 / 教学进度 / 学习日志 / 作品 / 教学笔记 / 设置
- [x] 技法目录子标签导航（点击核心→建子标签→切换）
- [x] 作品工具全屏工作区（flex fill + 滚动）
- [x] 项目章节子标签（点选项目后新建子标签，可切换）
- [x] 水平滚轮滑动（#toolTabs + #subTabs）

### 数据层
- [x] 技法目录：10 个核心组 × 3 技法 = 30 个技法（mock）
- [x] 项目列表：10 章 mock 数据
- [x] 会话列表：5 个 mock 会话
- [x] 教学状态：PhaseProgress 0.65 mock
- [x] 能力画像示意

### IPC 合约（已定义）
- [x] `training:catalog` — `TechniqueInfo` / `TechniqueCatalogGroup` / `TrainingCatalogRequest/Response`
- [x] `src/shared/types/types-training.ts` — 类型扩展
- [x] `src/shared/api-contracts/training.contract.ts` — 合约定义
- [x] `src/shared/constants.ts` — `TRAINING_CATALOG` 通道名

---

## 后续建设序列

---

### Phase G: 功能填充（让预览可交互）

**DoD**:
- 所有点击操作产生可见的界面响应
- 会话切换正确渲染对应消息
- 项目点击正确展示章节内容
- 技法目录选中后打开子标签详情

#### G-01 会话点击联动
- 左侧点击会话 → `chatSessionId` 更新
- 中间栏渲染该会话的对应消息列表
- 当前操作的 mock 数据需要体现不同会话的不同消息

#### G-02 训练历史选中
- 左侧训练列表（[对话] tab 下）点击训练项
- 中间栏展示对应训练对话
- 中间 header 显示训练名称

#### G-03 项目章节联动
- 左侧 [项目] tab → 点击项目
- 右侧作品工具打开，展示对应章节内容
- 不同章节展示不同正文 mock 内容

#### G-04 技法目录子标签展开详情
- 子标签点击技法 → 工作区展示技法详情（名称、难度、类别、说明）
- 技法详情需填充有意义的 mock 内容
- 活动子标签高亮

#### G-05 右侧工具切换联动
- 切换 #toolTabs 标签 → 工作区渲染对应工具内容
- 每个工具有基本的占位内容（名称+描述+占位图/表）

---

### Phase H: 训练模块深度实现

**DoD**:
- 技法目录完整操作链路跑通
- 教学进度工具展示可读数据
- 学习日志展示能力变化趋势

#### H-01 技法目录完整流程
- 点击技法 → 新建训练会话
- 训练界面展示：技法名称、目标、当前 phase、对话区
- 基本训练交互（用户输入 → mock 教练回复）

#### H-02 教学进度工具（◐）
- PhaseProgress 可视化（进度条/阶段示意）
- 当前技法进度、总体进度

#### H-03 学习日志工具（✎）
- 能力倾向聚合展示（雷达图/柱状图）
- 训练历史统计

#### H-04 教学笔记工具
- 训练记录列表
- 诊断结果展示
- 教练建议汇总

---

### Phase I: 后端集成

**DoD**:
- 至少一个 IPC 通道从 mock 切换为真实调用
- 前端预览可对接真实后端数据

#### I-01 `training:catalog` IPC 对接
- 替换 `TECHNIQUE_CATALOG` mock 为 `window.electronAPI.invoke('training:catalog')` 调用
- 错误处理和 fallback 到 mock

#### I-02 会话 IPC 对接
- `session:list` → 替换会话列表
- `session:getMessages` → 加载消息

#### I-03 诊断引擎 IPC 对接
- `diagnosis:analyze` → 替换诊断数据
- 诊断结果在右栏展示

#### I-04 配置 IPC 对接
- `config:getApiKey` / `config:setApiKey` → 设置工具对接

---

### Phase J: React 迁移

**DoD**:
- 主界面组件化完成
- Zustand Store 接管状态
- 构建通过（`npm run typecheck && npm run test && npm run lint`）

#### J-01 组件拆分
```
src/renderer/components/
├── layout/
│   ├── LeftPanel.tsx          # 左栏（对话/项目 tab + 列表）
│   ├── CenterPanel.tsx        # 中间栏（header + 消息 + 输入区）
│   ├── RightPanel.tsx         # 右栏（tool tabs + sub tabs + workspace）
│   └── AppShell.tsx           # 三栏容器 + resize handles
├── left/
│   ├── SessionList.tsx        # 会话列表
│   ├── ProjectList.tsx        # 项目列表
│   └── LeftHeader.tsx         # 月笙图标 + 收起键 + 项目选择
├── center/
│   ├── ChatMessages.tsx       # 消息列表
│   ├── ChatInput.tsx          # 输入框 + 发送
│   └── AttitudeLights.tsx     # 态度灯
├── right/
│   ├── ToolTabs.tsx           # header 标签栏
│   ├── SubTabs.tsx            # 子标签栏
│   ├── ToolGrid.tsx           # 工具网格
│   ├── CatalogWorkspace.tsx   # 技法目录工作区
│   └── WorksWorkspace.tsx     # 作品工作区
```

#### J-02 Zustand Store
```typescript
interface UIStore {
  // 面板状态
  leftCollapsed: boolean;
  rightCollapsed: boolean;
  leftWidth: number;
  rightWidth: number;

  // 左栏
  leftTab: 'chat' | 'proj';
  selectedSessionId: string | null;
  selectedProjectId: string | null;

  // 右栏
  openTools: string[];
  activeToolId: string | null;
  openSubTabs: string[];
  activeSubTabId: string | null;
  showingCatalog: boolean;

  // 中间
  messages: Message[];
  attitude: 'doubao' | 'yuesheng' | 'sensei';
  attitudeLocked: boolean;
}
```

#### J-03 CSS Modules + Design Tokens
- 将 `:root` 变量移到 `variables.css`
- 每个组件对应 `.module.css`
- `panel-trans`、`cscroll`、`small-scroll` 等通用类移入全局

#### J-04 IPC 集成层
- Type-safe IPC 调用 hook（`useIpc`）
- 错误处理和 loading 状态
- Electron API 类型声明

---

### Phase K: 打磨与收尾

**DoD**:
- 预览版 V1.0 可运行
- 所有已知占位功能标记为"待实现"

#### K-01 交互细节打磨
- 动画过渡优化
- 拖动 resize 体验提升
- 空状态展示

#### K-02 已知缺陷修复
- tri-fork 卡片不可点击
- 发送按钮无效
- 搜索框无功能
- [template] 按钮无操作
- 中间 header [+][⚙] 无操作

#### K-03 性能优化
- 渲染性能（`renderAll` → 增量更新）
- 大数据量列表虚拟滚动

---

## 文件索引

| 文件 | 用途 |
|------|------|
| `dev-docs/previews/phase-f-shell-v6.2.html` | **当前基线** — 完整前端预览 |
| `.specify/phase-f-shell-v6.2-task-plan.md` | 本文档 — 任务合集 |
| `src/shared/constants.ts` | IPC 通道常量 |
| `src/shared/types/types-training.ts` | 训练模块类型 |
| `src/shared/api-contracts/training.contract.ts` | training:catalog 合约 |
| `src/shared/api-contracts/index.ts` | API 合约导出 |
| `.specify/constitution.md` | 项目原则 |
| `.specify/project-brief.md` | 项目概览 |

---

## 版本历史

| 版本 | 日期 | 变更说明 |
|------|------|---------|
| V1.0 | 2026-06-18 | 创建，基于 V6.2 基线拆解 Phases G-K |
