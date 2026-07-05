/**
 * progress.handler.ts — 写作进度追踪（Sprint 40）
 *
 * 聚合章节写作量、训练记录、会话频率等数据，返回时间维度的进度总览。
 * 直接使用 db 实例，通过 registerMethod 注册 progress:overview 通道。
 */
import type Database from 'better-sqlite3';
import { registerMethod } from '../core/service-bridge';

export interface DailyWordCount {
  date: string;
  count: number;
}

export interface DailyTrainingCount {
  date: string;
  total: number;
  completed: number;
}

export interface ProgressOverview {
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

/** 从 chapters.updated_at 反推写作连续天数 */
function calcWritingStreak(db: Database.Database): number {
  const rows = db.prepare(
    `SELECT DISTINCT DATE(updated_at, 'unixepoch') AS day
     FROM chapters
     WHERE updated_at IS NOT NULL
     ORDER BY day DESC`
  ).all() as { day: string }[];

  if (rows.length === 0) return 0;

  let streak = 1;
  const today = new Date();

  // 如果最新活动日不是今天也不是昨天，连续天数为 1 或 0
  const firstDate = rows[0].day;
  const diffDays = Math.floor((today.getTime() - new Date(firstDate).getTime()) / 86400000);
  if (diffDays > 1) return 0; // 超过 1 天没有写作

  for (let i = 1; i < rows.length; i++) {
    const prev = new Date(rows[i - 1].day);
    const curr = new Date(rows[i].day);
    const diff = Math.floor((prev.getTime() - curr.getTime()) / 86400000);
    if (diff === 1) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
}

export function initProgressHandlers(d: { db: Database.Database }): void {
  registerMethod('progress:overview', async (): Promise<ProgressOverview> => {
    const db = d.db;

    // 1. 字数统计
    const wordCountToday = db.prepare(
      `SELECT COALESCE(SUM(word_count), 0) AS c FROM chapters
       WHERE DATE(updated_at, 'unixepoch') = DATE('now')`
    ).get() as { c: number };

    const wordCountWeek = db.prepare(
      `SELECT COALESCE(SUM(word_count), 0) AS c FROM chapters
       WHERE updated_at >= unixepoch('now', '-7 days')`
    ).get() as { c: number };

    const wordCountMonth = db.prepare(
      `SELECT COALESCE(SUM(word_count), 0) AS c FROM chapters
       WHERE updated_at >= unixepoch('now', '-30 days')`
    ).get() as { c: number };

    const wordCountTotal = db.prepare(
      `SELECT COALESCE(SUM(word_count), 0) AS c FROM chapters`
    ).get() as { c: number };

    // 2. 写作连续天数
    const writingStreak = calcWritingStreak(db);

    // 3. 训练统计
    const trainingStats = db.prepare(
      `SELECT
         COUNT(*) AS total,
         COALESCE(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0) AS completed,
         AVG(CASE WHEN score IS NOT NULL THEN score ELSE NULL END) AS avgScore
       FROM user_training_records`
    ).get() as { total: number; completed: number; avgScore: number | null };

    // 4. 会话统计
    const sessionStats = db.prepare(
      `SELECT
         COUNT(*) AS total,
         SUM(CASE WHEN created_at >= unixepoch('now', '-7 days') THEN 1 ELSE 0 END) AS weekly
       FROM sessions`
    ).get() as { total: number; weekly: number };

    // 5. 每日字数（近 30 天）
    const dailyWordCounts = db.prepare(
      `SELECT DATE(updated_at, 'unixepoch') AS date, SUM(word_count) AS count
       FROM chapters
       WHERE updated_at >= unixepoch('now', '-30 days')
       GROUP BY DATE(updated_at, 'unixepoch')
       ORDER BY date`
    ).all() as DailyWordCount[];

    // 6. 每日训练数（近 30 天）
    const dailyTrainingCounts = db.prepare(
      `SELECT DATE(assigned_at, 'unixepoch') AS date,
         COUNT(*) AS total,
         SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed
       FROM user_training_records
       WHERE assigned_at >= unixepoch('now', '-30 days')
       GROUP BY DATE(assigned_at, 'unixepoch')
       ORDER BY date`
    ).all() as DailyTrainingCount[];

    return {
      todayWordCount: wordCountToday.c,
      weeklyWordCount: wordCountWeek.c,
      monthlyWordCount: wordCountMonth.c,
      totalWordCount: wordCountTotal.c,
      writingStreak,
      totalTraining: trainingStats.total,
      completedTraining: trainingStats.completed,
      averageScore: trainingStats.avgScore != null ? Math.round(trainingStats.avgScore * 10) / 10 : null,
      totalSessions: sessionStats.total,
      weeklySessions: sessionStats.weekly,
      dailyWordCounts,
      dailyTrainingCounts,
    };
  });
}
