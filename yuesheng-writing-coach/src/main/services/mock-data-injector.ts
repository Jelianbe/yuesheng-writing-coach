/* eslint-disable no-console */
/**
 * 开发模式模拟数据注入
 * 目的：演示成长趋势功能，在数据库中注入两个对话流的模拟诊断数据
 * 
 * 对话 1（新手）：写作新手，症候严重度持续较高，展示"需关注"状态
 * 对话 2（进步）：同一个用户在多次对话后，症候严重度明显下降，展示"已掌握/进步中"状态
 * 
 * 注意：仅在开发模式下运行（NODE_ENV=development），且仅在数据库为空时注入
 */

import type Database from 'better-sqlite3';

/** 模拟诊断条目 */
interface MockDiagnosis {
  id: string;
  session_id: string;
  message_id: string;
  syndromes: string; // JSON
  suggested_actions: string; // JSON
  confidence: number;
  timestamp: string;
  next_focus: string | null;
}

/** 新手诊断数据：症候严重度高，趋势恶化或稳定 */
const NEWBIE_DIAGNOSES: MockDiagnosis[] = [
  // 第一次诊断：出现多个症候
  {
    id: 'newbie_001',
    session_id: 'mock-newbie-session',
    message_id: 'msg_001',
    syndromes: JSON.stringify([
      { id: 'P001', name: '世界观膨胀', severity: 'L2', score: 5.2, evidence: ['开篇大段设定说明', '直接罗列历史背景'], suggestedActions: ['A001', 'A002'] },
      { id: 'P002', name: '角色工具人化', severity: 'L3', score: 7.8, evidence: ['角色只推动情节不表达内心', '对话缺乏个性'], suggestedActions: ['A004', 'A005'] },
    ]),
    suggested_actions: JSON.stringify(['A001', 'A004']),
    confidence: 0.85,
    timestamp: '2026-06-01T10:00:00.000Z',
    next_focus: 'P002',
  },
  // 第二次诊断：症候依然严重
  {
    id: 'newbie_002',
    session_id: 'mock-newbie-session',
    message_id: 'msg_002',
    syndromes: JSON.stringify([
      { id: 'P001', name: '世界观膨胀', severity: 'L3', score: 8.1, evidence: ['插入大段设定打断叙事节奏'], suggestedActions: ['A001'] },
      { id: 'P002', name: '角色工具人化', severity: 'L3', score: 8.5, evidence: ['主角完全没有内心活动'], suggestedActions: ['A004'] },
    ]),
    suggested_actions: JSON.stringify(['A001', 'A004']),
    confidence: 0.9,
    timestamp: '2026-06-02T14:00:00.000Z',
    next_focus: 'P001',
  },
];

