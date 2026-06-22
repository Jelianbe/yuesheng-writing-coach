/**
 * workspace-registry 单测（ADR-002）
 *
 * 覆盖：
 * - registerWorkspace 添加/重复警告
 * - getWorkspace 检索
 * - getAllWorkspaces 全量
 * - getDefaultOpenWorkspaces 过滤
 * - resetForTesting 清空
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  registerWorkspace,
  getWorkspace,
  getAllWorkspaces,
  getDefaultOpenWorkspaces,
  resetForTesting,
  type WorkspaceRegistration,
} from '../workspace-registry';

const StubA: React.FC = () => null;
const StubC: React.FC = () => null;

const mockImport = (): Promise<{ default: React.FC }> =>
  Promise.resolve({ default: StubA });

function makeReg(
  id: string,
  name: string,
  icon: string,
  defaultOpen = false,
  component: () => Promise<{ default: React.FC }> = mockImport,
): WorkspaceRegistration {
  return { id, name, icon, defaultOpen, component };
}

describe('workspace-registry', () => {
  beforeEach(() => {
    resetForTesting();
  });

  it('registerWorkspace adds entry', () => {
    registerWorkspace(makeReg('test-a', '测试A', '✤'));
    expect(getWorkspace('test-a')).toBeDefined();
    expect(getWorkspace('test-a')?.name).toBe('测试A');
  });

  it('registerWorkspace warns on duplicate id', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    registerWorkspace(makeReg('dup', 'first', '✤'));
    registerWorkspace(makeReg('dup', 'second', '✎')); // duplicate
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('duplicate id: dup'));
    // 第一个注册不会被覆盖
    expect(getWorkspace('dup')?.name).toBe('first');
    warn.mockRestore();
  });

  it('getWorkspace returns undefined for unknown id', () => {
    expect(getWorkspace('non-existent')).toBeUndefined();
  });

  it('getAllWorkspaces returns all registered', () => {
    registerWorkspace(makeReg('a', 'A', '✤'));
    registerWorkspace(makeReg('b', 'B', '✎'));
    registerWorkspace(makeReg('c', 'C', '◐'));
    const all = getAllWorkspaces();
    expect(all).toHaveLength(3);
    expect(all.map(w => w.id).sort()).toEqual(['a', 'b', 'c']);
  });

  it('getDefaultOpenWorkspaces filters by defaultOpen=true', () => {
    registerWorkspace(makeReg('open-1', 'O1', '✤', true));
    registerWorkspace(makeReg('closed-1', 'C1', '✎', false));
    registerWorkspace(makeReg('open-2', 'O2', '◐', true));
    const defaults = getDefaultOpenWorkspaces();
    expect(defaults).toHaveLength(2);
    expect(defaults.map(w => w.id).sort()).toEqual(['open-1', 'open-2']);
  });

  it('resetForTesting clears all registrations', () => {
    registerWorkspace(makeReg('a', 'A', '✤'));
    registerWorkspace(makeReg('b', 'B', '✎'));
    expect(getAllWorkspaces()).toHaveLength(2);
    resetForTesting();
    expect(getAllWorkspaces()).toHaveLength(0);
    expect(getWorkspace('a')).toBeUndefined();
  });

  it('component is a function returning a Promise with default shape', async () => {
    const reg = makeReg('async-test', 'AT', '✤', true, () => Promise.resolve({ default: StubC }));
    registerWorkspace(reg);
    const loaded = await reg.component();
    expect(loaded.default).toBe(StubC);
  });
});
