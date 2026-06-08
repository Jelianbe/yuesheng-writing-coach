import React from 'react';
import {
  Dumbbell,
  CheckCircle,
  Clock,
  Target,
  TrendingUp,
  AlertTriangle,
} from 'lucide-react';
import { Card } from '../common/Card';
import { Badge } from '../common/Badge';
import { EmptyState } from '../common/EmptyState';
import { ActiveProblem, ActionId } from '../../shared/types';

interface TasksPageProps {
  activeProblems: ActiveProblem[];
  completedTasks: string[];
  currentTaskId: string | null;
  className?: string;
}

interface MockTask {
  id: string;
  name: string;
  description: string;
  actionId: ActionId;
  relatedSyndrome: string;
  difficulty: 'easy' | 'medium' | 'hard';
  estimatedTime: string;
}

const actionNameMap: Record<ActionId, string> = {
  A001: '缩小范围',
  A002: '回归主角',
  A003: '落地现实',
  A004: '从核心构建',
  A005: '展示而非告知',
  A006: '对话练习',
  A007: '翻转视角',
  A008: '阅读作业',
  A009: '信心确认',
  A010: '边界校准',
  A011: '跨场景迁移',
  A012: '意图校准',
};

const difficultyConfig = {
  easy: { label: '入门', variant: 'success' as const },
  medium: { label: '进阶', variant: 'warning' as const },
  hard: { label: '挑战', variant: 'danger' as const },
};

// Mock task data based on active problems
const generateTasksFromProblems = (
  problems: ActiveProblem[]
): MockTask[] => {
  if (problems.length === 0) {
    return [];
  }

  const tasks: MockTask[] = [];
  for (const problem of problems) {
    for (const actionId of problem.suggestedActions) {
      tasks.push({
        id: `${problem.id}-${actionId}`,
        name: `${actionNameMap[actionId]}训练`,
        description: `针对「${problem.name}」问题的专项训练，通过${actionNameMap[actionId]}的方式改善写作表现。`,
        actionId,
        relatedSyndrome: problem.name,
        difficulty:
          problem.severity === 'L3'
            ? 'hard'
            : problem.severity === 'L2'
            ? 'medium'
            : 'easy',
        estimatedTime: problem.severity === 'L3' ? '30分钟' : '15分钟',
      });
    }
  }

  return tasks;
};

