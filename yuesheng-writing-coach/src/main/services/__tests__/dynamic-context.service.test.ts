/**
 * DynamicContextService 单元测试
 *
 * 测试覆盖：
 * 1. 片段提取函数（extractSnippetsFromMarkdown）
 * 2. 症候-动作关联（getRelevantActionIds）
 * 3. 核心 Prompt 装载（铁三角降级提取）
 * 4. 知识文件片段索引构建
 * 5. loadContext 和 formatReferenceDrawer 集成测试
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as path from 'path';

const RESOURCES_ROOT = path.join(process.cwd(), 'resources');

import { DynamicContextService, extractSnippetsFromMarkdown, getRelevantActionIds } from '../dynamic-context.service';

describe('extractSnippetsFromMarkdown', () => {
  it('应提取带标记的症候片段', () => {
    const text = `
<!-- SYNDROME:P001 -->
## P001 世界观膨胀
**识别标准**：开篇大量世界观设定
<!-- END:SYNDROME:P001 -->
<!-- SYNDROME:P002 -->
## P002 角色工具人化
**识别标准**：角色缺乏独立动机
<!-- END:SYNDROME:P002 -->
`;
    const snippets = extractSnippetsFromMarkdown(text, 'SYNDROME');
    expect(snippets).toHaveLength(2);
    expect(snippets[0].id).toBe('P001');
    expect(snippets[0].content).toContain('世界观膨胀');
    expect(snippets[1].id).toBe('P002');
    expect(snippets[1].content).toContain('角色工具人化');
  });

  it('应提取带标记的动作片段', () => {
    const text = `
<!-- ACTION:A001 -->
## A001 缩小范围
**精髓**：从宏大设定回到具体场景
<!-- END:ACTION:A001 -->
`;
    const snippets = extractSnippetsFromMarkdown(text, 'ACTION');
    expect(snippets).toHaveLength(1);
    expect(snippets[0].id).toBe('A001');
    expect(snippets[0].content).toContain('缩小范围');
  });

  it('无标记时应返回空数组', () => {
    const text = '## 普通标题\n普通内容';
    const snippets = extractSnippetsFromMarkdown(text, 'SYNDROME');
    expect(snippets).toHaveLength(0);
  });
});

describe('getRelevantActionIds', () => {
  it('应根据症候返回关联的动作 ID', () => {
    const actions = getRelevantActionIds(['P001']);
    expect(actions).toContain('A001'); // 缩小范围
    expect(actions).toContain('A005'); // 阶段拆分
  });

  it('多个症候应合并去重动作', () => {
    const actions = getRelevantActionIds(['P001', 'P004']);
    // P001 → A001, A005; P004 → A002, A001
    expect(actions).toContain('A001');
    expect(actions).toContain('A002');
    expect(actions).toContain('A005');
    expect(actions.length).toBe(3); // 去重
  });

  it('不存在的症候应返回空数组', () => {
    const actions = getRelevantActionIds(['P999']);
    expect(actions).toHaveLength(0);
  });

  it('空输入应返回空数组', () => {
    const actions = getRelevantActionIds([]);
    expect(actions).toHaveLength(0);
  });
});

describe('DynamicContextService', () => {
  let service: DynamicContextService;

  beforeEach(() => {
    service = new DynamicContextService('/mock/resources');
    service.clearCache();
  });

  describe('loadContext', () => {
    it('应装载核心 Prompt', () => {
      const bundle = service.loadContext([]);
      expect(bundle.corePrompt).toBeDefined();
      expect(typeof bundle.corePrompt).toBe('string');
      // 核心 Prompt 应包含铁三角相关内容
      expect(bundle.corePrompt.length).toBeGreaterThan(0);
    });

    it('有活跃症候时应装载对应片段', () => {
      const bundle = service.loadContext(['P001']);
      expect(bundle.syndromeSnippets.length).toBeGreaterThan(0);
      const snippet = bundle.syndromeSnippets[0];
      expect(snippet.id).toBe('P001');
      expect(snippet.content).toBeDefined();
    });

    it('有活跃症候时应装载关联的动作片段', () => {
      const bundle = service.loadContext(['P001']);
      // P001 → A001, A005
      expect(bundle.actionSnippets.length).toBeGreaterThan(0);
      const actionIds = bundle.actionSnippets.map((s: { id: string }) => s.id);
      expect(actionIds).toContain('A001');
      expect(actionIds).toContain('A005');
    });

    it('无活跃症候时参考抽屉应为空', () => {
      const bundle = service.loadContext([]);
      expect(bundle.syndromeSnippets).toHaveLength(0);
      expect(bundle.actionSnippets).toHaveLength(0);
    });
  });

  describe('formatReferenceDrawer', () => {
    it('应正确格式化参考抽屉内容', () => {
      const bundle = service.loadContext(['P001']);
      const formatted = service.formatReferenceDrawer(bundle);

      if (bundle.syndromeSnippets.length > 0) {
        expect(formatted).toContain('参考抽屉：症候手册');
        expect(formatted).toContain('P001');
      }

      if (bundle.actionSnippets.length > 0) {
        expect(formatted).toContain('参考抽屉：教学动作');
        expect(formatted).toContain('A001');
      }
    });

    it('空参考抽屉应返回空字符串', () => {
      const emptyBundle = {
        corePrompt: 'test',
        syndromeSnippets: [],
        actionSnippets: [],
        caseSnippets: [],
      };
      const formatted = service.formatReferenceDrawer(emptyBundle);
      expect(formatted).toBe('');
    });
  });

  describe('clearCache', () => {
    it('清除缓存后应重新加载知识文件', () => {
      // 第一次加载
      service.loadContext(['P001']);
      // 清除缓存
      service.clearCache();
      // 第二次加载应重新读取文件
      const bundle = service.loadContext(['P001']);
      expect(bundle.corePrompt).toBeDefined();
    });
  });
});
