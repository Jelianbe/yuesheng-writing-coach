/**
 * 教学笔记 IPC 处理器
 * 负责：前端教学笔记工具的 CRUD 操作
 * 依赖：TeachingNoteService（内存存储）
 */

import { IPC_CHANNELS } from '../../shared/constants';
import type { TeachingNoteService } from '../domains/03-teaching/teaching-note.service';
import { createHandler } from './utils/create-handler';

export interface TeachingNoteHandlerDeps {
  teachingNoteService: TeachingNoteService;
}

let deps: TeachingNoteHandlerDeps | null = null;

export function initTeachingNoteHandlers(d: TeachingNoteHandlerDeps): void {
  deps = d;
}

/**
 * 注册教学笔记相关的 IPC 处理器
 */
export function registerTeachingNoteHandlers(): void {
  // 记录一条教学笔记
  createHandler(IPC_CHANNELS.TEACHING_NOTE_RECORD, async (
    _event,
    args: { sessionId: string; label: string; content: string; parentId?: string },
  ) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const node = deps.teachingNoteService.record(args.sessionId, args.label, args.content, args.parentId);
    return { id: node.id, createdAt: node.createdAt };
  });

  // 获取教学笔记树
  createHandler(IPC_CHANNELS.TEACHING_NOTE_GET_TREE, async (
    _event,
    args: { sessionId?: string },
  ) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const nodes = deps.teachingNoteService.getTree(args.sessionId);
    // 将平铺数据转为树
    const rootNodes = nodes.filter(n => n.parentId === null);
    const tree = rootNodes.map(n => flatToTree(n, nodes));
    return { nodes: tree };
  });

  // 删除笔记节点（含子节点）
  createHandler(IPC_CHANNELS.TEACHING_NOTE_DELETE, async (_event, args: { id: string }) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const success = deps.teachingNoteService.deleteNode(args.id);
    return { success };
  });

  // 更新笔记节点
  createHandler(IPC_CHANNELS.TEACHING_NOTE_UPDATE, async (
    _event,
    args: { id: string; label?: string; content?: string },
  ) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const success = deps.teachingNoteService.updateNode(args.id, { label: args.label, content: args.content });
    return { success };
  });
}

/** 将平铺节点递归转为树结构 */
function flatToTree(
  node: { id: string; parentId: string | null; label: string; content: string; createdAt: number },
  allNodes: Array<{ id: string; parentId: string | null; label: string; content: string; createdAt: number }>,
): { id: string; parentId: string | null; label: string; content: string; createdAt: number; children: unknown[] } {
  const children = allNodes
    .filter(n => n.parentId === node.id)
    .map(n => flatToTree(n, allNodes));
  return { ...node, children };
}
