import { BookOpen } from 'lucide-react';
import styles from './ManuscriptPanel.module.css';

/** 无打开章节时的空状态 */
export const EmptyEditorState: React.FC = () => (
  <div className={styles.emptyState}>
    <div className={styles.emptyIconWrap}>
      <BookOpen size={24} strokeWidth={1.4} opacity={0.5} />
    </div>
    <div className={styles.emptyTitle}>
      暂无打开的章节
    </div>
    <div className={styles.emptyHint}>
      在左侧栏点击章节，将在右侧打开编辑器
    </div>
  </div>
);
