/**
 * 训练领域入口
 *
 * 内部实现：TrainingRecordService, TrainingEvaluator, BehaviorDerivation
 * ChatOrchestrator 不直接依赖训练领域
 *
 * S8: 新增 TrainingFlowService（五步通用训练流）
 */

export { TrainingRecordService } from './training-record.service';
export { generateRecommendations, getChallengeTemplate, getAllChallengeTemplates, filterRecommendationsByStage, getAllowedSyndromeIds } from './training-recommendation.service';
export { evaluateTraining } from './training-evaluator.service';
export { deriveBehavior, type DerivationInput } from './behavior-derivation.service';
export { generateTrainingFlow, getSupportedCategories } from './training-flow.service';
