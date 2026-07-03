/**
 * PayloadSanitizer 单测 — Sprint 21 E-1
 *
 * 覆盖:
 * 1. 5 种动作 × 4 service 组合测试
 * 2. 命中计数埋点(stats)
 * 3. 降级安全:白名单缺失 / 字段不存在 / 异常输入
 * 4. 嵌套路径(evidence.feedback)
 * 5. 数组特化(truncate-nested for activeProblems)
 * 6. 不修改原对象(纯函数)
 * 7. service 未知 / disabled → 返回原 payload
 *
 * DoD: ≥20 单测
 * 依据: dev-docs/tasks/sprint-21-plan.md §E-1
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { PayloadSanitizer } from '../payload-sanitizer.service';

function writeTempWhitelist(content: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sanitize-'));
  const file = path.join(dir, 'whitelist.json');
  fs.writeFileSync(file, JSON.stringify(content), 'utf-8');
  return file;
}

const baseWhitelist = {
  version: '1.0',
  truncate: { defaultMaxChars: 80 },
  services: {
    diagnosis: {
      enabled: true,
      fields: {
        originalText: 'redact',
        rewrittenText: 'truncate',
        'evaluation.feedback': 'truncate',
        'evaluation.suggestion': 'truncate',
      },
    },
    training: {
      enabled: true,
      fields: {
        originalQuote: 'truncate',
        userDraft: 'truncate',
        challengeDescription: 'truncate',
        constraint: 'truncate',
        feedback: 'truncate',
        nextStep: 'truncate',
      },
    },
    'teaching-state': {
      enabled: true,
      fields: {
        diagnosisSummary: 'truncate',
        focusArea: 'omit',
        'activeProblems.evidence': 'truncate-nested',
      },
    },
    'student-context': {
      enabled: true,
      fields: {
        studentName: 'mask',
        email: 'redact',
        phone: 'redact',
      },
    },
  },
};

describe('PayloadSanitizer (Sprint 21 E-1)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  describe('5 种动作 × 4 service 组合', () => {
    it('diagnosis.originalText → redact', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('diagnosis', { originalText: '我的秘密日记内容...', id: 'P001' });
      expect(out).toEqual({ originalText: '[REDACTED]', id: 'P001' });
    });

    it('diagnosis.rewrittenText → truncate (≤80 字符不截断)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const short = 'a'.repeat(50);
      const out = s.sanitize('diagnosis', { rewrittenText: short });
      expect((out as { rewrittenText: string }).rewrittenText).toBe(short);
    });

    it('diagnosis.rewrittenText → truncate (>80 字符截断)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const long = 'a'.repeat(150);
      const out = s.sanitize('diagnosis', { rewrittenText: long });
      expect((out as { rewrittenText: string }).rewrittenText).toBe('a'.repeat(80) + '...');
    });

    it('diagnosis.evaluation.feedback → truncate(嵌套路径)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('diagnosis', {
        evaluation: { feedback: 'a'.repeat(120), score: 8 },
      });
      expect((out as { evaluation: { feedback: string; score: number } }).evaluation.feedback)
        .toBe('a'.repeat(80) + '...');
      expect((out as { evaluation: { feedback: string; score: number } }).evaluation.score).toBe(8);
    });

    it('training.userDraft → truncate', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('training', { userDraft: 'a'.repeat(200), passed: true });
      expect((out as { userDraft: string; passed: boolean }).userDraft).toBe('a'.repeat(80) + '...');
      expect((out as { userDraft: string; passed: boolean }).passed).toBe(true);
    });

    it('teaching-state.focusArea → omit(从对象删除)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('teaching-state', { focusArea: 'character', id: 'P001' });
      expect(out).toEqual({ id: 'P001' });
      expect((out as { focusArea?: string }).focusArea).toBeUndefined();
    });

    it('teaching-state.activeProblems → truncate-nested(限 evidence 数组)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('teaching-state', {
        activeProblems: [
          { id: 'P001', evidence: ['a'.repeat(120), 'short'] },
          { id: 'P002', evidence: ['b'.repeat(200)] },
        ],
      });
      const ap = (out as { activeProblems: Array<{ id: string; evidence: string[] }> }).activeProblems;
      expect(ap[0].id).toBe('P001');
      expect(ap[0].evidence[0]).toBe('a'.repeat(80) + '...');
      expect(ap[0].evidence[1]).toBe('short'); // 未超 80 字符
      expect(ap[1].evidence[0]).toBe('b'.repeat(80) + '...');
    });

    it('student-context.studentName → mask', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('student-context', { studentName: 'Alice李', email: 'a@b.com' });
      // 'Alice李' = 6 字符:首 1 + 4* + 末 1
      expect((out as { studentName: string }).studentName).toBe('A****李');
      expect((out as { email: string }).email).toBe('[REDACTED]');
    });

    it('student-context.email → redact', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('student-context', { email: 'alice@example.com' });
      expect((out as { email: string }).email).toBe('[REDACTED]');
    });

    it('mask 在 2 字符以内 → 全 *', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const out = s.sanitize('student-context', { studentName: 'AB' });
      expect((out as { studentName: string }).studentName).toBe('**');
    });
  });

  describe('hash 动作(虽然白名单未启用,直接验证方法)', () => {
    it('hashValue 等价性 + 长度(8 字符 hex)', () => {
      const tmp = writeTempWhitelist({
        version: '1.0',
        services: { test: { enabled: true, fields: { secret: 'hash' } } },
      });
      const s2 = new PayloadSanitizer(tmp);
      const out = s2.sanitize('test', { secret: 'my-secret' });
      expect((out as { secret: string }).secret).toMatch(/^[0-9a-f]{8}$/);
    });
  });

  describe('命中计数(stats)', () => {
    it('多次 sanitize 累加 total + byAction', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      s.sanitize('diagnosis', { originalText: 'a' }); // redact
      s.sanitize('training', { userDraft: 'a'.repeat(100) }); // truncate
      s.sanitize('teaching-state', { focusArea: 'x' }); // omit
      s.sanitize('student-context', { studentName: '李四' }); // mask
      const stats = s.stats();
      expect(stats.total).toBe(4);
      expect(stats.byAction.redact).toBe(1);
      expect(stats.byAction.truncate).toBe(1);
      expect(stats.byAction.omit).toBe(1);
      expect(stats.byAction.mask).toBe(1);
    });

    it('resetStats 归零', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      s.sanitize('diagnosis', { originalText: 'a' });
      s.resetStats();
      expect(s.stats().total).toBe(0);
    });

    it('字段不存在 → 不计入命中', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      s.sanitize('diagnosis', { id: 'P001' }); // 无 originalText
      expect(s.stats().total).toBe(0);
    });
  });

  describe('降级安全', () => {
    it('白名单文件不存在 → hasWhitelist=false + sanitize 返回原 payload', () => {
      const s = new PayloadSanitizer('/non/existent/whitelist.json');
      expect(s.hasWhitelist()).toBe(false);
      const input = { secret: 'visible' };
      const out = s.sanitize('diagnosis', input);
      expect(out).toEqual({ secret: 'visible' });
    });

    it('白名单 JSON 非法 → hasWhitelist=false', () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sanitize-bad-'));
      const file = path.join(dir, 'whitelist.json');
      fs.writeFileSync(file, '{ broken', 'utf-8');
      const s = new PayloadSanitizer(file);
      expect(s.hasWhitelist()).toBe(false);
    });

    it('白名单 services 字段缺失 → hasWhitelist=false', () => {
      const file = writeTempWhitelist({ version: '1.0' });
      const s = new PayloadSanitizer(file);
      expect(s.hasWhitelist()).toBe(false);
    });

    it('未知 service → 返回原 payload(无副作用)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const input = { secret: 'x' };
      const out = s.sanitize('unknown-service', input);
      expect(out).toEqual(input);
      expect(s.stats().total).toBe(0);
    });

    it('disabled service → 返回原 payload', () => {
      const cfg = writeTempWhitelist({
        version: '1.0',
        services: { diagnosis: { enabled: false, fields: { originalText: 'redact' } } },
      });
      const s = new PayloadSanitizer(cfg);
      const input = { originalText: 'still-visible' };
      const out = s.sanitize('diagnosis', input);
      expect(out).toEqual(input);
    });

    it('payload 为 null → 返回 null 不崩', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      expect(s.sanitize('diagnosis', null)).toBeNull();
    });

    it('payload 为字符串 → 返回原字符串(白名单不适用)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      expect(s.sanitize('diagnosis', 'plain-string')).toBe('plain-string');
    });
  });

  describe('纯函数语义(不修改原对象)', () => {
    it('sanitize 后原对象未被修改', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const input = { originalText: 'secret', id: 'P001' };
      const before = JSON.stringify(input);
      s.sanitize('diagnosis', input);
      expect(JSON.stringify(input)).toBe(before);
    });

    it('多次 sanitize 同一 input 返回结构等价(纯函数)', () => {
      const cfg = writeTempWhitelist(baseWhitelist);
      const s = new PayloadSanitizer(cfg);
      const input = { originalText: 'secret' };
      const out1 = s.sanitize('diagnosis', input);
      const out2 = s.sanitize('diagnosis', input);
      expect(out1).toEqual(out2);
    });
  });

  describe('字段路径边界', () => {
    it('中间路径不存在 → 跳过(不创建空对象)', () => {
      const tmp = writeTempWhitelist({
        version: '1.0',
        services: { test: { enabled: true, fields: { 'a.b.c': 'redact' } } },
      });
      const s = new PayloadSanitizer(tmp);
      const out = s.sanitize('test', { id: 1 });
      // getByPath 返回 undefined → 跳过,原对象不变
      expect(out).toEqual({ id: 1 });
      expect(s.stats().total).toBe(0);
    });

    it('omit 对顶层不存在的字段 → 无副作用', () => {
      const tmp = writeTempWhitelist({
        version: '1.0',
        services: { test: { enabled: true, fields: { missing: 'omit' } } },
      });
      const s = new PayloadSanitizer(tmp);
      const out = s.sanitize('test', { id: 1 });
      expect(out).toEqual({ id: 1 });
      expect(s.stats().total).toBe(0);
    });

    it('顶层字段 redact → 命中', () => {
      const tmp = writeTempWhitelist({
        version: '1.0',
        services: { test: { enabled: true, fields: { secret: 'redact' } } },
      });
      const s = new PayloadSanitizer(tmp);
      const out = s.sanitize('test', { secret: 'value' });
      expect((out as { secret: string }).secret).toBe('[REDACTED]');
      expect(s.stats().total).toBe(1);
    });
  });
});
