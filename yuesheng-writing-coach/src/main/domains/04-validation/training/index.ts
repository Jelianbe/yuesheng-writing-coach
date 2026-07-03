/**
 * 训练领域入口
 *
 * 内部实现：TrainingRecordService, TrainingEvaluator, BehaviorDerivation
 * ChatOrchestrator 不直接依赖训练领域
 *
 * S8: 新增 TrainingFlowService（五步通用训练流）
 * S25 BL-01: 拆分 flow-mapping.loader + technique-library.loader(R-014 零硬编码)
 */

export { TrainingRecordService } from './training-record.service';
export { generateRecommendations, getChallengeTemplate, getAllChallengeTemplates, filterRecommendationsByStage, getAllowedSyndromeIds } from './training-recommendation.service';
export { evaluateTraining } from './training-evaluator.service';
export { deriveBehavior, type DerivationInput } from './behavior-derivation.service';
export { generateTrainingFlow, getSupportedCategories } from './training-flow.service';
export {
  FLOW_CATEGORIES,
  FLOW_TEMPLATES,
  FLOW_CATEGORY_TEMPLATES,
  getFlowCategory,
  getFlowTemplate,
  getCategoryTemplate,
  getMappingVersion,
} from './flow-mapping.loader';
export type {
  FlowCategoryConfig,
  FlowCategoryTemplate,
  FlowTemplate,
  TrainingFlowMapping,
} from './flow-mapping.loader';
export {
  findTechnique,
  getAllTechniques,
  getTechniqueCategories,
} from './technique-library.loader';
export type { TechniqueEntry } from './technique-library.loader';
