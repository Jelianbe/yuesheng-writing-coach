/**
 * 复盘总结服务（Retro Service）
 *
 * 负责：根据训练历史生成结构化复盘总结
 * - 计算改善趋势（各症候的进步幅度）
 * - 总结已掌握技法
 * - 提炼持续改进方向
 */

import type { TrainingRecordService } from '../04-validation/training/training-record.service';
import { SYNDROME_NAMES } from '../../../shared/mappings';
import type { SyndromeId } from '../../../shared/constants';

// ─── 类型定义 ───

export interface RetroSummary {
  /** 总训练次数 */
  totalTrainingCount: number;
  /** 参与的症候数量 */
  syndromeCount: number;
  /** 各症候训练记录摘要 */
  syndromeSummaries: SyndromeRetroSummary[];
  /** 总体改善幅度（0-100%） */
  overallImprovement: number;
  /** 已掌握技法列表 */
  masteredTechniques: string[];
  /** 建议继续关注的症候 */
  recommendedFocus: string[];
  /** 总结评语 */
  summary: string;
}

export interface SyndromeRetroSummary {
  syndromeId: string;
  syndromeName: string;
  /** 训练次数 */
  trainingCount: number;
  /** 初始评分（最早一次） */
  initialScore: number | null;
  /** 当前评分（最近一次） */
  currentScore: number | null;
  /** 改善幅度（0-100%） */
  improvement: number | null;
  /** 是否已掌握 */
  mastered: boolean;
}

export interface RetroInput {
  sessionId: string;
}

// ─── 服务 ───

export class RetroService {
  constructor(
    private readonly trainingRecordService: TrainingRecordService,
  ) {}

  /**
   * 生成复盘总结
   */
  async generateRetroSummary(input: RetroInput): Promise<RetroSummary> {
    const records = this.trainingRecordService.getBySession(input.sessionId);

    if (records.length === 0) {
      return {
        totalTrainingCount: 0,
        syndromeCount: 0,
        syndromeSummaries: [],
        overallImprovement: 0,
        masteredTechniques: [],
        recommendedFocus: [],
        summary: '暂无训练记录。开始你的第一次训练吧！',
      };
    }

    // 按症候分组
    const bySyndrome = new Map<string, typeof records>();
    for (const r of records) {
      if (r.syndromeId) {
        const group = bySyndrome.get(r.syndromeId) ?? [];
        group.push(r);
        bySyndrome.set(r.syndromeId, group);
      }
    }

    const syndromeSummaries: SyndromeRetroSummary[] = [];
    let totalImprovement = 0;
    let improvementCount = 0;
    const masteredTechniques: string[] = [];
    const recommendedFocus: string[] = [];

    for (const [syndromeId, syndromeRecords] of bySyndrome) {
      const sorted = syndromeRecords.sort(
        (a, b) => new Date(a.assignedAt).getTime() - new Date(b.assignedAt).getTime(),
      );
      const scores = sorted
        .map(r => r.score)
        .filter((s): s is number => s != null);
      const initialScore = scores.length > 0 ? scores[0] : null;
      const currentScore = scores.length > 0 ? scores[scores.length - 1] : null;
      const improvement = initialScore != null && currentScore != null && initialScore > 0
        ? Math.round(((currentScore - initialScore) / initialScore) * 100)
        : null;

      // 平均分 >= 7 视为已掌握
      const avgScore = scores.length > 0
        ? scores.reduce((a, b) => a + b, 0) / scores.length
        : 0;
      const mastered = avgScore >= 7;

      const syndromeName = SYNDROME_NAMES[syndromeId as SyndromeId] ?? syndromeId;

      syndromeSummaries.push({
        syndromeId,
        syndromeName,
        trainingCount: syndromeRecords.length,
        initialScore,
        currentScore,
        improvement,
        mastered,
      });

      if (improvement != null) {
        totalImprovement += improvement;
        improvementCount++;
      }

      if (mastered) {
        masteredTechniques.push(syndromeName);
      } else {
        recommendedFocus.push(syndromeName);
      }
    }

    const overallImprovement = improvementCount > 0
      ? Math.round(totalImprovement / improvementCount)
      : 0;

    // 生成评语
    const summary = this.generateSummaryText(
      records.length,
      bySyndrome.size,
      overallImprovement,
      masteredTechniques.length,
    );

    return {
      totalTrainingCount: records.length,
      syndromeCount: bySyndrome.size,
      syndromeSummaries,
      overallImprovement,
      masteredTechniques,
      recommendedFocus,
      summary,
    };
  }

  private generateSummaryText(
    totalCount: number,
    syndromeCount: number,
    improvement: number,
    masteredCount: number,
  ): string {
    if (totalCount === 0) return '暂无训练记录。';

    const lines: string[] = [];
    lines.push(`共完成 ${totalCount} 次训练，涉及 ${syndromeCount} 个症候方向。`);

    if (improvement > 0) {
      lines.push(`总体改善幅度约 ${improvement}%，说明你在持续进步！`);
    } else if (improvement < 0) {
      lines.push('近期评分数值略有波动，这是学习中的正常现象，坚持练习会看到改善。');
    } else {
      lines.push('继续坚持训练，改善会在积累中显现。');
    }

    if (masteredCount > 0) {
      lines.push(`已掌握 ${masteredCount} 个技法方向，继续保持！`);
    } else {
      lines.push('暂时还没有达到掌握的技法，别灰心，每一次训练都在积累经验。');
    }

    return lines.join(' ');
  }
}
