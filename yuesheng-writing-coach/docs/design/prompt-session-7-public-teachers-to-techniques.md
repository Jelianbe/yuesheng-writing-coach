# 会话7提示词：外部教学资源→技法库补充

## 项目背景

月笙写作教练的技法库（technique-library.json）已有 89 条技法，全部来自小说作品（TQ/TC/TN 编号），覆盖 10 个核心模式。但这些技法只回答了"从小说里看出什么技法"，没有覆盖"写作老师/博主/大神作者公开教学中的技法"。

会话6（教学策略蒸馏）已经从外部公开教学资源中提取了教学方法（HOW TO TEACH），但那些资源中同样包含大量的**写作创作技法**（WHAT TO TEACH）：
- 白蘸糖分享的"核心梗设计"、"剧情循环模式"、"金手指设计法"
- 阅文大神课程中的人物塑造、世界观构建、伏笔三分法
- 狂更猫课程中的"爽点设计"、"情绪拉扯"、"期待感管理"
- 踏歌的五步法中"摄像机思维"、"放大镜读书"

这些是需要注入 `technique-library.json` 的补充技法，编号使用 **TE（Teaching External）** 前缀。

## 任务

从会话6蒸馏结果（public-writing-teachers-distillation_V1.0.md）和直接搜索以下来源，提取写作创作技法，追加到 technique-library.json。

## 必须读取的文件

1. `resources/config/technique-library.json` — 现有技法库（追加目标）
2. `docs/research/public-writing-teachers-distillation_V1.0.md` — 会话6蒸馏报告（从中提取写作技法和可参考的教学内容）
3. `docs/teaching/technique-library/index_V1.md` — 技法库索引（V6.0，含核心模式一览）
4. `src/renderer/shared/types.ts` — `TechniqueInfo` 接口定义

## 蒸馏来源清单

### 来源A：白蘸糖/白特慢啊——核心写作技法

**资源**：NGA/龙空网友整理的经验文本（B站视频转录）

可提取技法：
| 技法主题 | 核心内容 | 可能对应核心模式 |
|---------|---------|----------------|
| 核心梗设计法 | 不是制造悬念，而是制造"意料之内的惊喜" | structure-innovation |
| 剧情循环模式 | 获取信息→筛选运用→触发事件→升级反馈 | rhythm-control |
| 人设非正常化 | 人设是异于常人的点，不是正常人的道德准则 | character-depth |
| 金手指"信息有用"原则 | 给主角的信息必须能让读者看到"收获" | opening-hook |
| 开篇减法法则 | 开篇元素过多=全部没表达，减到只剩1个核心 | opening-hook |
| 逻辑链条强化 | 主角行为必须与设定/水平自洽 | character-depth |

### 来源B：阅文起点创作学堂——大神写作技法

| 讲师 | 技法主题 | 可能对应核心模式 |
|:----:|---------|----------------|
| 爱潜水的乌贼 | 世界观构建密码：地理/历史/文化/政治/科技/社会六维度 | worldbuilding-embed |
| 古羲 | 情绪七法：七情六欲在网文中的释放节奏 | show-dont-tell |
| 愤怒的乌贼 | 伏笔三分法：透明/半透明/不透明 | suspense-engine |
| 鹿时七 | "结与解"框架：铺垫伏笔→多重反转→翘起来的结尾 | structure-innovation |
| 十万菜团 | 剧情流四要素：切入点/身份身世/矛盾/四大元素 | rhythm-control |
| 烽仙 | 三重期待设计法：单一期待→多重期待→地图转换 | suspense-engine |
| 红刺北（网文周） | OOC处理机制：角色行为准则表 | character-depth |
| 横扫天涯（网文周） | "完成比完美重要一万倍"——完本心态技法 | 综合 |

### 来源C：公开文章/教程——实用写作技法

| 来源 | 技法主题 | 可能对应核心模式 |
|------|---------|----------------|
| 踏歌爱写作 | 摄像机思维：把"描写"转化为"拍摄" | show-dont-tell |
| 踏歌爱写作 | 微任务分解：单点突破替代全局压力 | 综合（教学方法） |
| 知乎过稿教程 | 开篇即战场：300字钩子法 | opening-hook |
| 知乎过稿教程 | 冲突升级滚雪球：大冲突→小冲突→连环套路 | suspense-engine |
| 新手行动派学习法 | 三级大纲法：根大纲→分卷→章纲 | structure-innovation |
| 新手行动派学习法 | 签约及格线：3000字立人设+抛冲突+留钩子 | opening-hook |

### 来源D：英文创意写作技法（补充参考）

| 资源 | 技法主题 |
|------|---------|
| LearningMole | 五元素教学法：角色/场景/情节/冲突/主题 |
| WriteOnWithMissG | Memory BINGO：记忆提取写作法 |
| FunFox | 小说结构15法：强力开篇 + 满足结局 + 角色弧光 |

