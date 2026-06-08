/**
 * DisputeTrackerService — 辩驳检测 + 计数 + 自动升级判定
 *
 * 职责：
 *   1. 检测用户消息中的辩驳行为（关键词匹配 + 反问句式）
 *   2. 按会话追踪辩驳次数
 *   3. 达到阈值时自动升级态度模式（doubao → yuesheng → direct）
 *   4. 实现"只升不降"和"用户否决权"规则
 *   5. 支持反思阶段排除（T-018 交互）
 *
 * 设计依据：
 *   - dispute-tracking-escalation_V1.0.md §3.1 辩驳检测
 *   - T-016 任务文档 DoD
 *   - design-philosophy_V1.0.md 第三章「降级规则」（用户有最终否决权）
 *
 * 升级规则：
 *   - 0-1 次辩驳：doubao（温柔模式）
 *   - 2-3 次辩驳：yuesheng（月笙模式）
 *   - 4+ 次辩驳：direct（尖锐模式）
 *
 * 优先级规则（T-016 vs T-017 冲突解决）：
 *   1. 只升不降：升级只向更高档位，不因辩驳减少而降低
 *   2. 用户手动选择 > 自动升级（用户选 direct 时，0 辩驳不降回 doubao）
 *   3. 用户否决：手动切回低档位后，同一阈值不再自动升级，但更高阈值仍可触发
 *   4. 反思阶段排除：S2_REFLECTION 阶段的用户回答不纳入辩驳计数
 */

import { AttitudeLevel } from '../../renderer/shared/types';

// ===== 类型定义 =====

/** 态度等级数值映射（用于比较高低） */
const ATTITUDE_ORDER: Record<AttitudeLevel, number> = {
  doubao: 0,
  yuesheng: 1,
  direct: 2,
};

/** 辩驳升级阈值 */
const ESCALATION_THRESHOLDS = {
  /** 2 次辩驳 → yuesheng */
  yuesheng: 2,
  /** 4 次辩驳 → direct（尖锐模式） */
  direct: 4,
};

/** 所有态度档位（按强度排序） */
const ALL_ATTITUDE_LEVELS: AttitudeLevel[] = ['doubao', 'yuesheng', 'direct'];

/** 会话辩驳记录 */
interface DisputeRecord {
  /** 辩驳次数 */
  count: number;
  /** 最后一次辩驳时间戳 */
  lastDisputeAt: number;
  /** 用户手动否决的升级目标档位（切回低档位时记录） */
  vetoedUpgrades: Set<AttitudeLevel>;
}

// ===== 辩驳检测正则 =====

/** 辩驳关键词模式 */
const DISPUTE_PATTERNS = [
  /但你不懂/,
  /不是这样/,
  /你没有理解/,
  /不对/,
  /你没看懂/,
  /你根本没/,
  /你想多了/,
  /你理解错了/,
  /你错了/,
  /你不对/,
  /根本不是/,
  /完全不对/,
  /你不明白/,
  /你没搞懂/,
  /这不对/,
  /不是的/,
  /不应该/,
  /我不这么认为/,
  /我觉得你理解有误/,
];

/** 反问句式模式（强烈的辩驳信号） */
const RHETORICAL_PATTERNS = [
  /你没看到.+吗/,
  /我不是说了.+/,
  /你仔细看了吗/,
  /你到底懂不懂/,
  /你难道没看到/,
  /我不是已经.+了/,
  /你怎么.+/,
];

// ===== 服务类 =====

export class DisputeTrackerService {
  private records = new Map<string, DisputeRecord>();

  /**
   * 检测并记录用户消息中的辩驳行为
   * @param sessionId 会话 ID
   * @param message 用户消息内容
   * @param isReflectionPhase 是否处于反思阶段（反思阶段不纳入辩驳计数）
   * @returns 是否检测到辩驳
   */
  checkMessage(
    sessionId: string,
    message: string,
    isReflectionPhase: boolean = false,
  ): boolean {
    // 反思阶段排除（T-018 交互）
    if (isReflectionPhase) {
      return false;
    }

    const isDispute = this.detectDispute(message);
    if (!isDispute) {
      return false;
    }

    // 更新辩驳记录
    const record = this.records.get(sessionId) ?? this.createRecord();
    record.count++;
    record.lastDisputeAt = Date.now();
    this.records.set(sessionId, record);

    return true;
  }

