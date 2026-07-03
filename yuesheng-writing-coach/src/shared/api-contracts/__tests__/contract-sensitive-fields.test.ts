/**
 * Contract 敏感字段标注测试 — Sprint 21 E-2
 *
 * 目的:
 * 1. 验证 4 个 contract(diagnosis/training/teaching-state/student-context)
 *    的 endpoint 标注了 sensitiveFields
 * 2. 验证标注字段名与 E-1 白名单 resources/config/payload-sanitize-whitelist.json
 *    的 services.<svc>.fields 键名一致(无遗漏)
 * 3. 验证 ApiResponse 类型可承载 sensitiveFields(typecheck 强制)
 *
 * DoD: ≥4 单测
 * 依据: dev-docs/tasks/sprint-21-plan.md §E-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { DiagnosisApi } from '../diagnosis.contract';
import { TrainingApi } from '../training.contract';
import { TeachingStateApi } from '../teaching-state.contract';
import { StudentContextApi } from '../student-context.contract';

/** 从白名单 JSON 读取字段集合(配置外置) */
function loadWhitelistFields(): Record<string, string[]> {
  const configPath = path.resolve(
    __dirname,
    '..',
    '..',
    '..',
    '..',
    'resources',
    'config',
    'payload-sanitize-whitelist.json',
  );
  const raw = JSON.parse(fs.readFileSync(configPath, 'utf-8')) as {
    services: Record<string, { enabled: boolean; fields: Record<string, string> }>;
  };
  const out: Record<string, string[]> = {};
  for (const [svc, cfg] of Object.entries(raw.services)) {
    if (cfg.enabled) {
      out[svc] = Object.keys(cfg.fields);
    }
  }
  return out;
}

/** 从 Api 对象提取某 endpoint 的 sensitiveFields */
function getSensitiveFields(
  endpoint: { response: { sensitiveFields?: ReadonlyArray<string> } },
): ReadonlyArray<string> | undefined {
  return endpoint.response.sensitiveFields;
}

