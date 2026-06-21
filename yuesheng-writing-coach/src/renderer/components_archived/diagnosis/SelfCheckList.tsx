import React, { useState } from 'react';
import { CheckSquare } from 'lucide-react';

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
    <div className="border border-border rounded-md overflow-hidden">
      <div className="px-3 py-2 bg-bg-tertiary/50 border-b border-border flex items-center gap-2">
        <CheckSquare className="w-3.5 h-3.5 text-accent-primary" />
        <span className="text-xs font-medium text-text-secondary">自检清单</span>
        {allChecked && (
          <span className="text-xs text-accent-success ml-auto">已自查 ✓</span>
        )}
      </div>
      <div className="px-3 py-2 space-y-1.5">
        {questions.map((q, i) => (
          <label
            key={i}
            className="flex items-start gap-2 py-1 cursor-pointer hover:text-text-primary transition-colors"
          >
            <input
              type="checkbox"
              checked={checkedItems.has(i)}
              onChange={() => handleToggleCheck(i)}
              className="mt-0.5 w-3.5 h-3.5 accent-accent-primary"
            />
            <span className={`text-xs ${checkedItems.has(i) ? 'text-text-muted line-through' : 'text-text-secondary'}`}>
              {q}
            </span>
          </label>
        ))}
      </div>
    </div>
  );
};
