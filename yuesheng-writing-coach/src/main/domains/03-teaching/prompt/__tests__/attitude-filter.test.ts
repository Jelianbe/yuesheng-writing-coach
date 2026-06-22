/**
 * AttitudeFilter 实质过滤测试
 *
 * 覆盖：
 * 1. 默认配置（无 configPath）不过滤
 * 2. doubao 档：不过滤
 * 3. yuesheng 档：轻度优化
 * 4. sensei 档：删除鼓励话术
 * 5. 配置文件缺失降级
 * 6. 长度下限保护
 * 7. 集成到 SkillDispatcher
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { AttitudeFilter } from '../attitude-filter';
import { SkillDispatcher } from '../skill-dispatcher';

const TEST_DIR = path.join(os.tmpdir(), 'test-attitude-filter-' + Date.now());
const TEST_CONFIG = path.join(TEST_DIR, 'attitude-filter.json');

beforeAll(() => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
  fs.writeFileSync(TEST_CONFIG, JSON.stringify({
    version: '1.0',
    rules: {
      doubao: { removePatterns: [], replacePatterns: [] },
      yuesheng: { removePatterns: [], replacePatterns: [] },
      sensei: {
        removePatterns: [
          '(?:加油|棒|真棒|非常好)(?=[，。！？、\\s])',
        ],
        replacePatterns: [
          { pattern: '希望.{0,10}', replacement: '' },
        ],
      },
    },
    minContentLength: { default: 50 },
  }, null, 2));
});

afterAll(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

describe('AttitudeFilter', () => {
  it('无 configPath 时使用默认（不过滤）', () => {
    const filter = new AttitudeFilter();
    const content = '加油！这个想法棒极了，继续努力！';
    const result = filter.apply(content, 'sensei');
    expect(result).toBe(content);
  });

  it('doubao 档：内容不变', () => {
    const filter = new AttitudeFilter(TEST_CONFIG);
    const content = '加油！这个想法棒极了，继续努力！';
    const result = filter.apply(content, 'doubao');
    expect(result).toBe(content);
  });

  it('sensei 档：删除"加油""棒""非常好"等鼓励话术', () => {
    const filter = new AttitudeFilter(TEST_CONFIG);
    // 内容必须 > 50 字符以避免长度下限保护触发
    // 构造 100+ 字符：50 字符技术内容 + 30 字符鼓励话术，过滤后剩 60+ 字符
    const content =
      '这一段在描写角色心理活动时需要更深层的笔触。通过细节让读者感受人物的内心冲突，' +
      '加油！这个想法棒！非常好。继续写作时要保持这样的节奏和氛围，' +
      '希望你能继续努力。希望能帮到你。';
    const result = filter.apply(content, 'sensei');
    expect(result).not.toContain('加油');
    expect(result).not.toContain('非常好');
    // 期望保留技术性内容
    expect(result).toContain('角色心理活动');
    expect(result).toContain('细节让读者');
  });

  it('yuesheng 档：保留内容（无规则）', () => {
    const filter = new AttitudeFilter(TEST_CONFIG);
    const content = '加油！这个想法棒极了！';
    const result = filter.apply(content, 'yuesheng');
    expect(result).toBe(content);
  });

  it('配置文件不存在时降级为不过滤', () => {
    const filter = new AttitudeFilter(path.join(TEST_DIR, 'non-existent.json'));
    const content = '加油！这个想法棒极了！';
    const result = filter.apply(content, 'sensei');
    expect(result).toBe(content);
  });

  it('配置文件无效时降级为不过滤', () => {
    const badConfig = path.join(TEST_DIR, 'bad.json');
    fs.writeFileSync(badConfig, '{ not valid json }');
    const filter = new AttitudeFilter(badConfig);
    const content = '加油！';
    expect(() => filter.apply(content, 'sensei')).not.toThrow();
    expect(filter.apply(content, 'sensei')).toBe(content);
  });

  it('长度下限保护：过滤后内容太短时返回原内容', () => {
    const filter = new AttitudeFilter(TEST_CONFIG);
    // 构造过滤后 < 50 字符的内容
    // - removePattern 会删 "加油" 等
    // - replacePattern 会删 "希望..." 等
    // 主体 80 字符，过滤后 < 50 → 返回原内容
    const content = '加油！加油！加油！加油！希望继续努力。希望保持节奏。' +
      '加油！加油！加油！加油！希望继续努力。希望保持节奏。';
    const result = filter.apply(content, 'sensei');
    // 过滤后 result 远 < 50 字符，触发长度下限保护，返回原内容
    expect(result).toBe(content);
  });

  it('连续空行被清理', () => {
    const filter = new AttitudeFilter(TEST_CONFIG);
    // 长内容确保不被长度保护回退
    const content = '第一段文字内容。\n\n\n\n第二段文字内容。\n\n\n第三段文字内容。'.repeat(3);
    const result = filter.apply(content, 'sensei');
    expect(result).not.toMatch(/\n\n\n/);
  });

  it('集成到 SkillDispatcher：sensei 档 composePrompt 应用过滤', () => {
    // 创建临时 skills 目录
    const skillsDir = path.join(TEST_DIR, 'skills-dispatcher');
    fs.mkdirSync(skillsDir, { recursive: true });
    // 长内容确保不被长度保护回退
    const yaml = `---
id: test-encouraging
estimatedTokens: 100
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao, yuesheng, sensei]
---

# 这段内容加油！你真棒！这个想法非常好。继续写作时希望保持这个节奏，希望能帮到你。
这一段在描写角色心理活动时需要更深层的笔触。通过细节让读者感受人物的内心冲突。
写作时要注意视角的一致性和节奏的把握，让故事自然地推进。`;
    fs.writeFileSync(path.join(skillsDir, 'test-encouraging.md'), yaml);

    // 不注入 filter
    const d1 = new SkillDispatcher();
    d1.load(skillsDir);
    const before = d1.composePrompt('P0_INIT', 'sensei');
    expect(before).toContain('加油');

    // 注入 filter
    const d2 = new SkillDispatcher();
    d2.load(skillsDir);
    d2.setAttitudeFilter(new AttitudeFilter(TEST_CONFIG));
    const after = d2.composePrompt('P0_INIT', 'sensei');
    expect(after).not.toContain('加油');

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });
});
