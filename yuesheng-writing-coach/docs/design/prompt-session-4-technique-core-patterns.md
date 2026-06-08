# 会话4提示词：技法核心化分类

## 项目背景

月笙写作教练是一个 Electron + React + SQLite 桌面应用，通过 AI 诊断用户写作问题并推荐针对性训练。技法库（technique-library.json）是系统的核心教学素材，包含 89 条从头部网文中提取的写作技法。

目前技法库的结构是扁平的——89 条技法挤在一个 JSON 数组里，没有层次关系。这将导致：
1. 推荐算法无法区分"同一模式的不同变种"
2. 教学无法根据用户水平在变种间切换
3. 系统无法感知"核心模式覆盖是否完整"

## 任务

将 89 条技法重组为 **"核心模式 + 难度变种"** 的树形结构。

## 必须读取的文件

**需要修改的目标文件：**
1. `resources/config/technique-library.json` — 当前 89 条技法
2. `src/renderer/shared/types.ts` — TechniqueInfo 接口定义（需追加新字段）
3. `docs/teaching/technique-library/index_V1.md` — 索引文档（更新为 V6.0）

**参考文件（无需修改，但需理解上下文）：**
4. `docs/design/distillation-review_V1.0.md` — 审查结果（含 5 条需标注 genreScope 的技法）
5. `docs/design/design-philosophy_V1.0.md` — 设计哲学（§3 降级规则、§8 能力图谱）
6. `docs/teaching/technique-library/technique-changjing_V1.md` — 场景类别文档
7. `docs/teaching/technique-library/technique-qingxu_V1.md` — 情绪类别文档
8. `docs/teaching/technique-library/technique-duihua_V1.md` — 对话类别文档

## 核心技法模式定义（供参考，可在执行中调整）

以下为预研得出的 10 个核心模式，每个模式包含一组技法：

| coreId | coreName | 概述 |
|--------|---------|------|
| show-dont-tell | 展示而非告知 | 把情绪/状态通过感官细节、行为、环境来暗示，不直接说出 |
| suspense-engine | 悬念驱动 | 制造信息差，让读者产生"想知道答案"的欲望 |
| pov-control | 视角控制 | 管理读者获取信息的渠道和范围 |
| structure-innovation | 结构创新 | 打破线性叙事，使用非传统结构组织故事 |
| worldbuilding-embed | 设定融入 | 把世界观设定自然地编织进故事中 |
| character-depth | 角色立体化 | 让角色有深度、有矛盾、有成长 |
| dialogue-depth | 对话层次 | 让对话承载潜台词、立场、信息 |
| rhythm-control | 节奏呼吸 | 控制叙事节奏的张弛 |
| opening-hook | 开篇钩子 | 快速制造阅读动力 |
| negative-example | 反面教材 | 展示常见错误，教识别能力 |

但以上只是预研结果，**你有权调整**——如果发现有更好的核心模式划分方式（合并/拆分/新增/改名），请按你的判断执行。

## 执行步骤

### Step 1：逐条分析 89 条技法

对每条技法，问自己三个问题：

**Q1：它属于哪个核心模式？**
- 看看它与其他技法是否有相同的底层原理
- 例如："感官替代法""环境映射法""冰山情绪法"都指向"展示而非告知"
- 如果一条技法无法归入任何现有模式，可以新建或合并模式

**Q2：它适合什么水平？**
- beginner：刚接触该领域的写作者，需要范例模板
- intermediate：有一定基础但需要精准训练
- advanced：已掌握基础，需要策略选择训练
- 参考设计哲学 §3.3 三级降级模型

**Q3：它只适用于特定类型的小说吗？**
- "通用"：几乎所有类型都适用
- 特定类型：如"超能力/奇幻""推理/悬疑""凡人流""双世界观"等

### Step 2：更新 technique-library.json

在每条技法原有字段基础上追加：

```json
{
  "id": "TQ-025",
  "name": "感官替代法",
  "coreId": "show-dont-tell",
  "coreName": "展示而非告知",
  "difficultyOrder": 2,
  "genreScope": "通用",
  ...
  // 以下为原有字段，不变
  "difficulty": "intermediate",
  "category": "情绪",
  "applicableSyndromes": ["P003"],
  "description": "...",
  "example": "...",
  "exercise": "...",
  "source": "道诡异仙",
  "sourceAuthor": "狐尾的笔"
}
```

字段说明：
- `coreId` — 核心模式标识（英文字段，如 "show-dont-tell"）
- `coreName` — 核心模式名称（中文，如 "展示而非告知"）
- `difficultyOrder` — 难度顺序：1=beginner, 2=intermediate, 3=advanced
- `genreScope` — 适用范围：通用 / 奇幻玄幻 / 推理悬疑 / 都市 / 凡人流 / 冒险奇幻 / ... 如有多标签用数组

### Step 3：更新 TechniqueInfo 接口

在 `src/renderer/shared/types.ts` 中找到 `TechniqueInfo` 接口，追加以下字段：

```typescript
export interface TechniqueInfo {
  id: string;
  name: string;
  source: string;
  difficulty: string;
  category: string;
  description: string;
  example: string;
  // ↓ 新增字段
  coreId?: string;
  coreName?: string;
  difficultyOrder?: number;
  genreScope?: string | string[];
}
```

### Step 4：更新 index_V1.md

更新 `docs/teaching/technique-library/index_V1.md` 到 V6.0，增加全新的"核心模式一览"章节：

```markdown
## 核心模式一览

| 核心模式 | coreId | 包含技法数 | beginner | intermediate | advanced | 覆盖症候 |
|---------|--------|:---------:|:--------:|:------------:|:--------:|---------|
| 展示而非告知 | show-dont-tell | 8 | 2 | 3 | 3 | P003,P010 |
| ... | ... | ... | ... | ... | ... | ... |
```

原有内容（类别汇总、书籍来源、症候-技法映射表）保留不动。

## 休止符条件

以下条件满足后，会话即可结束，返回产出文件：

| 条件 | 说明 |
|:----:|------|
| ✅ 全部 89 条技法已标注 coreId/coreName | 无遗漏 |
| ✅ 全部 89 条技法已标注 difficultyOrder | 1/2/3 无遗漏 |
| ✅ 全部 89 条技法已标注 genreScope | 含审查报告中的 5 条标注项 |
| ✅ TechniqueInfo 接口已更新 | 新增 4 个字段 |
| ✅ index_V1.md 已更新 | 新增"核心模式一览"章节 |

## 输出物

请在当前对话的**工作区**直接修改以下文件的物理内容：

| 文件 | 操作 |
|------|------|
| `resources/config/technique-library.json` | 修改（89 条追加新字段）|
| `src/renderer/shared/types.ts` | 修改（TechniqueInfo 接口追加字段）|
| `docs/teaching/technique-library/index_V1.md` | 修改（V6.0，新增核心模式一览）|

修改完成后，在操作层运行 `npx tsc --noEmit` 确认编译通过，然后返回确认。

## 核心原则

1. **不要过度细分**：核心模式数量控制在 8-12 个，每个模式至少包含 3 条技法
2. **不要生造分类**：coreId 要反映技法之间的真实关系，不是为了分类而分类
3. **如果某条技法独树一帜无法归入任何模式**：可以给它单独建一个核心模式（如 "negative-example"），但确保这个模式确实有价值
4. **核心模式命名要反映底层认知能力**：如"展示而非告知"反映的是"将抽象情绪转化为可感知细节"的认知能力，而不是"写出了好的情绪描写"
