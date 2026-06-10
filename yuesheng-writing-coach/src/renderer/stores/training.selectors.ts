/**
 * 训练 Store 选择器
 */

import type { TrainingState } from './training.types';

export const selectCenterMode = (state: TrainingState) => state.centerMode;
export const selectActiveTraining = (state: TrainingState) => state.activeTraining;
export const selectErrorCards = (state: TrainingState) => state.errorCards;
export const selectRecommendations = (state: TrainingState) => state.recommendations;
export const selectTrainingHistory = (state: TrainingState) => state.history;
export const selectIsLoading = (state: TrainingState) => state.isLoading;
