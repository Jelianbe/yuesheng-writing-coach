# T-016 辩驳追踪 + 强度升级设计

> **对应发现**：发现8 — 验证报告未消化  
> **优先级**：P1  
> **工作量**：2天  
> **依赖**：T-015（翻译层）✅ 后做  
> **前端改动**：无（纯后端逻辑）

---

## 一、问题

验证报告明确指出：

1. AI 在用户辩驳时倾向温和引导（A001/A004 兜底）
2. 真实月笙会采用 Sensei 模式直接批判
3. 验证报告要求"辩驳处理多样化"，但代码中没有辩驳检测逻辑

## 二、目标

1. 追踪用户的辩驳行为次数
2. 达到阈值时自动升级态度模式
3. 不同辩驳次数触发不同的教学策略

## 三、设计

### 3.1 辩驳检测

```typescript
interface DisputeRecord {
  count: number;
  lastDisputeAt: number;
  isEscalated: boolean;
}

class DisputeTracker {
  private records = new Map<string, DisputeRecord>(); // key: sessionId

  /** 检查用户消息是否包含辩驳倾向 */
  checkMessage(sessionId: string, message: string): boolean {
    const isDispute = this.detectDispute(message);
    if (!isDispute) return false;

    const record = this.records.get(sessionId) ?? { count: 0, lastDisputeAt: 0, isEscalated: false };
    record.count++;
    record.lastDisputeAt = Date.now();

    if (record.count >= 3) record.isEscalated = true;
    this.records.set(sessionId, record);
    return true;
  }

  /** 获取当前态度档位（基于辩驳次数） */
  getAttitude(sessionId: string): 'doubao' | 'yuesheng' | 'sensei' {
    const record = this.records.get(sessionId);
    if (!record || record.count < 2) return 'doubao';
    if (record.count < 4) return 'yuesheng';
    return 'sensei';
  }

  /** 检测单条消息是否包含辩驳 */
  private detectDispute(message: string): boolean {
    // 关键词匹配
    const patterns = [
      /但你不懂/, /不是这样/, /你没有理解/, /不对/, /你没看懂/,
      /你根本没/, /你想多了/, /你理解错了/, /你错了/, /你不对/,
    ];
    // 反问句式
    const rhetoricalPatterns = [
      /你没看到.+吗/, /我不是说了.+/,
      /你仔细看了吗/, /你到底懂不懂/,
    ];

    return patterns.some(p => p.test(message))
        || rhetoricalPatterns.some(p => p.test(message));
  }

  /** 清理过期记录 */
  clearSession(sessionId: string): void {
    this.records.delete(sessionId);
  }
}
```

### 3.2 升级逻辑

| 辩驳次数 | 态度模式 | 教学语气 | 行为 |
|----------|---------|---------|------|
| 0-1 次 | doubao | encouraging | 正常引导，耐心解释 |
| 2-3 次 | yuesheng | direct | 直接指出问题，减少修饰 |
| 4+ 次 | sensei | challenging | 使用"打醒"式反馈 |

### 3.2.1 自动升级 vs 手动选择优先级（T-017 冲突解决）

> **冲突来源**：T-016 自动升级态度 vs T-017 用户手动选择态度，二者未定义优先级。
> **解决原则**：升级只升不降，用户有最终否决权。

**规则**：

1. **只升不降**：辩驳升级只会向更高档位升级，不会因为辩驳少而降低用户主动选择的档位。如果用户手动选了 sensei，辩驳 0 次不会降回 doubao。
2. **升级有条件触发**：只有当 `升级目标档位 > 用户当前手动选择` 时才触发升级。例：用户选了 doubao，辩驳 2 次可升到 yuesheng；用户已选 yuesheng，辩驳 2 次无变化（因为 yuesheng 就是目标）。
3. **UI 同步**：升级触发后，态度按钮自动切换到升级后的档位，用户可见。
4. **用户否决权**：用户可手动切回低档位。切回后视为"用户明确选择 softer 策略"——本次会话内不再因同一辩驳计数自动升级，除非辩驳计数继续增加达到下一个阈值。例：doubao→yuesheng（自动）→doubao（用户切回）→yuesheng 不再自动触发，但辩驳到 4 次仍可触发 sensei。
5. **反思门控排除**（T-018 交互）：当教学状态机处于 S2_REFLECTION 阶段时，用户的回答不纳入辩驳计数。用户回答反思问题时说"你不对"不算辩驳——他们是在配合反思流程，不是在对抗教练。

**代码修改**：

```typescript
/** 获取有效态度档位（综合考虑辩驳升级 + 用户手动选择） */
getEffectiveAttitude(
  sessionId: string,
  userSelectedAttitude: 'doubao' | 'yuesheng' | 'sensei',
  isReflectionPhase: boolean,  // T-018: 反思阶段不升级
): 'doubao' | 'yuesheng' | 'sensei' {
  // 反思阶段不升级
  if (isReflectionPhase) return userSelectedAttitude;

  const record = this.records.get(sessionId);
  if (!record) return userSelectedAttitude;

  // 计算辩驳升级目标
  const escalationTarget: AttitudeLevel =
    record.count < 2 ? 'doubao' :
    record.count < 4 ? 'yuesheng' : 'sensei';

  // 只升不降：升级目标 > 用户选择时才升级
  const levelOrder = { doubao: 0, yuesheng: 1, sensei: 2 };
  if (levelOrder[escalationTarget] > levelOrder[userSelectedAttitude]) {
    // 检查用户是否已否决过此升级
    if (this.isUpgradeVetoed(sessionId, escalationTarget)) {
      return userSelectedAttitude;
    }
    return escalationTarget;
  }

  return userSelectedAttitude;
}
```

### 3.3 集成到 chat.handler.ts

```typescript
// 在 processMessage 流程中
const disputeTracker = new DisputeTracker();

async function processMessage(sessionId: string, message: string) {
  // 1. 检测辩驳
  disputeTracker.checkMessage(sessionId, message);
  
  // 2. 获取当前态度
  const attitude = disputeTracker.getAttitude(sessionId);
  
  // 3. 根据态度设置语气修饰
  const toneModifier = loadToneModifier(attitude);
  
  // 4. 继续正常流程
  await callDiagnosisAgent(sessionId, message);
  const response = await generateResponse(sessionId, toneModifier);
  sendResponse(response);
}
```

### 3.4 动作选择影响

辩驳次数也会影响动作选择：

```
0 次辩驳：正常教学动作
1-2 次：增加"直接解释原因"作为备选
3+ 次：使用"对比展示"动作，提供多组例子让用户自己判断
```

## 四、涉及文件

| 文件 | 改动类型 |
|------|---------|
| `src/main/services/dispute-tracker.service.ts` | **新建** |
| `src/main/ipc/chat.handler.ts` | 集成辩驳检测逻辑 |
| `resources/config/tone-modifiers.json` | 添加 sensei 档位（可选） |
| `src/main/index.ts` | 注册 DisputeTracker（可选） |

## 五、DoD

1. DisputeTracker 正确检测辩驳消息（正则匹配 + 反问句式）
2. 辩驳 2 次自动升级到 yuesheng，4 次升级到 sensei
3. 升级后语气和动作选择相应变化
4. TypeScript 编译无错误
5. 至少 5 个测试覆盖不同辩驳次数的升级逻辑

## 六、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-05 | 初始设计 |
