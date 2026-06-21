/**
 * ProfileWorkspace — 个人资料工作区
 *
 * 使用 useStudentContextStore 显示学生画像信息：
 * 用户类型、信心水平、思维风格。
 *
 * 用法:
 * ```tsx
 * <ProfileWorkspace />
 * ```
 */
import { useStudentContextStore } from '@/stores/student-context.store';
import styles from './index.module.css';

/** 用户类型中文映射 */
const USER_TYPE_LABEL: Record<string, string> = {
  beginner: '新手',
  intermediate: '进阶',
  advanced: '熟练',
};

/** 信心水平中文映射 */
const CONFIDENCE_LABEL: Record<string, string> = {
  low: '偏低',
  medium: '适中',
  high: '充足',
};

/** 思维风格中文映射 */
const THINKING_STYLE_LABEL: Record<string, string> = {
  analytical: '理性分析型',
  emotional: '感性体验型',
  mixed: '混合型',
};

export function ProfileWorkspace(): JSX.Element {
  const userType = useStudentContextStore((s) => s.userType);
  const confidenceLevel = useStudentContextStore((s) => s.confidenceLevel);
  const thinkingStyle = useStudentContextStore((s) => s.thinkingStyle);
  const frustrationCount = useStudentContextStore((s) => s.frustrationCount);

  return (
    <div className={styles.container}>
      {/* 标题区 */}
      <div className={styles.header}>
        <h3 className={styles.title}>个人资料</h3>
      </div>

      <div className={styles.content}>
        <div className={styles.avatarSection}>
          <div className={styles.avatar} aria-hidden="true">
            {'\uD83D\uDC64'}
          </div>
        </div>

        <div className={styles.infoCard}>
          <span className={styles.infoLabel}>用户类型</span>
          <span className={styles.infoValue}>
            {USER_TYPE_LABEL[userType] ?? userType}
          </span>
        </div>

        <div className={styles.infoCard}>
          <span className={styles.infoLabel}>信心水平</span>
          <span className={styles.infoValue}>
            {CONFIDENCE_LABEL[confidenceLevel] ?? confidenceLevel}
          </span>
        </div>

        <div className={styles.infoCard}>
          <span className={styles.infoLabel}>思维风格</span>
          <span className={styles.infoValue}>
            {THINKING_STYLE_LABEL[thinkingStyle] ?? thinkingStyle}
          </span>
        </div>

        <div className={styles.infoCard}>
          <span className={styles.infoLabel}>挫折计数</span>
          <span className={styles.infoValue}>{frustrationCount}</span>
        </div>
      </div>
    </div>
  );
}
