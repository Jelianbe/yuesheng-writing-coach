/**
 * App.tsx 辅助函数
 *
 * 纯函数集合，不含 React hook 或 store 依赖。
 */

import type { AttitudeLevel, TeachingState, DiagnosisEntry } from '../shared/types';
import type { RightPanelProps } from '../components/panels/RightPanel';

// ===== 右侧面板辅助 =====

export function getPanelSubphasesForPhase(phase: string): string[] {
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

export function buildRightPanelSteps(
  teachingState: TeachingState | null,
  subphaseNameMap: Record<string, string>,
): RightPanelProps['steps'] {
  if (!teachingState) return [];
  const subphases = getPanelSubphasesForPhase(teachingState.currentPhase);
  const currentIdx = subphases.indexOf(teachingState.currentSubphase);

  return subphases.map((sp, idx) => {
    const isCompleted = idx < currentIdx;
    const isActive = idx === currentIdx;
    return {
      id: sp,
      title: subphaseNameMap[sp] || sp,
      desc: isActive ? '进行中' : isCompleted ? '已完成' : '待进行',
      status: isCompleted ? 'completed' : isActive ? 'active' : 'pending',
    };
  });
}

export function buildRightPanelNextStep(
  teachingState: TeachingState | null,
  actionNameMap: Record<string, string>,
): string {
  if (!teachingState?.nextSuggestedActions?.length) return '';
  return teachingState.nextSuggestedActions
    .map((a) => actionNameMap[a] || a)
    .join(' → ');
}

export function buildRightPanelDiagnoses(
  currentDiagnosis: DiagnosisEntry | null,
): RightPanelProps['diagnoses'] {
  if (!currentDiagnosis?.syndromes?.length) return [];
  return currentDiagnosis.syndromes.map((s) => ({
    id: s.id,
    name: s.name,
    severity: s.severity === 'L3' ? 'high' : s.severity === 'L2' ? 'mid' : 'low',
    status: `信号分 ${(s.score ?? 0).toFixed(1)}`,
  }));
}

// ===== 成长趋势辅助 =====

function severityPercent(sev: string | null): number {
  if (!sev) return 50;
  switch (sev) {
    case 'L1': return 25;
    case 'L2': return 50;
    case 'L3': return 85;
    default: return 50;
  }
}

function statusValue(status: string): 'improving' | 'stable' {
  if (status === 'improving' || status === 'mastered') return 'improving';
  return 'stable';
}

function statusLabel(status: string): string {
  switch (status) {
    case 'mastered': return '已掌握';
    case 'improving': return '进步中';
    case 'needsAttention': return '需关注';
    default: return '稳定';
  }
}

export interface GrowthTrendItem {
  id: string;
  name: string;
  status: string;
  latestSeverity: string | null;
  occurrenceCount: number;
  description: string;
}

export function buildGrowthItems(
  trends: GrowthTrendItem[],
  maxDisplay: number,
): RightPanelProps['growthItems'] {
  if (!trends || trends.length === 0) return [];
  return trends.slice(0, maxDisplay).map((t) => ({
    name: t.name,
    value: statusLabel(t.status),
    trend: statusValue(t.status),
    percent: severityPercent(t.latestSeverity),
    desc: t.description,
  }));
}

// ===== 时间辅助 =====

export function getTimeAgo(dateStr: string): string {
  const now = Date.now();
  const date = new Date(dateStr).getTime();
  const diff = now - date;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return '刚刚';
  if (mins < 60) return `${mins}分钟前`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}小时前`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}天前`;
  return `${Math.floor(days / 7)}周前`;
}

// ===== 态度映射 =====

export function mapHeaderAttitude(attitudeLevel: string): 'gentle' | 'direct' | 'sharp' {
  const map: Record<string, 'gentle' | 'direct' | 'sharp'> = {
    doubao: 'gentle',
    direct: 'direct',
    yuesheng: 'sharp',
  };
  return map[attitudeLevel] ?? 'sharp';
}

export function getAttitudeMap(): Record<string, AttitudeLevel> {
  return {
    gentle: 'doubao',
    direct: 'direct',
    sharp: 'yuesheng',
  };
}
