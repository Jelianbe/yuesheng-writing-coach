import React from 'react';
import {
  Check,
  Clock,
  AlertCircle,
  ChevronRight,
  Target,
  BookOpen,
} from 'lucide-react';
import { Badge } from '../common/Badge';
import type {
  TeachingState,
  ActiveProblem,
} from '../../shared/types';
import { PhaseNameMap, SubphaseNameMap, ActionNameMap } from '../../shared/display-names';

export interface TeachingProgressProps {
  teachingState: TeachingState | null;
  className?: string;
  /** 紧凑模式（用于 Sidebar） */
  compact?: boolean;
}

const ALL_SUBPHASES = Object.keys(SubphaseNameMap);

const ProblemStatusMap: Record<ActiveProblem['status'], { label: string; variant: 'danger' | 'warning' | 'success' }> = {
  active: { label: '活跃', variant: 'danger' },
  improving: { label: '改善中', variant: 'warning' },
  resolved: { label: '已解决', variant: 'success' },
};

const ProgressStep: React.FC<{
  label: string;
  isCompleted: boolean;
  isCurrent: boolean;
}> = ({ label, isCompleted, isCurrent }) => (
  <div className="flex items-center gap-2.5 py-1.5">
    <div
      className={`w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 transition-colors duration-fast ${
        isCompleted
          ? 'bg-info text-text-inverse'
          : isCurrent
          ? 'bg-accent-primary text-text-inverse'
          : 'bg-surface-secondary border border-border'
      }`}
    >
      {isCompleted ? (
        <Check className="w-3 h-3" />
      ) : isCurrent ? (
        <Clock className="w-3 h-3" />
      ) : (
        <div className="w-2 h-2 rounded-full bg-text-tertiary" />
      )}
    </div>
    <span
      className={`text-sm ${
        isCompleted
          ? 'text-text-secondary'
          : isCurrent
          ? 'text-text-primary font-medium'
          : 'text-text-tertiary'
      }`}
    >
      {label}
    </span>
  </div>
);

/** 根据当前阶段获取子阶段列表 */
function getSubphasesForPhase(phase: string): string[] {
  switch (phase) {
    case 'P1_WORLD':
      return ['S1_NATURAL_LAW', 'S1_PROTAGONIST', 'S1_SOCIAL_STRUCT', 'S1_FIRST_SCENE', 'S1_DAILY_DETAIL'];
    case 'P2_PRACTICE_LOOP':
      return ['S2_IDENTIFY', 'S2_TEACHING', 'S2_ASSIGN_TASK', 'S2_REVIEW_TASK'];
    case 'P4_REVIEW':
      return ['S4_SUMMARY'];
    default:
      return [];
  }
}

export const TeachingProgress: React.FC<TeachingProgressProps> = ({
  teachingState,
  className = '',
  compact = false,
}) => {
  if (!teachingState) {
    return (
      <div className={`p-6 text-center ${className}`}>
        <div className="w-12 h-12 rounded-full bg-surface-secondary flex items-center justify-center mx-auto mb-3">
          <BookOpen className="w-6 h-6 text-text-tertiary" strokeWidth={1.5} />
        </div>
        <p className="text-sm text-text-secondary">暂无教学进度</p>
        <p className="text-xs text-text-tertiary mt-1">
          开始对话后将自动跟踪教学进度
        </p>
      </div>
    );
  }

  if (compact) {
    return (
      <div className={className}>
        {/* Compact: show only phase and active problem count */}
        <div className="px-4 py-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Badge variant="accent">
                {PhaseNameMap[teachingState.currentPhase] || teachingState.currentPhase}
              </Badge>
              {teachingState.activeProblems.length > 0 && (
                <span className="text-xs text-text-tertiary">
                  {teachingState.activeProblems.length} 个活跃问题
                </span>
              )}
            </div>
            <div className="h-1.5 flex-1 mx-3 bg-surface-secondary rounded-full overflow-hidden">
              <div
                className="h-full bg-accent-primary rounded-full transition-all duration-slide"
                style={{
                  width: `${Math.min(
                    (ALL_SUBPHASES.indexOf(teachingState.currentSubphase) + 1) /
                      ALL_SUBPHASES.length *
                      100,
                    100
                  )}%`,
                }}
              />
            </div>
          </div>
        </div>
      </div>
    );
  }

  const currentPhaseSubphases = getSubphasesForPhase(teachingState.currentPhase);

  return (
    <div className={className}>
      {/* Phase Header */}
      <div className="px-4 py-3 border-b border-border bg-surface-secondary/50">
        <h3 className="text-base font-medium text-text-primary">教学进度</h3>
        <div className="flex items-center gap-2 mt-2">
          <Badge variant="accent">
            {PhaseNameMap[teachingState.currentPhase] || teachingState.currentPhase}
          </Badge>
          {teachingState.currentSubphase && (
            <>
              <ChevronRight className="w-3 h-3 text-text-tertiary" />
              <span className="text-xs text-text-secondary">
                {SubphaseNameMap[teachingState.currentSubphase] || teachingState.currentSubphase}
              </span>
            </>
          )}
        </div>
      </div>

      <div className="overflow-y-auto flex-1">
        {/* Progress steps */}
        <div className="p-4 border-b border-border">
          <p className="text-xs font-medium text-text-secondary mb-2">当前阶段</p>
          <div className="space-y-0.5">
            {currentPhaseSubphases.length > 0 ? (
              currentPhaseSubphases.map((subphase) => {
                const isCompleted =
                  ALL_SUBPHASES.indexOf(subphase) <
                  ALL_SUBPHASES.indexOf(teachingState.currentSubphase);
                const isCurrent = subphase === teachingState.currentSubphase;
                return (
                  <ProgressStep
                    key={subphase}
                    label={SubphaseNameMap[subphase] || subphase}
                    isCompleted={isCompleted}
                    isCurrent={isCurrent}
                  />
                );
              })
            ) : (
              <p className="text-sm text-text-tertiary">进行中...</p>
            )}
          </div>
        </div>

        {/* Active problems */}
        {teachingState.activeProblems.length > 0 && (
          <div className="p-4 border-b border-border">
            <p className="text-xs font-medium text-text-secondary mb-2 flex items-center gap-1.5">
              <AlertCircle className="w-3.5 h-3.5" />
              活跃问题 ({teachingState.activeProblems.length})
            </p>
            <div className="space-y-2">
              {teachingState.activeProblems.map((problem) => {
                const statusInfo = ProblemStatusMap[problem.status];
                return (
                  <div
                    key={problem.id}
                    className="p-2.5 bg-surface-secondary rounded-[var(--radius-sm)]"
                  >
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-sm font-medium text-text-primary">
                        {problem.name}
                      </span>
                      <Badge variant={statusInfo.variant}>
                        {statusInfo.label}
                      </Badge>
                    </div>
                    {problem.suggestedActions.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-1.5">
                        {problem.suggestedActions.slice(0, 3).map((a) => (
                          <Badge key={a} variant="default">
                            {(ActionNameMap as Record<string, string>)[a]}
                          </Badge>
                        ))}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Next actions */}
        {teachingState.nextSuggestedActions.length > 0 && (
          <div className="p-4">
            <p className="text-xs font-medium text-text-secondary mb-2 flex items-center gap-1.5">
              <Target className="w-3.5 h-3.5" />
              下一步建议
            </p>
            <div className="flex flex-wrap gap-1.5">
              {teachingState.nextSuggestedActions.map((actionId) => (
                <Badge key={actionId} variant="accent">
                  {(ActionNameMap as Record<string, string>)[actionId]}
                </Badge>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
