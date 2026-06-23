# ID 命名规范（Yuesheng ID Naming Specification）

> **版本**: v1.0.0
> **生效日期**: 2026-06-23
> **关联**: ADR-005 / Sprint 15 T15-D / Issue #23
> **状态**: 🟡 横切规范（每个 Sprint 15 Task 末尾检查）

---

## 一、目标

统一月笙写作教练项目所有 ID 命名规则，避免：
- 同一概念多个 ID（如 P001 训练在 3 套体系中各有 ID）
- 命名混杂（ABL/AB/P/T0/TRAIN/CH/TQ/DST）
- 数据漂移（更新一处无法同步到另几处）

---

## 二、ID 命名规范

### 2.1 完整 ID 清单

| 层 | ID 格式 | 例子 | 说明 | 数量 |
|:---|:--------|:-----|:-----|:-----|
| 能力图谱节点 | `ABL-XXX` | ABL-001 | 8 个能力节点 | 8 |
| 教学原子 | `AB-XXX` | AB-003 | 教学原子节点 | 5 |
| 症候 | `P-XXX` | P001 | 写作症候 | 27（含 syndromes + mappings） |
| 训练任务（**唯一主源**） | `TRAIN-PXXX-XXX` | TRAIN-P001-001 | 教学工坊训练 | 21 |
| 基础能力训练 | `PRAC-XXXX-NNN` | PRAC-EYE-001 | 基础能力训练（观察力/笔力/词汇/结构/品味） | 8 |
| 蒸馏素材 | `DST-XXX-NNN` | DST-001-001 | 写作蒸馏素材 | 461（待索引化） |
| 技法 | `TQ-XXX` | TQ-025 | 写作技法 | (待索引化) |
| 经典原则 | `(slug)` | CHEKHOV_GUN | 文学原则（slug 格式） | (待索引化) |
| 挑战式微练 | `CH-PXXX-XXX` | CH-P001-001 | challenge-templates.json | 31 |

### 2.2 格式规范

#### 通用规则
- **全部大写**，下划线分隔（除 slug 类型外）
- **数字部分必须 ≥ 3 位**（P-001 而非 P-1，ABL-001 而非 ABL-1）
- **连字符 `-`** 分隔前缀和数字（ABL-001）
- **下划线 `_`** 分隔层级（TRAIN-P001-001）

#### 各层细节

**能力图谱节点 (ABL-XXX)**:
```
格式: ABL-{3位数字}
示例: ABL-001, ABL-007
范围: ABL-001 ~ ABL-999
位置: resources/knowledge-graph/ability-atlas.json (abilities 数组)
```

**教学原子 (AB-XXX)**:
```
格式: AB-{3位数字}
示例: AB-001, AB-005
范围: AB-001 ~ AB-999
位置: resources/02-prescription/ability-nodes/ability-node-prototypes.json
```

**症候 (P-XXX)**:
```
格式: P{3位数字}（无连字符）
示例: P001, P010
范围: P001 ~ P999
位置: resources/01-diagnosis/syndromes/*.json
备注: 历史数据使用 P001（无连字符），新数据延续
```

**训练任务 (TRAIN-PXXX-XXX)** ⭐ **唯一主源**:
```
格式: TRAIN-P{3位数字}-{3位数字}
示例: TRAIN-P001-001, TRAIN-P010-003
范围: TRAIN-P001-001 ~ TRAIN-P999-999
位置: resources/02-prescription/training-library.json
备注: 第二段数字是同一症候下的任务序号
```

**蒸馏素材 (DST-XXX-NNN)**:
```
格式: DST-{3位批次号}-{3位序号}
示例: DST-001-001, DST-003-061
范围: DST-001-001 ~ DST-999-999
位置: resources/distillation-index.json (待创建)
备注: 第一段是批次（001/002/003），第二段是同批次内序号
```

**技法 (TQ-XXX)**:
```
格式: TQ-{3位数字}
示例: TQ-025
范围: TQ-001 ~ TQ-999
位置: resources/config/technique-library.json
```

**经典原则 (slug)**:
```
格式: AUTHOR_PRINCIPLE_NAME（UPPER_SNAKE_CASE）
示例: CHEKHOV_GUN, FORSTER_ROUND, LAO_SHE_EVERYTHING_MATTERS
范围: 不限
位置: resources/config/classical-principles.json
```

**基础能力训练 (PRAC-XXXX-NNN)**:
```
格式: PRAC-{4字母类别大写}-{3位数字}
示例: PRAC-EYE-001（观察力）, PRAC-PEN-001（笔力）, PRAC-WORD-001（词汇）
类别: EYE（观察力）/PEN（笔力）/WORD（词汇）/STRUCT（结构）/TASTE（品味）
位置: resources/02-prescription/training-library.json (与 TRAIN-PXXX 并列)
备注: 基础能力训练是"无症候"训练任务，与症状解耦的底层能力练习
```

**挑战式微练 (CH-PXXX-XXX)**:
```
格式: CH-P{3位数字}-{3位数字}
示例: CH-P001-001, CH-P007-003
位置: resources/config/challenge-templates.json
备注: 通过 relatedChallengeIds 字段引用，无独立主源
```

### 2.3 旧 ID 处理

