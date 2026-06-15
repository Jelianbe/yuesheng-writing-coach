import { create } from 'zustand';

/**
 * F-04: 分级提示点数管理
 * 初始 3 点，L1 消耗 1 点，L2 消耗 2 点，L3 消耗 3 点
 */

export type HintLevel = 'L1' | 'L2' | 'L3';

export const HINT_COSTS: Record<HintLevel, number> = {
  L1: 1,
  L2: 2,
  L3: 3,
};

export const INITIAL_HINT_POINTS = 3;

interface HintState {
  points: number;
  unlockedLevels: Set<HintLevel>;
  
  // Actions
  resetPoints: () => void;
  unlockLevel: (level: HintLevel) => boolean;
  canUnlock: (level: HintLevel) => boolean;
  getUnlockedHints: () => HintLevel[];
}

export const useHintStore = create<HintState>((set, get) => ({
  points: INITIAL_HINT_POINTS,
  unlockedLevels: new Set<HintLevel>(),

  resetPoints: () => {
    set({ points: INITIAL_HINT_POINTS, unlockedLevels: new Set<HintLevel>() });
  },

  canUnlock: (level: HintLevel) => {
    const { points, unlockedLevels } = get();
    const cost = HINT_COSTS[level];
    return points >= cost && !unlockedLevels.has(level);
  },

  unlockLevel: (level: HintLevel) => {
    const { points, unlockedLevels, canUnlock } = get();
    
    if (!canUnlock(level)) {
      return false;
    }

    const cost = HINT_COSTS[level];
    const newUnlocked = new Set(unlockedLevels);
    newUnlocked.add(level);

    set({
      points: points - cost,
      unlockedLevels: newUnlocked,
    });

    return true;
  },

  getUnlockedHints: () => {
    const { unlockedLevels } = get();
    return Array.from(unlockedLevels);
  },
}));
