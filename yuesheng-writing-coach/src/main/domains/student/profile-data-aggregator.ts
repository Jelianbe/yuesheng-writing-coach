/**
 * 学生领域数据聚合器
 *
 * 职责：集中管理 StudentModelService + AbilityProfileService 对
 *       DiagnosisService 和 TrainingRecordService 的数据访问，
 *       消除两者各自独立查询的重复依赖。
 *
 * 设计依据：domain-consolidation-plan.md §4.2 Phase 3 Step 3.1
 *          消除 StudentModel + AbilityProfile 重复依赖
 */

import type { DiagnosisService } from '../diagnosis/diagnosis.service';
import type { TrainingRecordService } from '../training/training-record.service';
import type { DiagnosisEntry } from '../../../renderer/shared/types';
import type { TrainingRecord } from '../training/training-record.service';

export interface ProfileData {
  diagnoses: DiagnosisEntry[];
  trainings: TrainingRecord[];
}

export class ProfileDataAggregator {
  constructor(
    private diagnosisService: DiagnosisService,
    private trainingService: TrainingRecordService,
  ) {}

  /** 获取单个会话的诊断记录 */
  getDiagnosesBySession(sessionId: string): DiagnosisEntry[] {
    return this.diagnosisService.getBySession(sessionId);
  }

  /** 获取所有诊断记录（跨会话） */
  getAllDiagnoses(): DiagnosisEntry[] {
    return this.diagnosisService.getAll();
  }

  /** 获取单个会话的训练记录 */
  getTrainingsBySession(sessionId: string): TrainingRecord[] {
    return this.trainingService.getBySession(sessionId);
  }

  /** 获取所有训练记录 */
  getAllTrainings(): TrainingRecord[] {
    return this.trainingService.getAll();
  }

  /** 获取单个会话的完整画像数据（诊断 + 训练） */
  getProfileData(sessionId: string): ProfileData {
    return {
      diagnoses: this.getDiagnosesBySession(sessionId),
      trainings: this.getTrainingsBySession(sessionId),
    };
  }
}
