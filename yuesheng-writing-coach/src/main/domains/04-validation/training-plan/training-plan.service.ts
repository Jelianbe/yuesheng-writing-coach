/**
 * TrainingPlanService — 自定义训练计划持久化服务
 *
 * Sprint 38: 管理 training_plans 和 training_plan_items 表的 CRUD。
 * 使用 better-sqlite3 直接执行 SQL。
 */
import type Database from 'better-sqlite3';
import { randomUUID } from 'crypto';
import type {
  TrainingPlanDTO,
  TrainingPlanWithItemsDTO,
  TrainingPlanItemDTO,
  AvailableChallengeDTO,
} from '../../../../shared/api-contracts/training-plan.contract';
import challengeTemplates from '../../../../../resources/04-validation/mastery/challenge-templates.json';

export class TrainingPlanService {
  constructor(private db: Database.Database) {}

  // ─── Plan CRUD ───

  create(name: string, description: string = ''): TrainingPlanDTO {
    const id = randomUUID();
    const now = new Date().toISOString();
    this.db.prepare(
      'INSERT INTO training_plans (id, name, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    ).run(id, name, description, now, now);
    return { id, name, description, createdAt: now, updatedAt: now, itemCount: 0, completedCount: 0 };
  }

  list(): TrainingPlanDTO[] {
    return this.db.prepare(`
      SELECT
        p.id, p.name, p.description, p.created_at, p.updated_at,
        COALESCE(i.itemCount, 0) AS itemCount,
        COALESCE(i.completedCount, 0) AS completedCount
      FROM training_plans p
      LEFT JOIN (
        SELECT plan_id,
          COUNT(*) AS itemCount,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completedCount
        FROM training_plan_items
        GROUP BY plan_id
      ) i ON i.plan_id = p.id
      ORDER BY p.updated_at DESC
    `).all().map((row: unknown) => {
      const r = row as Record<string, unknown>;
      return {
        id: r.id as string,
        name: r.name as string,
        description: r.description as string,
        createdAt: r.created_at as string,
        updatedAt: r.updated_at as string,
        itemCount: (r.itemCount ?? 0) as number,
        completedCount: (r.completedCount ?? 0) as number,
      };
    });
  }

  get(planId: string): TrainingPlanWithItemsDTO | null {
    const plan = this.db.prepare('SELECT * FROM training_plans WHERE id = ?').get(planId) as Record<string, unknown> | undefined;
    if (!plan) return null;
    const items = this.db.prepare(
      'SELECT * FROM training_plan_items WHERE plan_id = ? ORDER BY sort_order ASC',
    ).all(planId).map((row: unknown) => this.rowToItemDTO(row as Record<string, unknown>));
    return {
      id: plan.id as string,
      name: plan.name as string,
      description: plan.description as string,
      createdAt: plan.created_at as string,
      updatedAt: plan.updated_at as string,
      itemCount: items.length,
      completedCount: items.filter(i => i.status === 'completed').length,
      items,
    };
  }

  delete(planId: string): void {
    this.db.prepare('DELETE FROM training_plans WHERE id = ?').run(planId);
  }

  // ─── Items ───

  addItem(planId: string, challengeId: string): TrainingPlanItemDTO {
    // 从 challenge-templates 查找挑战信息
    const template = (challengeTemplates as { templates: Array<Record<string, unknown>> }).templates
      .find((t: Record<string, unknown>) => t.id === challengeId);
    if (!template) throw new Error(`Challenge not found: ${challengeId}`);

    const id = randomUUID();
    const now = new Date().toISOString();

    // 获取当前最大 sort_order
    const maxOrder = this.db.prepare(
      'SELECT COALESCE(MAX(sort_order), -1) AS maxOrder FROM training_plan_items WHERE plan_id = ?',
    ).get(planId) as { maxOrder: number };

    this.db.prepare(`
      INSERT INTO training_plan_items (id, plan_id, challenge_id, technique_name, syndrome_id, sort_order, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)
    `).run(id, planId, challengeId, template.syndromeName as string, template.syndromeId as string, maxOrder.maxOrder + 1, now);

    // 更新 plan 的 updated_at
    this.db.prepare('UPDATE training_plans SET updated_at = ? WHERE id = ?').run(now, planId);

    return {
      id, planId, challengeId,
      techniqueName: template.syndromeName as string,
      syndromeId: template.syndromeId as string | null,
      sortOrder: maxOrder.maxOrder + 1,
      status: 'pending', completedAt: null, createdAt: now,
    };
  }

  removeItem(planId: string, itemId: string): void {
    this.db.prepare('DELETE FROM training_plan_items WHERE id = ? AND plan_id = ?').run(itemId, planId);
    this.db.prepare('UPDATE training_plans SET updated_at = ? WHERE id = ?').run(new Date().toISOString(), planId);
  }

  updateItemStatus(itemId: string, status: 'pending' | 'in_progress' | 'completed'): void {
    const now = status === 'completed' ? new Date().toISOString() : null;
    this.db.prepare(
      'UPDATE training_plan_items SET status = ?, completed_at = ? WHERE id = ?',
    ).run(status, now, itemId);
  }

  // ─── Available Challenges ───

  getAvailableChallenges(): AvailableChallengeDTO[] {
    return (challengeTemplates as { templates: Array<Record<string, unknown>> }).templates.map((t: Record<string, unknown>) => ({
      challengeId: t.id as string,
      techniqueName: t.syndromeName as string,
      syndromeId: t.syndromeId as string,
      description: t.challenge as string,
      constraint: t.constraint as string,
    }));
  }

  // ─── Helpers ───

  private rowToItemDTO(row: Record<string, unknown>): TrainingPlanItemDTO {
    return {
      id: row.id as string,
      planId: row.plan_id as string,
      challengeId: row.challenge_id as string,
      techniqueName: row.technique_name as string,
      syndromeId: row.syndrome_id as string | null,
      sortOrder: row.sort_order as number,
      status: row.status as 'pending' | 'in_progress' | 'completed',
      completedAt: row.completed_at as string | null,
      createdAt: row.created_at as string,
    };
  }
}
