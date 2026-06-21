/**
 * 教学笔记服务 — 内存存储
 *
 * 职责：管理教学笔记树状结构，支持创建/读取/删除/更新节点
 * 设计：当前为进程级内存存储，数据随应用重启重置。
 *       后续需要持久化时可迁移到 SQLite + Knex migration。
 */

import { randomUUID } from 'node:crypto';

export interface TeachingNoteNodeData {
  id: string;
  parentId: string | null;
  sessionId: string;
  label: string;
  content: string;
  createdAt: number;
}

export class TeachingNoteService {
  /** 内存存储：所有节点平铺存储 */
  private nodes = new Map<string, TeachingNoteNodeData>();

  /**
   * 记录一条教学笔记
   */
  record(sessionId: string, label: string, content: string, parentId?: string): TeachingNoteNodeData {
    const node: TeachingNoteNodeData = {
      id: randomUUID(),
      parentId: parentId ?? null,
      sessionId,
      label,
      content,
      createdAt: Date.now(),
    };
    this.nodes.set(node.id, node);
    return node;
  }

  /**
   * 获取教学笔记树（按会话筛选）
   */
  getTree(sessionId?: string): TeachingNoteNodeData[] {
    const entries = Array.from(this.nodes.values());
    if (sessionId) {
      return entries.filter(n => n.sessionId === sessionId);
    }
    return entries;
  }

  /**
   * 删除节点及其所有子节点
   */
  deleteNode(id: string): boolean {
    if (!this.nodes.has(id)) return false;
    // 查找并删除所有子节点
    const childrenIds = Array.from(this.nodes.values())
      .filter(n => n.parentId === id)
      .map(n => n.id);
    for (const childId of childrenIds) {
      this.deleteNode(childId);
    }
    return this.nodes.delete(id);
  }

  /**
   * 更新节点
   */
  updateNode(id: string, updates: { label?: string; content?: string }): boolean {
    const node = this.nodes.get(id);
    if (!node) return false;
    if (updates.label !== undefined) node.label = updates.label;
    if (updates.content !== undefined) node.content = updates.content;
    return true;
  }
}
