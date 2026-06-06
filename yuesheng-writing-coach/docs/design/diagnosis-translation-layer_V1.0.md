# T-015 翻译层设计

> **对应发现**：发现4 — 诊断面板违反理念  
> **优先级**：P1  
> **工作量**：1天  
> **依赖**：T-012（右侧栏数据同步）✅  
> **前端改动**：RightPanel.tsx

---

## 一、问题

右侧栏诊断发现直接展示内部术语：

```
P001 世界观膨胀 [L2]
P004 信息硬塞 [L1]
```

违反 V1.0 铁律：**"不向用户输出 Layer 1 的诊断结果（评分、病症编号、诊断报告）"**。

## 二、目标

将内部诊断结果翻译为用户可理解的自然语言：

| 内部 | 用户看到的 |
|------|-----------|
| P001 世界观膨胀 L2 | "你的故事设定很丰富，但主角出场还不够清晰" |
| P004 信息硬塞 L1 | "故事开头信息量稍大，可以试着让角色带出设定" |
| severity: L2 | 标签颜色橙（不显示文字）|

## 三、设计

### 3.1 翻译函数

```typescript
interface UserFacingDiagnosis {
  /** 用户友好的症候名（正面表述） */
  name: string;
  /** 教练语言的描述 */
  description: string;
  /** 严重度等级（仅用颜色表示，不显示文字） */
  severityLevel: 'mild' | 'moderate' | 'severe';
}

function diagnosisToUserFacing(syndrome: {
  id: string;
  severity: 'L1' | 'L2' | 'L3';
}): UserFacingDiagnosis {
  const translation = DIAGNOSIS_TRANSLATIONS[syndrome.id];
  if (!translation) {
    return {
      name: syndrome.id,
      description: '',
      severityLevel: 'mild',
    };
  }

  const severityColor: Record<string, 'mild' | 'moderate' | 'severe'> = {
    L1: 'mild',
    L2: 'moderate',
    L3: 'severe',
  };

  return {
    name: translation.name,
    description: translation.description[syndrome.severity] ?? translation.description.default,
    severityLevel: severityColor[syndrome.severity],
  };
}
```

### 3.2 翻译映射表

```typescript
const DIAGNOSIS_TRANSLATIONS: Record<string, {
  name: string;
  description: { L1?: string; L2?: string; L3?: string; default: string };
}> = {
  P001: {
    name: '你的故事设定很丰富',
    description: {
      L1: '开场可以试着先展示主角的日常',
      L2: '但主角的出场还不太清晰',
      L3: '建议先聚焦第一个场景，设定可以后续逐步展开',
      default: '建议先从场景入手',
    },
  },
  P002: {
    name: '对话很自然',
    description: {
      L1: '个别角色的语气还可以更鲜明',
      L2: '但角色之间的谈话还需要更多个性',
      default: '试着让每个角色说话的方式不一样',
    },
  },
  P003: {
    name: '情绪描写很真实',
    description: {
      L1: '部分场景可以用动作代替直接描述',
      L2: '有些情绪可以直接用行为展现',
      default: '试试用行动来表达感受',
    },
  },
  P004: {
    name: '故事信息量丰富',
    description: {
      L1: '开头可以再放慢一点节奏',
      L2: '开场信息稍多，可以让角色带出设定',
      default: '试着把设定融入情节',
    },
  },
  P005: {
    name: '人物形象鲜明',
    description: {
      L1: '可以再丰富一下角色的背景',
      L2: '角色动机还需要更多展现',
      default: '让角色的行为更有说服力',
    },
  },
  P006: {
    name: '故事很完整',
    description: {
      default: '注意不要遗漏故事中的重要信息',
    },
  },
  P007: {
    name: '情节丰富',
    description: {
      L1: '有些支线可以适当精简',
      L2: '支线情节有点多，建议聚焦主线',
      default: '试着围绕主线展开',
    },
  },
  P009: {
    name: '角色很有潜力',
    description: {
      L1: '可以再多展现角色的内心',
      L2: '角色的动机还不太清晰',
      L3: '角色的核心动机需要明确',
      default: '让读者理解角色为什么这么做',
    },
  },
  P010: {
    name: '想象力丰富',
    description: {
      L1: '可以注意场景之间的过渡',
      L2: '转折需要更自然的铺垫',
      default: '让变化更符合逻辑',
    },
  },
};
```

### 3.3 严重度颜色映射（仅用颜色）

```
L1 → 绿色（好转/轻微）
L2 → 橙色（中等/关注）
L3 → 红色（严重/需处理）
```

## 四、涉及文件

| 文件 | 改动类型 |
|------|---------|
| `src/shared/diagnosis-translations.ts` | **新建** — 翻译映射表 |
| `src/renderer/components/panels/RightPanel.tsx` | 改造 `diagnoses` 渲染使用翻译函数 |
| `src/renderer/shared/types.ts` | 新增 `UserFacingDiagnosis` 接口 |

## 五、DoD

1. 右侧栏诊断不再展示 P001/L2 等内部术语
2. 每个症候有对应的正面表述名称和教练语言描述
3. 严重度用颜色表示，不显示文字
4. TypeScript 编译无错误
5. 至少 3 个测试覆盖翻译函数

## 六、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-05 | 初始设计 |
