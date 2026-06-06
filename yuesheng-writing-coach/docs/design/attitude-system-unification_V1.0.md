# T-017 态度系统统一设计

> **对应发现**：发现7 — 态度系统混乱  
> **优先级**：P1  
> **工作量**：1天  
> **依赖**：T-016（辩驳追踪）✅ 后做  
> **前端改动**：态度按钮映射调整

---

## 一、问题

当前存在两套独立的态度/语气系统：

**系统A — 态度档位**（`types.ts`）：
```
AttitudeLevel = 'doubao' | 'yuesheng' | 'direct'
```

**系统B — 教学语气**（`teaching-strategy.service.ts`）：
```
ToneType = 'encouraging' | 'direct' | 'logical' | 'resonant'
```

两套系统互不映射。默认 `yuesheng` 档位在 `tone-modifiers.json` 中无任何修饰内容（prompt-loader 注释明确写明："yuesheng 或其他档位无修饰词"）。

## 二、目标

1. 统一为三态：`doubao` / `yuesheng` / `sensei`
2. 每档都有明确的语气修饰和教学行为
3. 与 `teaching-strategy.service.ts` 的教学语气联动

## 三、设计

### 3.1 统一态度映射

```typescript
interface AttitudeConfig {
  /** 对应教学语气 */
  tone: ToneType;
  /** Prompt 语气修饰词 */
  toneModifier: string;
  /** 前端显示名称 */
  label: string;
  /** 描述 */
  description: string;
}

const ATTITUDE_SYSTEM: Record<string, AttitudeConfig> = {
  doubao: {
    tone: 'encouraging',
    toneModifier: '用温柔鼓励的语气，多肯定用户做得好的地方',
    label: '豆包模式',
    description: '鼓励为主，适合新手和信心不足时',
  },
  yuesheng: {
    tone: 'direct',
    toneModifier: '用直接直击的语气，少修饰，点出核心问题',
    label: '月笙模式',
    description: '直击问题，适合有一定基础的用户',
  },
  sensei: {
    tone: 'challenging',
    toneModifier: '用犀利甚至略带讽刺的语气，目的是打醒用户',
    label: '导师模式',
    description: '犀利反馈，适合屡教不改时使用',
  },
};
```

### 3.2 与教学策略的联动

```typescript
// teaching-strategy.service.ts 中的 decideTone 方法改造
decideTone(
  userTypeMatrix: UserTypeMatrixConfig,
  input: StrategyInput,
  attitude: 'doubao' | 'yuesheng' | 'sensei',
): ToneType {
  // 态度优先：如果用户已触发辩护升级，覆盖教学策略的语气
  if (attitude === 'sensei') return 'challenging';
  if (attitude === 'yuesheng') return 'direct';
  
  // 正常教学策略决策
  const userTypeConfig = userTypeMatrix.userTypes[input.proficiency];
  return userTypeConfig?.defaultTone ?? 'encouraging';
}
```

> **与 T-016 的联动**：`decideTone()` 接收的 `attitude` 参数是 **T-016 的 `getEffectiveAttitude()` 产出的最终值**，已经综合考虑了辩驳升级 + 用户手动选择 + 否决权。此处不需要再判断态度来源。详见 dispute-tracking-escalation_V1.0.md §3.2.1。

### 3.3 与 DisputeTracker 的集成

当 T-016 的辩驳升级触发时，态度按钮需要同步变化：

```typescript
// 在 Sidebar.tsx 中监听态度变化
useEffect(() => {
  // IPC 监听后端态度升级事件
  ipcRenderer.on('attitude-escalated', (_event, newAttitude: AttitudeLevel) => {
    setAttitude(newAttitude);
  });
}, []);
```

用户手动切换态度时，通知后端记录否决：

```typescript
// 用户主动切换态度 → 通知后端
function handleAttitudeChange(newAttitude: AttitudeLevel) {
  const currentEscalation = escalatedAttitude; // 来自后端的升级档位
  const levelOrder = { doubao: 0, yuesheng: 1, sensei: 2 };

  if (levelOrder[newAttitude] < levelOrder[currentEscalation]) {
    // 用户切回了更低的档位 → 通知后端记录否决
    ipcRenderer.send('attitude-veto', { attitude: currentEscalation });
  }
  setAttitude(newAttitude);
}
```

### 3.3 tone-modifiers.json 改造

```json
{
  "$source": "docs/design/attitude-system-unification_V1.0.md",
  "version": "2.0",
  "doubao": "用温柔鼓励的语气，多肯定用户做得好的地方，用"我们"而不是"你"",
  "yuesheng": "用直接直击的语气，少修饰，点出核心问题，使用"你"直接称呼",
  "sensei": "用犀利甚至略带讽刺的语气，目的是打醒用户，可以使用反问句"
}
```

### 3.4 前端态度按钮

```typescript
// 当前前端映射
const ATTITUDE_OPTIONS = [
  { value: 'doubao', label: '豆包', icon: '🐶' },
  { value: 'yuesheng', label: '月笙', icon: '👤' },
  { value: 'sensei', label: '导师', icon: '👹' },
];
```

## 四、涉及文件

| 文件 | 改动类型 |
|------|---------|
| `src/renderer/shared/types.ts` | 修改 `AttitudeLevel` 定义 |
| `resources/config/tone-modifiers.json` | 添加 sensei 档位 |
| `src/main/services/teaching-strategy.service.ts` | `decideTone()` 接收 attitude 参数 |
| `src/main/services/prompt-loader.ts` | 修复 yuesheng 无语气修饰问题 |
| `src/renderer/components/layout/Sidebar.tsx` | 更新态度按钮映射 |

## 五、DoD

1. 三态 `doubao/yuesheng/sensei` 每档有明确语气修饰
2. `tone-modifiers.json` 三条目完整
3. 教学策略的 `decideTone()` 接收 attitude 参数做联动
4. 默认 `yuesheng` 档位有语气修饰（修复当前 Bug）
5. TypeScript 编译无错误
6. 3 个测试覆盖不同态度的语气输出

## 六、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-05 | 初始设计 |
