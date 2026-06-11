/**
 * 训练 Store 选择器
 *
 * 从 TrainingState 中提取指定切片，供组件通过 zustand store 使用。
 */

import type { TrainingState } from './training.types';

export const selectCenterMode = (state: TrainingState) => state.centerMode;
export const selectActiveTraining = (state: TrainingState) => state.activeTraining;
export const selectErrorCards = (state: TrainingState) => state.errorCards;
export const selectRecommendations = (state: TrainingState) => state.recommendations;
export const selectTrainingHistory = (state: TrainingState) => state.history;
export const selectIsLoading = (state: TrainingState) => state.isLoading;
