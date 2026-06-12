/**
 * StudentContextSection — 学生模型状态配置区块
 */

import React from 'react';
import { Button } from '../common/Button';
import { useStudentContextStore, UserType, ThinkingStyle } from '../../stores/student-context.store';

export const StudentContextSection: React.FC = () => {
  const {
    userType,
    confidenceLevel,
    thinkingStyle,
    frustrationCount,
    setUserType,
    setThinkingStyle,
    reset,
  } = useStudentContextStore();

  const userTypeOptions: Array<{ value: UserType; label: string }> = [
    { value: 'beginner', label: '新手' },
    { value: 'intermediate', label: '进阶' },
    { value: 'advanced', label: '高阶' },
  ];

  const thinkingStyleOptions: Array<{ value: ThinkingStyle; label: string }> = [
    { value: 'analytical', label: '理性分析型' },
    { value: 'emotional', label: '感性体验型' },
    { value: 'mixed', label: '混合型' },
  ];

  return (
    <div className="space-y-4">
      {/* 用户类型 */}
      <div>
        <label className="text-tiny text-text-secondary mb-1.5 block">用户类型</label>
        <div className="flex gap-1.5">
          {userTypeOptions.map((opt) => (
            <button
              key={opt.value}
              type="button"
              onClick={() => setUserType(opt.value)}
              className={[
                'flex-1 py-1.5 px-2 rounded text-tiny font-medium transition-all duration-fast',
                userType === opt.value
                  ? 'bg-accent-primary-light text-accent-primary border border-accent-primary/30'
                  : 'bg-bg-tertiary text-text-muted border border-border hover:bg-bg-hover',
              ].join(' ')}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {/* 思维风格 */}
      <div>
        <label className="text-tiny text-text-secondary mb-1.5 block">思维风格</label>
        <div className="flex gap-1.5">
          {thinkingStyleOptions.map((opt) => (
            <button
              key={opt.value}
              type="button"
              onClick={() => setThinkingStyle(opt.value)}
              className={[
                'flex-1 py-1.5 px-2 rounded text-tiny font-medium transition-all duration-fast',
                thinkingStyle === opt.value
                  ? 'bg-accent-primary-light text-accent-primary border border-accent-primary/30'
                  : 'bg-bg-tertiary text-text-muted border border-border hover:bg-bg-hover',
              ].join(' ')}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {/* 状态概览 */}
      <div className="bg-bg-tertiary rounded-md p-3 text-tiny space-y-1">
        <div className="flex justify-between text-text-muted">
          <span>信心水平</span>
          <span className="text-text-secondary">
            {confidenceLevel === 'low' ? '低' : confidenceLevel === 'medium' ? '中' : '高'}
          </span>
        </div>
        <div className="flex justify-between text-text-muted">
          <span>挫折计数</span>
          <span className={frustrationCount >= 3 ? 'text-accent-danger' : 'text-text-secondary'}>
            {frustrationCount}
          </span>
        </div>
      </div>

      {/* 重置按钮 */}
      <Button variant="ghost" size="sm" onClick={reset} className="text-tiny">
        重置学生模型数据
      </Button>
    </div>
  );
}