const TaskCard: React.FC<{
  task: MockTask;
  isCompleted: boolean;
  isCurrent: boolean;
}> = ({ task, isCompleted, isCurrent }) => {
  const difficulty = difficultyConfig[task.difficulty];

  return (
    <Card
      hover={!isCompleted}
      className={`p-4 transition-all duration-fast ${
        isCurrent ? 'ring-2 ring-accent-primary ring-offset-2' : ''
      } ${isCompleted ? 'opacity-60' : ''}`}
    >
      <div className="flex items-start gap-3">
        <div
          className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 ${
            isCompleted
              ? 'bg-accent-secondary/10'
              : isCurrent
              ? 'bg-accent-primary/10'
              : 'bg-bg-tertiary'
          }`}
        >
          {isCompleted ? (
            <CheckCircle className="w-5 h-5 text-accent-secondary" />
          ) : (
            <Dumbbell className="w-5 h-5 text-text-secondary" />
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <h4 className="text-small font-medium text-text-primary">
              {task.name}
            </h4>
            <Badge variant={difficulty.variant}>{difficulty.label}</Badge>
            {isCurrent && (
              <Badge variant="accent">进行中</Badge>
            )}
          </div>
          <p className="text-tiny text-text-secondary mb-2">
            {task.description}
          </p>
          <div className="flex items-center gap-3">
            <span className="text-tiny text-text-muted flex items-center gap-1">
              <Target className="w-3 h-3" />
              {task.relatedSyndrome}
            </span>
            <span className="text-tiny text-text-muted flex items-center gap-1">
              <Clock className="w-3 h-3" />
              {task.estimatedTime}
            </span>
          </div>
        </div>
      </div>
    </Card>
  );
};

export const TasksPage: React.FC<TasksPageProps> = ({
  activeProblems,
  completedTasks,
  currentTaskId,
  className = '',
}) => {
  const tasks = generateTasksFromProblems(activeProblems);

  // Compute stats
  const totalTasks = tasks.length;
  const completedCount = completedTasks.length;
  const inProgressCount = currentTaskId ? 1 : 0;

  if (tasks.length === 0 && activeProblems.length === 0) {
    return (
      <div className={`flex-1 bg-bg-primary overflow-y-auto ${className}`}>
        <EmptyState
          icon={Dumbbell}
          title="暂无训练任务"
          description="完成对话后，系统会根据诊断结果自动生成训练任务"
        />
      </div>
    );
  }

  return (
    <div className={`flex-1 bg-bg-primary overflow-y-auto ${className}`}>
      <div className="max-w-4xl mx-auto p-6">
        {/* Header */}
        <div className="mb-6">
          <h2 className="text-h2 font-semibold text-text-primary mb-2">
            训练任务
          </h2>
          <p className="text-body text-text-secondary">
            根据诊断结果为你生成的写作训练任务，完成任务提升写作能力
          </p>
        </div>

        {/* Stats cards */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-accent-primary-light flex items-center justify-center">
                <Target className="w-5 h-5 text-accent-primary" />
              </div>
              <div>
                <p className="text-tiny text-text-muted">总任务</p>
                <p className="text-h3 font-semibold text-text-primary">
                  {totalTasks}
                </p>
              </div>
            </div>
          </Card>
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-emerald-50 flex items-center justify-center">
                <CheckCircle className="w-5 h-5 text-accent-secondary" />
              </div>
              <div>
                <p className="text-tiny text-text-muted">已完成</p>
                <p className="text-h3 font-semibold text-text-primary">
                  {completedCount}
                </p>
              </div>
            </div>
          </Card>
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center">
                <Clock className="w-5 h-5 text-accent-info" />
              </div>
              <div>
                <p className="text-tiny text-text-muted">进行中</p>
                <p className="text-h3 font-semibold text-text-primary">
                  {inProgressCount}
                </p>
              </div>
            </div>
          </Card>
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-amber-50 flex items-center justify-center">
                <TrendingUp className="w-5 h-5 text-accent-warning" />
              </div>
              <div>
                <p className="text-tiny text-text-muted">完成率</p>
                <p className="text-h3 font-semibold text-text-primary">
                  {totalTasks > 0
                    ? Math.round((completedCount / totalTasks) * 100)
                    : 0}
                  %
                </p>
              </div>
            </div>
          </Card>
        </div>

        {/* Active problems summary */}
        {activeProblems.length > 0 && (
          <div className="mb-6">
            <h3 className="text-h3 font-medium text-text-primary mb-3 flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-accent-warning" />
              待改善问题
            </h3>
            <div className="flex flex-wrap gap-2">
              {activeProblems.map((problem) => (
                <Badge
                  key={problem.id}
                  variant={
                    problem.severity === 'L3'
                      ? 'danger'
                      : problem.severity === 'L2'
                      ? 'warning'
                      : 'info'
                  }
                >
                  {problem.name} ({problem.status === 'active' ? '活跃' : problem.status === 'improving' ? '改善中' : '已解决'})
                </Badge>
              ))}
            </div>
          </div>
        )}

        {/* Task list */}
        <div>
          <h3 className="text-h3 font-medium text-text-primary mb-3">
            任务列表
          </h3>
          <div className="space-y-3">
            {tasks.map((task) => (
              <TaskCard
                key={task.id}
                task={task}
                isCompleted={completedTasks.includes(task.id)}
                isCurrent={task.id === currentTaskId}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

// Usage example:
// <TasksPage
//   activeProblems={activeProblems}
//   completedTasks={completedTasks}
//   currentTaskId={currentTaskId}
// />
