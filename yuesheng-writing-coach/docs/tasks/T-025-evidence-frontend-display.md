# T-025: 前端证据原文引用展示

> **优先级**: P1 | **状态**: done | **预估**: 1.5d
> **依赖**: — | **后续**: —（可独立推进，不依赖其他任务）

## 目标

让用户在诊断面板中看到"为什么这样诊断"。当前 SQLite 中 `evidence_records` 表已完整存储 keyPassages 原文引用，但前端 `DiagnosisCard` 只展示 `syndrome.evidence` 截断字符串（最多 50 字），用户看不到原文证据。本任务将证据原文引用链路从数据库打通到前端展示。

## 设计依据

- **技术规格**: [SPEC_Evidence_V1.md](../specs/SPEC_Evidence_V1.md)
- **关联发现**: system-scan-report_V1.0.md §6.2（引用链路完整，但前端未消费）
- **来源任务**: T-004（诊断持久化）、T-021.1（证据系统重构）
- **已有资源**:
  - SQLite `evidence_records` 表 + `diagnosis_evidence` 关联表 — 数据完整
  - `src/main/services/evidence.service.ts` — 证据查询服务
  - `src/main/ipc/evidence.handler.ts` — 证据 IPC 通道
  - `src/renderer/components/diagnosis/DiagnosisCard.tsx` — 现有诊断卡片组件

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 新增 getEvidenceBySyndrome IPC：按 syndromeId + sessionId 查询原文证据 | `src/main/ipc/evidence.handler.ts` |
| 后端 | 以上查询依赖 evidence.service.ts 已有方法或新增 | `src/main/services/evidence.service.ts` |
| 前端 | DiagnosisCard 展开区新增 "原文证据" 区块，展示 keyPassages | `src/renderer/components/diagnosis/DiagnosisCard.tsx` |
| 前端 | 证据交叉引用：同一段原文被多个症候引用时展示关联标记 | 同上 |
| 前端 | 诊断详情 Store 层新增 evidence 数据管理 | `src/renderer/stores/diag.store.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/ipc/evidence.handler.ts` | 修改 | 新增 getEvidenceBySyndrome IPC，参数 { syndromeId, sessionId }，返回 EvidenceItem[] |
| 2 | `src/main/services/evidence.service.ts` | 修改 | 新增 getBySyndrome(syndromeId, sessionId) 方法，按 evidence.relatedDisease 查询 |
| 3 | `src/renderer/components/diagnosis/DiagnosisCard.tsx` | 修改 | 症候详情展开区新增 "原文证据" 区块，展示 { text: 原文片段, issue: 问题描述 } |
| 4 | `src/renderer/stores/diag.store.ts` | 修改 | 新增 evidenceMap: Map<string, EvidenceItem[]> 状态，按 syndromeId 索引 |

## 交互设计

### DiagnosisCard 展开态（新增区块）

```
┌─ P001 世界观膨胀 · L3 ── [收起] ─┐
│                                   │
│ 你的故事设定很丰富，但...          │
│                                   │
│ ┌─ 原文证据 ──────────────────┐  │
│ │ 📝 "在这片大陆上，有五个     │  │
│ │    王国：精灵、矮人、人类..." │  │
│ │ ⚠️ 前两段直接铺陈了三个种族  │  │
│ │    的设定，没有融入故事      │  │
│ ├─────────────────────────────┤  │
│ │ 📝 "精灵族擅长魔法，矮人族   │  │
│ │    擅长锻造，兽人族..."     │  │
│ │ ⚠️ 同样是说明性文字，可以    │  │
│ │    通过角色互动来展现       │  │
│ └─────────────────────────────┘  │
│                                   │
│ [尝试修改]                         │
└───────────────────────────────────┘
```

### 交叉引用

同一段原文被多个症候引用时，在证据右上角标记：

```
📝 "他很紧张，心里充满了不安"
   ⚠️ P003 情绪标签化 · P002 角色工具人化
```

## 数据流

```
DiagnosisCard 展开
    │
    ├─ 从 diag.store.evidenceMap 查缓存
    │   └─ 命中 → 直接展示
    │
    └─ 未命中 → window.electronAPI.getEvidenceBySyndrome(syndromeId, sessionId)
        │
        ▼
    evidence.service.getBySyndrome()
        │
        ▼
    SQLite: SELECT * FROM evidence_records er
            JOIN diagnosis_evidence de ON er.evidenceId = de.evidenceId
            WHERE er.relatedDisease = ? AND de.diagnosisId IN (subquery)
        │
        ▼
    返回: [{ text: string, issue: string, linkType: 'primary'|'supporting' }]
        │
        ▼
    DiagnosisCard 展示原文证据区块
```

## DoD（完成标准）

- [x] S1. 点击任意症候卡片可展开至少一条原文证据引用（含 "原文片段" 和 "问题描述"）
- [x] S2. 证据数据来自 SQLite 的 evidence_records 表（通过 IPC 查询），而非 AI 回复中截断的字符串
- [x] S3. 同一段原文被多个症候引用时，证据区域展示交叉引用标记

## 回退方案

1. IPC 通道保留但前端不调用：证据区块使用 feature flag 控制显示
2. 数据库查询兜底：evidence.service 查询失败时返回空数组，前端显示 "暂无原文引用"
3. 证据缓存：首次查询后缓存到 diag.store，避免重复查询

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `src/main/services/evidence.service.ts` | 新增 getBySyndrome(syndromeId, sessionId) 方法，JOIN diagnosis_evidence + diagnosis_results |
| `src/main/ipc/evidence.handler.ts` | 新增 EVIDENCE_GET_BY_SYNDROME IPC handler |
| `src/shared/constants.ts` | 新增 EVIDENCE_GET_BY_SYNDROME 通道常量 |
| `src/renderer/stores/diag.store.ts` | 新增 evidenceMap + loadEvidence + getEvidence，带缓存机制 |
| `src/renderer/components/diagnosis/DiagnosisCard.tsx` | 新增 OriginalEvidenceSection 组件，替换旧 evidence 区块，支持交叉引用 |
| `src/renderer/components/diagnosis/DiagnosisCard.test.tsx` | 更新证据测试用例 |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit` → 0 errors）
- [x] 测试通过（`npx vitest run` → 38 files, 439 tests passed）

## 下个任务建议

T-027（症候变种标注），证据展示完善后，用户能看到"诊断了什么"和"为什么诊断"，接下来是提升诊断精度。
