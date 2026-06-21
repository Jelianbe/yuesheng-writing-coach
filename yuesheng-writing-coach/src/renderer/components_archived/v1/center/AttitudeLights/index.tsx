/**
 * AttitudeLights — 态度灯组件
 *
 * 三个小圆点表示 AI 态度档位：
 * - doubao(绿) = 温和鼓励
 * - yuesheng(橙) = 专业平衡
 * - sensei(红) = 直接挑战
 *
 * 功能：点击切换态度、锁定/解锁、hover tooltip
 *
 * 用法:
 * ```tsx
 * <AttitudeLights />
 * ```
 */
import { useCallback } from 'react';
import { useUiStore, type AttitudeLevel } from '@/stores/ui.store';
import styles from './index.module.css';

/** 各档位的显示信息 */
const ATTITUDE_CONFIG: Record<AttitudeLevel, {
  label: string;
  desc: string;
  className: string;
}> = {
  doubao: {
    label: '豆包',
    desc: '温和鼓励',
    className: styles.doubao,
  },
  yuesheng: {
    label: '月笙如歌',
    desc: '专业平衡',
    className: styles.yuesheng,
  },
  sensei: {
    label: 'Sensei',
    desc: '直接挑战',
    className: styles.sensei,
  },
};

const LEVELS: AttitudeLevel[] = ['doubao', 'yuesheng', 'sensei'];

/**
 * 单个态度灯
 */
function Light({
  level,
  active,
  locked,
  onSelect,
}: {
  level: AttitudeLevel;
  active: boolean;
  locked: boolean;
  onSelect: (level: AttitudeLevel) => void;
}): JSX.Element {
  const config = ATTITUDE_CONFIG[level];

  const handleClick = useCallback(() => {
    if (!locked) {
      onSelect(level);
    }
  }, [locked, level, onSelect]);

  const classNames = [
    styles.light,
    config.className,
    active ? styles.lightActive : '',
    locked ? styles.lightDisabled : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <button
      className={classNames}
      onClick={handleClick}
      type="button"
      aria-label={`${config.label} - ${config.desc}${active ? '（当前）' : ''}`}
      aria-pressed={active}
      aria-disabled={locked}
      disabled={locked}
    >
      <span className={styles.tooltip} role="tooltip" aria-hidden="true">
        <span className={styles.tooltipLabel}>{config.label}</span>
        <span className={styles.tooltipDesc}>{config.desc}</span>
      </span>
    </button>
  );
}

/**
 * AttitudeLights 态度灯组件
 *
 * 从 useUiStore 读取 attitude 和 attitudeLocked 状态，
 * 点击灯切换态度，锁按钮控制锁定。
 */
export function AttitudeLights(): JSX.Element {
  const attitude = useUiStore((s) => s.attitude);
  const attitudeLocked = useUiStore((s) => s.attitudeLocked);
  const setAttitude = useUiStore((s) => s.setAttitude);
  const toggleAttitudeLock = useUiStore((s) => s.toggleAttitudeLock);

  const lockClass = [
    styles.lockBtn,
    attitudeLocked ? styles.lockBtnLocked : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={styles.wrapper} role="group" aria-label="AI 态度档位选择">
      <div className={styles.lights}>
        {LEVELS.map((level) => (
          <Light
            key={level}
            level={level}
            active={attitude === level}
            locked={attitudeLocked}
            onSelect={setAttitude}
          />
        ))}
      </div>

      <button
        className={lockClass}
        onClick={toggleAttitudeLock}
        type="button"
        aria-label={attitudeLocked ? '解锁态度切换' : '锁定当前态度'}
        aria-pressed={attitudeLocked}
      >
        {attitudeLocked ? '\u{1F512}' : '\u{1F513}'}
      </button>
    </div>
  );
}