| 旧 ID | 新 ID | 关系 | 处理方式 |
|:------|:------|:-----|:--------|
| T001-T020 | TRAIN-PXXX-XXX | 合并 | ability-atlas.json 的 T001-T020 占位删除，合并入 training-library.json 的 related_abilities 字段 |
| （无） | DST-XXX-NNN | 新建 | 461 条素材新建索引 |
| P1, P-1 | P001 | 规范化 | 兼容别名 P1 ≡ P-1 ≡ P001（不在代码硬编码） |
| AB-1, AB-001 | AB-001 | 规范化 | 统一 AB-XXX 格式 |
| ABL-1, ABL-001 | ABL-001 | 规范化 | 统一 ABL-XXX 格式 |

**重要**: T15-D 是**横切规范**，不强制一次性重命名旧 ID。
- ✅ 写规范文档
- ✅ 写 lint 规则（警告而非 error）
- ⏸ 旧 ID 重命名 = 增量式，按 Task commit 末尾处理

---

## 三、ID 字段一致性检查

### 3.1 必须包含 ID 字段的 JSON 文件

```bash
# 训练工坊（主源）
resources/02-prescription/training-library.json
  → entries[].id 必须是 TRAIN-PXXX-XXX

# 挑战模板
resources/config/challenge-templates.json
  → templates[].id 必须是 CH-PXXX-XXX

# 能力图谱
resources/knowledge-graph/ability-atlas.json
  → abilities[].id 必须是 ABL-XXX
  → syndromes[].id 必须是 PXXX（无连字符）
  → training_tasks[].id 必须是 T0XX 或映射到 TRAIN-PXXX

# 教学原子
resources/02-prescription/ability-nodes/ability-node-prototypes.json
  → nodes[].id 必须是 AB-XXX

# 症候相关
resources/01-diagnosis/syndromes/syndrome-action-map.json
  → entries[].syndromeId 必须是 PXXX
resources/01-diagnosis/syndromes/syndrome-classical-map.json
  → entries[].syndromeId 必须是 PXXX

# 技法库
resources/config/technique-library.json
  → entries[].id 必须是 TQ-XXX（待索引化）

# 蒸馏素材（待创建）
resources/distillation-index.json
  → entries[].id 必须是 DST-XXX-NNN
```

### 3.2 一致性检查脚本

**脚本**: `scripts/check-id-naming.mjs`

**功能**:
1. 扫描所有 resources/ 下的 JSON 文件
2. 检查已知 ID 字段的格式
3. 不合规 → warning（不阻塞构建）
4. 统计：每种 ID 类型的数量、违规数

**使用**:
```bash
node scripts/check-id-naming.mjs
```

**输出示例**:
```
[ID Naming Check]
✅ ABL-XXX: 8/8 合规
✅ AB-XXX: 5/5 合规
✅ PXXX (syndromes): 27/27 合规
✅ TRAIN-PXXX-XXX (training-library): 21/21 合规
✅ PRAC-XXXX-NNN (training-library): 8/8 合规
✅ CH-PXXX-XXX (challenge-templates): 31/31 合规
⏳ DST-XXX-NNN (distillation): 待创建
⏳ TQ-XXX (techniques): 待索引化
```

---

## 四、ID 命名规范 Lint 规则

### 4.1 ID 命名校验函数

**位置**: `src/main/utils/id-validator.ts`

**API**:
```typescript
export type IDType = 'ABL' | 'AB' | 'P' | 'TRAIN' | 'CH' | 'DST' | 'TQ' | 'SLUG';

export function validateID(id: string, type: IDType): ValidationResult {
  // 格式校验 + 数字范围检查
  // 返回 { valid: boolean, errors: string[] }
}

export function isCompatibleID(id: string, type: IDType): boolean {
  // 兼容旧格式（如 P1 vs P001）
  // 用于过渡期
}
```

### 4.2 自动检查触发点

- **TypeScript 编译时**: 无（不阻塞构建）
- **JSON 加载时**: 软警告（loader 加载 JSON 时记录 warning，不抛错）
- **Commit 前**: `npm run lint:id` 手动运行
- **CI**: 不强制（warn only）

### 4.3 迁移工具

**位置**: `scripts/migrate-ids.mjs`

**功能**:
- 旧 ID → 新 ID 自动映射
- 兼容别名（`P1` → `P001`）
- 生成迁移报告（哪些文件被改，改了几个 ID）
- **dry-run 模式**（默认）：不修改文件，只输出报告

---

## 五、检查清单

每个 Sprint 15 Task commit 末尾必须：

```
□ ID 字段格式合规（无新增违规）
□ 旧 ID 未引入新引用（如未新增 T001 引用）
□ task-id-mapping.json 与本 Task 涉及的 ID 一致
□ 决策日志 D-035+ 记录 ID 相关决策
```

---

## 六、依据

- **ADR-005**: 训练任务单一真相源
- **dev-docs/designs/2026-06-23-diagnosis-library-remediation.md** §4.2 ID 命名规范
- **R-014**: 配置外置规范
- **R-018**: 变更溯源
- **Issue #23**: Sprint 15

---

## 七、状态

🟡 提议 → Sprint 15 Build 阶段实施 T15-D
