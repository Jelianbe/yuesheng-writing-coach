/**
 * 教学笔记 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('teachingNote:record' | 'teachingNote:getTree' | 'teachingNote:delete' | 'teachingNote:update', ...)`
 *
 * flatToTree 树形转换保留在主进程(无现役 renderer 调用方,但契约稳定)
 */

import { registerMethod } from '../core/service-bridge';
import type { TeachingNoteService } from '../domains/03-teaching/teaching-note.service';

export interface TeachingNoteHandlerDeps {
  teachingNoteService: TeachingNoteService;
}

let deps: TeachingNoteHandlerDeps | null = null;

export function initTeachingNoteHandlers(d: TeachingNoteHandlerDeps): void {
  deps = d;
}

export function registerTeachingNoteHandlers(): void {
  registerMethod('teachingNote:record', async (args) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const { sessionId, label, content, parentId } = args as {
      sessionId: string;
      label: string;
      content: string;
      parentId?: string;
    };
    const node = deps.teachingNoteService.record(sessionId, label, content, parentId);
    return { id: node.id, createdAt: node.createdAt };
  });

  registerMethod('teachingNote:getTree', async (args) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const { sessionId } = args as { sessionId?: string };
    const nodes = deps.teachingNoteService.getTree(sessionId);
    const rootNodes = nodes.filter(n => n.parentId === null);
    const tree = rootNodes.map(n => flatToTree(n, nodes));
    return { nodes: tree };
  });

  registerMethod('teachingNote:delete', async (args) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const { id } = args as { id: string };
    const success = deps.teachingNoteService.deleteNode(id);
    return { success };
  });

  registerMethod('teachingNote:update', async (args) => {
    if (!deps) throw new Error('TeachingNoteHandler deps not initialized');
    const { id, label, content } = args as { id: string; label?: string; content?: string };
    const success = deps.teachingNoteService.updateNode(id, { label, content });
    return { success };
  });
}

function flatToTree(
  node: { id: string; parentId: string | null; label: string; content: string; createdAt: number },
  allNodes: Array<{ id: string; parentId: string | null; label: string; content: string; createdAt: number }>,
): { id: string; parentId: string | null; label: string; content: string; createdAt: number; children: unknown[] } {
  const children = allNodes
    .filter(n => n.parentId === node.id)
    .map(n => flatToTree(n, allNodes));
  return { ...node, children };
}
