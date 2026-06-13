/**
 * 学生模型领域入口
 *
 * 对外接口：IStudentDomain — 供 ChatOrchestrator 等外部模块使用
 * 内部实现：StudentModelService, AbilityProfileService, GrowthTrendService
 */

export interface IStudentDomain {
  toPromptText(): string;
}

export { StudentModelService } from './student-model-service';
export { AbilityProfileService } from './ability-profile.service';
export { GrowthTrendService } from './growth-trend.service';
export { ProfileDataAggregator } from './profile-data-aggregator';
