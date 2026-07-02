import React, { useState } from 'react';
import { CheckSquare } from 'lucide-react';
import styles from './SelfCheckList.module.css';

interface SelfCheckListProps {
  questions: string[];
}

/**
 * SelfCheckList — 自检清单子组件
 *
 * 引导用户自我发现问题的检查清单。
 * 替代"治疗模式"，不替用户判断。
 */
export const SelfCheckList: React.FC<SelfCheckListProps> = ({ questions }) => {
  const [checkedItems, setCheckedItems] = useState<Set<number>>(new Set());

  const allChecked = questions.length > 0 && questions.every((_, i) => checkedItems.has(i));

  const handleToggleCheck = (index: number) => {
    setCheckedItems(prev => {
      const next = new Set(prev);
      if (next.has(index)) next.delete(index);
      else next.add(index);
      return next;
    });
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <CheckSquare className={styles.icon} />
        <span className={styles.headerText}>自检清单</span>
        {allChecked && (
          <span className={styles.allCheckedText}>已自查 ✓</span>
        )}
      </div>
      <div className={styles.body}>
        {questions.map((q, i) => (
          <label
            key={i}
            className={styles.label}
          >
            <input
              type="checkbox"
              checked={checkedItems.has(i)}
              onChange={() => handleToggleCheck(i)}
              className={styles.checkbox}
            />
            <span className={checkedItems.has(i) ? styles.checkedText : styles.uncheckedText}>
              {q}
            </span>
          </label>
        ))}
      </div>
    </div>
  );
};
