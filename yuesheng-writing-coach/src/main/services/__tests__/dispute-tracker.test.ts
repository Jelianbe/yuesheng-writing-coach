/**
 * DisputeTrackerService 单元测试
 *
 * 测试覆盖：
 *   - 基础辩驳检测（关键词 + 反问句式）
 *   - 辩驳计数
 *   - 态度升级（2次→yuesheng，4次→direct）
 *   - 只升不降规则
 *   - 用户否决权
 *   - 反思阶段排除
 *   - 会话清理
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { DisputeTrackerService } from '../dispute-tracker.service';

describe('DisputeTrackerService', () => {
  let tracker: DisputeTrackerService;
  const SESSION_ID = 'test-session';

  beforeEach(() => {
    tracker = new DisputeTrackerService();
    tracker.reset();
  });

  // ===== 基础辩驳检测 =====

  describe('detectDispute', () => {
    it('检测到辩驳关键词时返回 true', () => {
      expect(tracker.checkMessage(SESSION_ID, '但你不懂我的意思')).toBe(true);
    });

    it('检测到"不是这样"时返回 true', () => {
      expect(tracker.checkMessage(SESSION_ID, '不是这样的，我写的是另一个意思')).toBe(true);
    });

    it('检测到反问句式时返回 true', () => {
      expect(tracker.checkMessage(SESSION_ID, '你没看到第二段吗？')).toBe(true);
    });

    it('检测到"你理解错了"时返回 true', () => {
      expect(tracker.checkMessage(SESSION_ID, '你理解错了，我的角色是这样的')).toBe(true);
    });

    it('普通消息返回 false', () => {
      expect(tracker.checkMessage(SESSION_ID, '好的，我明白了')).toBe(false);
    });

    it('正常提问返回 false', () => {
      expect(tracker.checkMessage(SESSION_ID, '你觉得这段世界观描写怎么样？')).toBe(false);
    });
  });

  // ===== 辩驳计数 =====

  describe('dispute count', () => {
    it('初始计数为 0', () => {
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(0);
    });

    it('每次检测到辩驳时计数 +1', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(1);

      tracker.checkMessage(SESSION_ID, '不是这样');
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(2);

      tracker.checkMessage(SESSION_ID, '你理解错了');
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(3);
    });

    it('非辩驳消息不增加计数', () => {
      tracker.checkMessage(SESSION_ID, '好的谢谢');
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(0);

      tracker.checkMessage(SESSION_ID, '但你不对');
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(1);
    });
  });

  // ===== 态度升级 =====

  describe('attitude escalation', () => {
    it('0 次辩驳时返回用户选择的态度', () => {
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('doubao');
    });

    it('1 次辩驳时不升级（阈值 2）', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('doubao');
    });

    it('2 次辩驳时自动升级到 yuesheng', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('yuesheng');
    });

    it('3 次辩驳时保持 yuesheng', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');
      tracker.checkMessage(SESSION_ID, '你理解错了');
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('yuesheng');
    });

    it('4 次辩驳时自动升级到 direct', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');
      tracker.checkMessage(SESSION_ID, '你理解错了');
      tracker.checkMessage(SESSION_ID, '完全不对');
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('direct');
    });
  });

  // ===== 只升不降规则 =====

  describe('escalation only upward (只升不降)', () => {
    it('用户手动选择 yuesheng 时，0 辩驳不降回 doubao', () => {
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'yuesheng');
      expect(result).toBe('yuesheng');
    });

    it('用户手动选择 direct 时，0 辩驳不降级', () => {
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'direct');
      expect(result).toBe('direct');
    });

    it('用户选择 doubao，辩驳 2 次升到 yuesheng', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('yuesheng');
    });

    it('用户已选 yuesheng，辩驳 2 次无变化', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'yuesheng');
      expect(result).toBe('yuesheng'); // 不会降到 doubao
    });
  });

  // ===== 用户否决权 =====

  describe('user veto power', () => {
    it('用户切回低档位后，同一阈值不再自动升级', () => {
      // 辩驳 2 次
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');

      // 自动升级到 yuesheng
      expect(tracker.getEffectiveAttitude(SESSION_ID, 'doubao')).toBe('yuesheng');

      // 用户手动切回 doubao（否决升级）
      tracker.onUserAttitudeChange(SESSION_ID, 'doubao');

      // 同一辩驳计数（2次），不再自动升级
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('doubao');
    });

    it('用户否决后，更高阈值仍可触发', () => {
      // 辩驳 2 次 → 自动升级 yuesheng → 用户否决
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');
      tracker.getEffectiveAttitude(SESSION_ID, 'doubao'); // 触发 yuesheng
      tracker.onUserAttitudeChange(SESSION_ID, 'doubao'); // 否决

      // 同一阈值不再触发
      expect(tracker.getEffectiveAttitude(SESSION_ID, 'doubao')).toBe('doubao');

      // 继续辩驳到 4 次 → 触发 direct
      tracker.checkMessage(SESSION_ID, '你理解错了');
      tracker.checkMessage(SESSION_ID, '完全不对');
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('direct'); // direct > yuesheng（被否决的），仍触发
    });

    it('用户否决 yuesheng 后，切到 yuesheng 再切回 doubao，yuesheng 仍被否决', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');

      // 用户选择 yuesheng（不触发自动升级，因为用户主动选了）
      tracker.onUserAttitudeChange(SESSION_ID, 'yuesheng');

      // 用户再切回 doubao
      tracker.onUserAttitudeChange(SESSION_ID, 'doubao');

      // 同一阈值不应再触发
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('doubao');
    });
  });

  // ===== 反思阶段排除 =====

  describe('reflection phase exclusion', () => {
    it('反思阶段的辩驳消息不纳入计数', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂', true); // isReflectionPhase = true
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(0);
    });

    it('反思阶段不升级态度', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂', true);
      tracker.checkMessage(SESSION_ID, '不是这样', true);
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao', true);
      expect(result).toBe('doubao'); // 即使有辩驳（实际没记录），也不升级
    });

    it('反思阶段返回用户选择的态度', () => {
      // 先正常辩驳 4 次
      tracker.checkMessage(SESSION_ID, '但你不懂');
      tracker.checkMessage(SESSION_ID, '不是这样');
      tracker.checkMessage(SESSION_ID, '你理解错了');
      tracker.checkMessage(SESSION_ID, '完全不对');

      // 非反思阶段会升级到 direct
      expect(tracker.getEffectiveAttitude(SESSION_ID, 'doubao')).toBe('direct');

      // 反思阶段返回用户选择
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'yuesheng', true);
      expect(result).toBe('yuesheng');
    });
  });

  // ===== 会话清理 =====

  describe('session management', () => {
    it('clearSession 清理指定会话的记录', () => {
      tracker.checkMessage(SESSION_ID, '但你不懂');
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(1);

      tracker.clearSession(SESSION_ID);
      expect(tracker.getDisputeCount(SESSION_ID)).toBe(0);
    });

    it('不同会话的辩驳计数独立', () => {
      tracker.checkMessage('session-1', '但你不懂');
      tracker.checkMessage('session-1', '不是这样');

      expect(tracker.getDisputeCount('session-1')).toBe(2);
      expect(tracker.getDisputeCount('session-2')).toBe(0);
    });

    it('reset 清理所有会话记录', () => {
      tracker.checkMessage('session-1', '但你不懂');
      tracker.checkMessage('session-2', '不是这样');

      tracker.reset();

      expect(tracker.getDisputeCount('session-1')).toBe(0);
      expect(tracker.getDisputeCount('session-2')).toBe(0);
    });
  });

  // ===== 边界情况 =====

  describe('edge cases', () => {
    it('空消息不抛出异常', () => {
      expect(() => tracker.checkMessage(SESSION_ID, '')).not.toThrow();
    });

    it('不存在会话时返回默认态度', () => {
      const result = tracker.getEffectiveAttitude('non-existent', 'doubao');
      expect(result).toBe('doubao');
    });

    it('大量辩驳消息后态度保持 direct', () => {
      for (let i = 0; i < 20; i++) {
        tracker.checkMessage(SESSION_ID, '但你不懂');
      }
      const result = tracker.getEffectiveAttitude(SESSION_ID, 'doubao');
      expect(result).toBe('direct');
    });
  });
});
