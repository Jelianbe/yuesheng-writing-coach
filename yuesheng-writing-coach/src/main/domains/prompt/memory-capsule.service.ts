/**
 * MemoryCapsuleService — PE-009 记忆胶囊机制
 *
 * 将最近诊断摘要 + 教学进度封装为结构化记忆胶囊，
 * 替代纯诊断历史。确保 AI 理解完整的教学上下文。
 *
 * 设计来源：pro-writing-tools-report_V1.0.md → PE-009
 * 参考实现：Claude Projects "记忆胶囊机制"
 *   - 每 3-5 次交互后封装当前状态 + 进度 + 聚焦问题
 *   - 标准化格式注入对话上下文
 */

import { severityToNumber } from '../../../shared/severity-utils';
import type { DiagnosisEntry, SeverityLevel, TeachingProgressDisplay } from '../../../shared/types/index';

// ===== 接口定义 =====

export interface CapsuleOptions {
  /** 诊断历史列表（按时间正序，最新的在最后） */
  diagnoses: DiagnosisEntry[];
  /** 教学进度显示（可选） */
  progress?: TeachingProgressDisplay | null;
  /** 胶囊标题（默认 "教学生态（记忆胶囊）"） */
  title?: string;
  /** 最近诊断取多少条（默认 3） */
  recentCount?: number;
}

// ===== 服务类 =====

export class MemoryCapsuleService {
  /**
   * 构建记忆胶囊文本
   * 格式：诊断摘要 + 频率统计 + 当前聚焦 + 教学进度
   */
  buildCapsule(options: CapsuleOptions): string {
    const { diagnoses, progress, title = '教学生态（记忆胶囊）', recentCount = 3 } = options;

    if (diagnoses.length === 0) {
      return `## ${title}\n\n本会话尚无历史诊断记录。`;
    }

    const parts: string[] = [];
    parts.push(`## ${title}\n`);

    // 1. 最近诊断摘要
    const recent = diagnoses.slice(-recentCount);
    const recentLines = recent.map(d => {
      const date = new Date(d.timestamp).toLocaleDateString('zh-CN');
      const syndromesText = d.syndromes
        .slice(0, 3)
        .map(s => `${s.name}（${s.severity}）`)
        .join('、');
      return `- ${date}：${syndromesText}`;
    });

    parts.push('### 最近诊断\n');
    parts.push(recentLines.join('\n'));

    // 2. 当前聚焦（最高严重度 + 高频率症候）
    const focusText = this.buildFocusSection(diagnoses);
    if (focusText) {
      parts.push(`\n${focusText}`);
    }

    // 3. 教学进度
    if (progress) {
      parts.push(`\n### 教学进度\n`);
      parts.push(`- 当前阶段：${progress.phaseName}`);
      parts.push(`- 当前步骤：${progress.subphaseName}`);
      parts.push(`- 阶段进度：${Math.round(progress.phaseProgress * 100)}%`);
      if (progress.completedActions.length > 0) {
        const actions = progress.completedActions.map(a => a.name).join('、');
        parts.push(`- 已完成：${actions}`);
      }
    }

    // 4. 教学建议
    parts.push('\n### 教学建议');
    parts.push('- 关注用户是否反复出现相同问题');
    if (progress) {
      parts.push('- 根据当前教学阶段调整指导密度');
    }
    parts.push('- 一次只聚焦一个问题');

    return parts.join('\n');
  }

  /**
   * 构建聚焦信息：统计症候频率，找出最需关注的问题
   */
  private buildFocusSection(diagnoses: DiagnosisEntry[]): string | null {
    const syndromeStats = new Map<string, { name: string; severity: string; count: number }>();

    for (const d of diagnoses) {
      for (const s of d.syndromes) {
        const existing = syndromeStats.get(s.id);
        const sevNum = severityToNumber(s.severity as SeverityLevel);
        if (!existing || sevNum > severityToNumber(existing.severity as SeverityLevel)) {
          syndromeStats.set(s.id, {
            name: s.name,
            severity: s.severity,
            count: (existing?.count ?? 0) + 1,
          });
        } else {
          existing!.count++;
        }
      }
    }

    const sorted = Array.from(syndromeStats.values())
      .sort((a, b) => severityToNumber(b.severity as SeverityLevel) - severityToNumber(a.severity as SeverityLevel));

    const top = sorted[0];
    if (!top || severityToNumber(top.severity as SeverityLevel) < severityToNumber('L2')) {
      return null;
    }

    const recurrenceNote = top.count > 1 ? `（已出现 ${top.count} 次）` : '';
    return `### 当前聚焦\n\n**${top.name}**（${top.severity}）${recurrenceNote} — 请优先处理此项。`;
  }
}

// ===== 便捷函数（无 DI 场景使用） =====

let defaultService: MemoryCapsuleService | null = null;

export function getMemoryCapsuleService(): MemoryCapsuleService {
  if (!defaultService) {
    defaultService = new MemoryCapsuleService();
  }
  return defaultService;
}

/** 便捷调用：直接传入参数构建胶囊文本 */
export function buildMemoryCapsule(options: CapsuleOptions): string {
  return getMemoryCapsuleService().buildCapsule(options);
}
