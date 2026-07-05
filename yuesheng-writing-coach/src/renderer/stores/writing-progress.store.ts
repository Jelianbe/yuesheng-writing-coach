/**
 * writing-progress.store.ts — 写作进度追踪（Sprint 40）
 *
 * 封装 progress:overview IPC 调用，提供写作量、训练频率、活跃度等统计。
 */
import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';

interface DailyWordCount {
  date: string;
  count: number;
}

interface DailyTrainingCount {
  date: string;
  total: number;
  completed: number;
}

interface ProgressOverview {
  todayWordCount: number;
  weeklyWordCount: number;
  monthlyWordCount: number;
  totalWordCount: number;
  writingStreak: number;

  totalTraining: number;
  completedTraining: number;
  averageScore: number | null;

  totalSessions: number;
  weeklySessions: number;

  dailyWordCounts: DailyWordCount[];
  dailyTrainingCounts: DailyTrainingCount[];
}

interface WritingProgressStoreState {
  overview: ProgressOverview | null;
  loading: boolean;
  error: string | null;
  fetchOverview: () => Promise<void>;
}

export const useWritingProgressStore = create<WritingProgressStoreState>((set) => ({
  overview: null,
  loading: false,
  error: null,

  fetchOverview: async () => {
    set({ loading: true, error: null });
    try {
      const data = await serviceBridge.invoke<void, ProgressOverview>('progress:overview', undefined);
      set({ overview: data, loading: false });
    } catch (e) {
      set({ error: String(e), loading: false });
    }
  },
}));