/** 进步用户诊断数据：症候严重度逐步下降 */
const PROGRESS_DIAGNOSES: MockDiagnosis[] = [
  // 第一次对话：初始状态，症候严重
  {
    id: 'progress_001',
    session_id: 'mock-progress-session',
    message_id: 'msg_001',
    syndromes: JSON.stringify([
      { id: 'P001', name: '世界观膨胀', severity: 'L3', score: 7.5, evidence: ['设定说明占据前两章'], suggestedActions: ['A001'] },
      { id: 'P003', name: '时间线混乱', severity: 'L2', score: 5.0, evidence: ['闪回与当前叙事交织不清'], suggestedActions: ['A006'] },
    ]),
    suggested_actions: JSON.stringify(['A001', 'A006']),
    confidence: 0.8,
    timestamp: '2026-06-01T09:00:00.000Z',
    next_focus: 'P001',
  },
  // 第二次对话：有所改善
  {
    id: 'progress_002',
    session_id: 'mock-progress-session',
    message_id: 'msg_002',
    syndromes: JSON.stringify([
      { id: 'P001', name: '世界观膨胀', severity: 'L2', score: 5.0, evidence: ['仍有设定说明但有所减少'], suggestedActions: ['A001'] },
      { id: 'P003', name: '时间线混乱', severity: 'L2', score: 4.5, evidence: ['时间跳跃有标记但仍显突兀'], suggestedActions: ['A006'] },
    ]),
    suggested_actions: JSON.stringify(['A001', 'A006']),
    confidence: 0.85,
    timestamp: '2026-06-02T10:00:00.000Z',
    next_focus: 'P001',
  },
  // 第三次对话：继续改善
  {
    id: 'progress_003',
    session_id: 'mock-progress-session',
    message_id: 'msg_003',
    syndromes: JSON.stringify([
      { id: 'P001', name: '世界观膨胀', severity: 'L2', score: 3.8, evidence: ['大部分设定融入情节'], suggestedActions: ['A001'] },
      { id: 'P003', name: '时间线混乱', severity: 'L1', score: 2.0, evidence: ['偶有时间跳跃但已有铺垫'], suggestedActions: ['A006'] },
    ]),
    suggested_actions: JSON.stringify(['A001']),
    confidence: 0.9,
    timestamp: '2026-06-03T11:00:00.000Z',
    next_focus: 'P003',
  },
  // 第四次对话：基本掌握
  {
    id: 'progress_004',
    session_id: 'mock-progress-session',
    message_id: 'msg_004',
    syndromes: JSON.stringify([
      { id: 'P001', name: '世界观膨胀', severity: 'L1', score: 2.0, evidence: ['设定自然地融入场景'], suggestedActions: ['A002'] },
      { id: 'P003', name: '时间线混乱', severity: 'L1', score: 1.5, evidence: ['时间线清晰，偶尔需要强化'], suggestedActions: ['A006'] },
    ]),
    suggested_actions: JSON.stringify(['A002']),
    confidence: 0.95,
    timestamp: '2026-06-04T14:00:00.000Z',
    next_focus: null,
  },
  // 第五次对话：症候基本消失
  {
    id: 'progress_005',
    session_id: 'mock-progress-session',
    message_id: 'msg_005',
    syndromes: JSON.stringify([
      { id: 'P001', name: '世界观膨胀', severity: 'L1', score: 1.0, evidence: ['几乎没有说明性段落'], suggestedActions: [] },
    ]),
    suggested_actions: JSON.stringify([]),
    confidence: 0.98,
    timestamp: '2026-06-05T16:00:00.000Z',
    next_focus: null,
  },
];

/**
 * 注入模拟数据到数据库
 */
export function injectMockDiagnosisData(db: Database.Database): void {
  // 检查是否已有模拟数据（避免重复注入）
  const existingCount = db.prepare(
    "SELECT COUNT(*) as count FROM diagnosis_results WHERE session_id LIKE 'mock-%'"
  ).get() as { count: number };

  if (existingCount.count > 0) {
    console.log('[MockData] 模拟数据已存在，跳过注入');
    return;
  }

  console.log('[MockData] 开始注入模拟诊断数据...');

  const stmt = db.prepare(`
    INSERT INTO diagnosis_results (id, session_id, message_id, syndromes, suggested_actions, confidence, timestamp, next_focus)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const transaction = db.transaction((diagnoses: MockDiagnosis[]) => {
    for (const d of diagnoses) {
      stmt.run(
        d.id,
        d.session_id,
        d.message_id,
        d.syndromes,
        d.suggested_actions,
        d.confidence,
        d.timestamp,
        d.next_focus,
      );
    }
  });

  // 注入新手数据
  transaction(NEWBIE_DIAGNOSES);
  console.log(`[MockData] 注入新手数据: ${NEWBIE_DIAGNOSES.length} 条诊断记录`);

  // 注入进步用户数据
  transaction(PROGRESS_DIAGNOSES);
  console.log(`[MockData] 注入进步用户数据: ${PROGRESS_DIAGNOSES.length} 条诊断记录`);

  // 验证注入结果
  const totalNewbie = db.prepare(
    "SELECT COUNT(*) as count FROM diagnosis_results WHERE session_id = 'mock-newbie-session'"
  ).get() as { count: number };

  const totalProgress = db.prepare(
    "SELECT COUNT(*) as count FROM diagnosis_results WHERE session_id = 'mock-progress-session'"
  ).get() as { count: number };

  console.log(`[MockData] 注入完成 - 新手: ${totalNewbie.count} 条, 进步: ${totalProgress.count} 条`);
}