  /**
   * 获取有效态度档位（综合考虑辩驳升级 + 用户手动选择 + 否决权）
   *
   * 规则（T-016 vs T-017 冲突解决）：
   * 1. 反思阶段不升级
   * 2. 只升不降：升级目标 > 用户选择时才升级
   * 3. 用户否决：已否决的升级目标不再自动触发
   */
  getEffectiveAttitude(
    sessionId: string,
    userSelectedAttitude: AttitudeLevel,
    isReflectionPhase: boolean = false,
  ): AttitudeLevel {
    // 反思阶段不升级
    if (isReflectionPhase) {
      return userSelectedAttitude;
    }

    const record = this.records.get(sessionId);
    if (!record || record.count === 0) {
      return userSelectedAttitude;
    }

    // 计算辩驳升级目标
    const escalationTarget = this.calculateEscalationTarget(record.count);

    // 只升不降：升级目标 > 用户选择时才升级
    if (ATTITUDE_ORDER[escalationTarget] <= ATTITUDE_ORDER[userSelectedAttitude]) {
      return userSelectedAttitude;
    }

    // 检查用户是否已否决此升级
    if (record.vetoedUpgrades.has(escalationTarget)) {
      return userSelectedAttitude;
    }

    return escalationTarget;
  }

  /**
   * 用户手动切换态度档位时的处理
   *
   * 如果用户切回比当前辩驳升级目标更低的档位，视为"否决"该升级。
   * 记录被否决的档位，后续不再因同一辩驳计数自动升级到此档位，
   * 但更高阈值仍可触发。
   */
  onUserAttitudeChange(
    sessionId: string,
    userSelectedAttitude: AttitudeLevel,
  ): void {
    const record = this.records.get(sessionId);
    if (!record) {
      return;
    }

    // 计算当前辩驳计数对应的升级目标
    const escalationTarget = this.calculateEscalationTarget(record.count);

    // 如果用户切回比升级目标更低的档位，记录否决
    if (ATTITUDE_ORDER[userSelectedAttitude] < ATTITUDE_ORDER[escalationTarget]) {
      // 否决从 userSelectedAttitude+1 到 escalationTarget 之间的所有档位
      for (const level of ALL_ATTITUDE_LEVELS) {
        if (
          ATTITUDE_ORDER[level] > ATTITUDE_ORDER[userSelectedAttitude] &&
          ATTITUDE_ORDER[level] <= ATTITUDE_ORDER[escalationTarget]
        ) {
          record.vetoedUpgrades.add(level);
        }
      }
    }
  }

  /**
   * 获取当前会话的辩驳次数
   */
  getDisputeCount(sessionId: string): number {
    return this.records.get(sessionId)?.count ?? 0;
  }

  /**
   * 清理会话记录（会话结束或新建时调用）
   */
  clearSession(sessionId: string): void {
    this.records.delete(sessionId);
  }

  /**
   * 重置服务（测试用）
   */
  reset(): void {
    this.records.clear();
  }

  // ===== 私有方法 =====

  /** 检测单条消息是否包含辩驳 */
  private detectDispute(message: string): boolean {
    // 关键词匹配
    const hasDisputeKeyword = DISPUTE_PATTERNS.some((p) => p.test(message));

    // 反问句式
    const hasRhetorical = RHETORICAL_PATTERNS.some((p) => p.test(message));

    return hasDisputeKeyword || hasRhetorical;
  }

  /** 根据辩驳次数计算升级目标档位 */
  private calculateEscalationTarget(count: number): AttitudeLevel {
    if (count >= ESCALATION_THRESHOLDS.direct) {
      return 'direct';
    }
    if (count >= ESCALATION_THRESHOLDS.yuesheng) {
      return 'yuesheng';
    }
    return 'doubao';
  }

  /** 创建新的辩驳记录 */
  private createRecord(): DisputeRecord {
    return {
      count: 0,
      lastDisputeAt: 0,
      vetoedUpgrades: new Set<AttitudeLevel>(),
    };
  }
}