describe('Contract sensitiveFields 标注 (Sprint 21 E-2)', () => {
  let whitelistFields: Record<string, string[]>;

  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    whitelistFields = loadWhitelistFields();
  });

  describe('4 contract 标注存在性', () => {
    it('diagnosis.query 标注了 evidence(ActiveProblem 元素字段)', () => {
      const fields = getSensitiveFields(DiagnosisApi.query);
      expect(fields).toBeDefined();
      expect(fields).toContain('evidence');
    });

    it('diagnosis.submitRewrite 标注了 evaluation.feedback + suggestion', () => {
      const fields = getSensitiveFields(DiagnosisApi.submitRewrite);
      expect(fields).toBeDefined();
      expect(fields).toEqual(
        expect.arrayContaining(['evaluation.feedback', 'evaluation.suggestion']),
      );
    });

    it('training.submit + evaluate 标注了 feedback + nextStep', () => {
      const submitFields = getSensitiveFields(TrainingApi.submit);
      const evaluateFields = getSensitiveFields(TrainingApi.evaluate);
      expect(submitFields).toContain('feedback');
      expect(submitFields).toContain('nextStep');
      expect(evaluateFields).toContain('feedback');
      expect(evaluateFields).toContain('nextStep');
    });

    it('teaching-state.get 标注了 diagnosisSummary + focusArea + activeProblems.evidence', () => {
      const fields = getSensitiveFields(TeachingStateApi.get);
      expect(fields).toBeDefined();
      expect(fields).toEqual(
        expect.arrayContaining([
          'diagnosisSummary',
          'focusArea',
          'activeProblems.evidence',
        ]),
      );
    });

    it('student-context.load 标注了 studentName + email + phone', () => {
      const fields = getSensitiveFields(StudentContextApi.load);
      expect(fields).toBeDefined();
      expect(fields).toEqual(
        expect.arrayContaining(['studentName', 'email', 'phone']),
      );
    });
  });

  describe('与 E-1 白名单字段名一致性', () => {
    /** 工具:检查 contract 字段集合是否 ⊆ 白名单某 service 的字段集合 */
    function contractFieldsInWhitelist(
      serviceName: string,
      contractFieldsList: ReadonlyArray<string>[],
    ): { ok: boolean; missing: string[] } {
      const whitelist = new Set(whitelistFields[serviceName] ?? []);
      const allContractFields = contractFieldsList
        .filter((f): f is ReadonlyArray<string> => f !== undefined)
        .flat();
      const missing: string[] = [];
      for (const cf of allContractFields) {
        if (!whitelist.has(cf)) missing.push(cf);
      }
      return { ok: missing.length === 0, missing };
    }

    it('diagnosis contract 字段 ⊆ 白名单 diagnosis 字段', () => {
      const r = contractFieldsInWhitelist('diagnosis', [
        getSensitiveFields(DiagnosisApi.query) ?? [],
        getSensitiveFields(DiagnosisApi.submitRewrite) ?? [],
      ]);
      if (!r.ok) {
        throw new Error(`diagnosis contract 字段缺失白名单覆盖: ${r.missing.join(', ')}`);
      }
      expect(r.ok).toBe(true);
    });

    it('training contract 字段 ⊆ 白名单 training 字段', () => {
      const r = contractFieldsInWhitelist('training', [
        getSensitiveFields(TrainingApi.submit) ?? [],
        getSensitiveFields(TrainingApi.evaluate) ?? [],
      ]);
      if (!r.ok) {
        throw new Error(`training contract 字段缺失白名单覆盖: ${r.missing.join(', ')}`);
      }
      expect(r.ok).toBe(true);
    });

    it('teaching-state contract 字段 ⊆ 白名单 teaching-state 字段', () => {
      const r = contractFieldsInWhitelist('teaching-state', [
        getSensitiveFields(TeachingStateApi.get) ?? [],
      ]);
      if (!r.ok) {
        throw new Error(`teaching-state contract 字段缺失白名单覆盖: ${r.missing.join(', ')}`);
      }
      expect(r.ok).toBe(true);
    });

    it('student-context contract 字段 ⊆ 白名单 student-context 字段', () => {
      const r = contractFieldsInWhitelist('student-context', [
        getSensitiveFields(StudentContextApi.load) ?? [],
        getSensitiveFields(StudentContextApi.save) ?? [],
      ]);
      if (!r.ok) {
        throw new Error(`student-context contract 字段缺失白名单覆盖: ${r.missing.join(', ')}`);
      }
      expect(r.ok).toBe(true);
    });
  });

  describe('ApiResponse 类型系统', () => {
    it('sensitiveFields 是 ReadonlyArray<string> 类型', () => {
      const fields = getSensitiveFields(DiagnosisApi.query);
      expect(Array.isArray(fields)).toBe(true);
      for (const f of fields ?? []) {
        expect(typeof f).toBe('string');
      }
    });

    it('未标注的 endpoint 返回 undefined(类型上仍合法,阶段 1 容忍)', () => {
      // diagnosis.update 不含敏感字段(只是状态变更)
      const fields = getSensitiveFields(DiagnosisApi.update);
      expect(fields).toBeUndefined();
    });
  });

  describe('E-1 → E-2 联动校验', () => {
    it('白名单 4 个 service 都至少有一个 contract 标注', () => {
      const svcToContractFields: Record<string, ReadonlyArray<string> | undefined> = {
        diagnosis: getSensitiveFields(DiagnosisApi.query),
        training: getSensitiveFields(TrainingApi.submit),
        'teaching-state': getSensitiveFields(TeachingStateApi.get),
        'student-context': getSensitiveFields(StudentContextApi.load),
      };
      for (const svc of Object.keys(whitelistFields)) {
        expect(svcToContractFields[svc]).toBeDefined();
        expect(svcToContractFields[svc]?.length).toBeGreaterThan(0);
      }
    });
  });
});
