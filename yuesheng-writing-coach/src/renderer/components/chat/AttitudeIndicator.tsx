/**
 * AttitudeIndicator — 态度档位三灯 (RWR-P1-3)
 *
 * 规格 DoD:
 * - 🟢🟡🔴 三灯互斥(温柔/月笙/尖锐)
 * - 🔒 锁图标(实心/空心)
 * - 锁定: 实心 + var(--color-attitude-{level})
 * - 未锁定: 空心 + 浅色
 * - 无 toast / 弹窗
 *
 * 设计:
 * - 三灯同行(横排)
 * - 锁在右侧(独立按钮)
 * - 点击切换锁定状态,锁定后点击单灯切换 attitudeLevel
 */

import React, { useState, useCallback } from 'react';
import { Lock, Unlock } from 'lucide-react';
import { useConfigStore } from '../../stores/config.store';
import type { AttitudeLevel } from '../../../shared/types/types-config';
import styles from '../../styles/AttitudeIndicator.module.css';

/** 档位 → CSS 变量后缀 */
const LEVEL_TO_VAR: Record<AttitudeLevel, string> = {
  doubao: 'doubao',
  yuesheng: 'yuesheng',
  direct: 'direct',
};

/** 档位顺序(从左到右) */
const LEVELS: ReadonlyArray<AttitudeLevel> = ['doubao', 'yuesheng', 'direct'];

export const AttitudeIndicator: React.FC = () => {
  const attitudeLevel = useConfigStore((s) => s.attitudeLevel);
  const setAttitudeLevel = useConfigStore((s) => s.setAttitudeLevel);
  const [locked, setLocked] = useState(false);

  /** 点击单灯: 仅在锁定时切换(未锁定时由其他 UI 操作) */
  const handleLevelClick = useCallback(
    (level: AttitudeLevel) => {
      if (!locked) return;
      void setAttitudeLevel(level);
    },
    [locked, setAttitudeLevel]
  );

  /** 切换锁定 */
  const toggleLock = useCallback(() => {
    setLocked((prev) => !prev);
  }, []);

  return (
    <div
      className={styles.indicator}
      role="group"
      aria-label="态度档位"
    >
      {/* 三灯 */}
      <div
        className={styles.lights}
        role={locked ? 'radiogroup' : 'group'}
        aria-label={locked ? '态度档位(已锁定)' : '态度档位(未锁定)'}
      >
        {LEVELS.map((level) => {
          const isActive = attitudeLevel === level;
          const colorVar = `var(--color-attitude-${LEVEL_TO_VAR[level]})`;
          return (
            <button
              key={level}
              type="button"
              role={locked ? 'radio' : undefined}
              aria-checked={locked ? isActive : undefined}
              aria-label={`态度档位: ${level}`}
              onClick={() => handleLevelClick(level)}
              disabled={!locked}
              className={
                isActive
                  ? `${styles.light} ${styles.lightActive}`
                  : styles.light
              }
              style={
                isActive
                  ? { backgroundColor: colorVar, borderColor: colorVar }
                  : undefined
              }
            />
          );
        })}
      </div>

      {/* 锁图标 */}
      <button
        type="button"
        onClick={toggleLock}
        className={
          locked
            ? `${styles.lockBtn} ${styles.lockBtnLocked}`
            : styles.lockBtn
        }
        aria-label={locked ? '解锁态度档位' : '锁定态度档位'}
        aria-pressed={locked}
        title={locked ? '解锁' : '锁定'}
      >
        {locked ? (
          <Lock size={11} strokeWidth={1.8} />
        ) : (
          <Unlock size={11} strokeWidth={1.8} />
        )}
      </button>
    </div>
  );
};
