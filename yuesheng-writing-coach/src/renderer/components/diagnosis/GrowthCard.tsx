import React from 'react';
import { TrendingUp } from 'lucide-react';

interface GrowthCardProps {
  /** 一句话成长记录 */
  summary: string;
  /** 是否有历史记录 */
  hasHistory: boolean;
  /** 加载状态 */
  isLoading?: boolean;
}

/**
 * GrowthCard — 一句话成长记录（M-4）
 *
 * 出现在诊断/评估后，作为聊天的自然收尾。
 * 通过 IPC `diagnosis:getComparison` 获取对比数据。
 */
export const GrowthCard: React.FC<GrowthCardProps> = ({
  summary,
  hasHistory,
  isLoading = false,
}) => {
  if (isLoading) {
    return (
      <div className="border border-border rounded-[var(--radius-md)] bg-surface shadow-sm px-4 py-3 animate-fade-in">
        <div className="flex items-center gap-2">
          <div className="w-4 h-4 rounded-full bg-surface-secondary animate-pulse-custom" />
          <div className="h-4 bg-surface-secondary rounded-[var(--radius-sm)] flex-1 animate-pulse-custom" />
        </div>
      </div>
    );
  }

  return (
    <div className="border border-border rounded-[var(--radius-md)] bg-surface shadow-sm animate-slide-up">
      <div className="flex items-start gap-3 px-4 py-3">
        <div className="w-8 h-8 rounded-full bg-accent-primary-light flex items-center justify-center flex-shrink-0">
          <TrendingUp className="w-4 h-4 text-accent-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-xs text-accent-primary font-medium mb-1">
            成长记录
          </p>
          <p className="text-sm text-text-primary leading-relaxed">
            {hasHistory ? summary : '这是你的第一次诊断，还没有对比数据。'}
          </p>
        </div>
      </div>
    </div>
  );
};