### 来源E：狂更猫/千夜等——市场导向写作技法

| 来源 | 技法主题 | 可能对应核心模式 |
|------|---------|----------------|
| 狂更猫 | 爽点密度控制：每3000字一个小爽点/反转 | rhythm-control |
| 狂更猫 | 期待感管理：让读者知道主角要干什么+为什么要干+能干成多爽 | suspense-engine |
| 作家千夜 | 十种经典故事类型（救猫咪模型） | structure-innovation |
| 作家千夜 | 起承转合大纲四步法 | structure-innovation |

## 执行步骤

### Step 1：提取写作技法

对每个来源，逐条提取：

每条技法至少包含：
```json
{
  "id": "TE-001",
  "name": "技法中文名",
  "source": "教学资源来源",
  "sourceType": "public_teaching",
  "sourceAuthor": "原作者/讲师名",
  "difficulty": "beginner | intermediate | advanced",
  "category": "开篇 | 节奏 | 人物 | 世界观 | 情绪 | 对话 | 场景",
  "applicableSyndromes": ["P001", "P002"],
  "description": "技法描述（100-200字）",
  "coreIdea": "技法的核心一句话",
  "teachingLogic": "原作者是如何教这个技法的（提取其教学逻辑）",
  "example": "示例",
  "exercise": "练习建议",
  "coreId": "对应的核心模式ID",
  "coreName": "对应的核心模式名",
  "difficultyOrder": 1,
  "genreScope": ["通用"]
}
```

注意新增字段：
- `sourceType`: 固定值 `"public_teaching"`，方便与从小说的技法区分
- `sourceAuthor`: 原作者/讲师名
- `teachingLogic`: 这个技法的教学逻辑（原作者是怎么教的）
- `coreIdea`: 技法的核心一句话

### Step 2：编号规则

使用 TE 前缀（Teaching External），从 TE-001 开始顺延。

现有编号区间：
- TQ-001~TQ-077：小说技法（开篇/节奏/人物/世界观/情绪）
- TC-001~TC-015：小说技法（对话/场景）
- TN-001：反面教材

新技法：**TE-001~TE-XXX**

### Step 3：追加到 technique-library.json

直接追加到现有 JSON 数组末尾。保持 `TechniqueInfo` 接口兼容。

### Step 4：更新 index_V1.md

在 V6.0 的基础上：
- 新增"外部教学资源技法"章节
- 新增 TE 系列的统计

### Step 5：验证

运行 `npx tsc --noEmit` 确认编译通过。

## 注意事项

1. **不重复**：检查现有 89 条技法，避免与已有 TQ/TC 技法重复。如果已有高度相似的技法（如"视角锚定物法"和新提取的"摄像机思维"），考虑合并或标注为"补充角度"
2. **教学逻辑优先**：TE 系列的价值不在于技法本身（已有的 TQ 系列可能已经覆盖），而在于**原作者教这个技法的逻辑**。比如"摄像机思维"这个技法在教学上比"环境映射法"更容易让新手理解
3. **中等难度优先**：现有技法 beginner 偏多，TE 系列尽量补充 intermediate 和 advanced 级别
4. **来源可追溯**：每条技法标注 sourceType 和 sourceAuthor

## 休止符条件

| 条件 | 说明 |
|:----:|------|
| ✅ 至少提取 15 条新技法 | 编号 TE-001~TE-015+ |
| ✅ 覆盖至少 10 个外部来源 | 来源A~来源E 各至少 2 条 |
| ✅ 每技法含 teachingLogic 字段 | 这是 TE 系列的核心价值 |
| ✅ 追加到 technique-library.json | JSON 数组格式正确 |
| ✅ index_V1.md 已更新 | 新增 TE 系列章节 |
| ✅ npx tsc --noEmit 通过 | |

## 输出物

| 文件 | 操作 |
|------|------|
| `resources/config/technique-library.json` | **修改**（追加 TE-001~TE-XXX）|
| `docs/teaching/technique-library/index_V1.md` | **修改**（升级标记，新增 TE 系列统计）|

改完运行 `npx tsc --noEmit` 确认编译通过。

## 核心原则

1. **区分"技法"和"教法"**：这个会话只提取"技法"（WHAT TO TEACH），不提取"教法"（HOW TO TEACH）——教法已经在会话6中处理。例如："摄像机思维"是技法，"用三步引导学生掌握摄像机思维"才是教法
2. **教学逻辑是核心附加值**：TE-001 和 TQ-025 可能教同样的技巧（如"用感官替代抽象"），但 TE-001 多了一个 `teachingLogic` 字段——原作者是怎么让学生理解的
3. **宁少勿滥**：只提取高质量的、真正有用的技法。如果某个来源的内容过于水（如纯商业推广），跳过
