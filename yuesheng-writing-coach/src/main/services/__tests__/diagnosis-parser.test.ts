import { describe, it, expect } from 'vitest';
import { SyndromeId, ActionId } from '../../../shared/constants';
import { SeverityLevel } from '../../../renderer/shared/types';
import { parseDiagnosisFromAIResponse } from '../diagnosis-parser';
import {
  buildAIResponseWithDiagnosis,
  buildPlainAIResponse,
  ALL_SYNDROME_IDS,
} from './test-factories';

const SESSION_ID = 'test-session-001';
const MESSAGE_ID = 'test-msg-001';

describe('parseDiagnosisFromAIResponse', () => {
  describe('正常解析', () => {
    it('正确解析包含诊断表 JSON 的 AI 回复', () => {
      const response = buildAIResponseWithDiagnosis(
        '你的问题在于世界观设定太大。',
        [{ id: SyndromeId.WorldviewBloat, severity: 'L2', evidence: ['我还没确定主角'] }],
        [ActionId.NarrowScope],
        0.85,
      );

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.cleanResponse).toBe('你的问题在于世界观设定太大。');
      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.sessionId).toBe(SESSION_ID);
      expect(result.diagnosis!.messageId).toBe(MESSAGE_ID);
      expect(result.diagnosis!.syndromes).toHaveLength(1);
      expect(result.diagnosis!.syndromes[0].id).toBe(SyndromeId.WorldviewBloat);
      expect(result.diagnosis!.syndromes[0].severity).toBe('L2');
      expect(result.diagnosis!.confidence).toBe(0.85);
      expect(result.diagnosis!.suggestedActions).toContain(ActionId.NarrowScope);
    });

    it('AI 同时回答问题和生成诊断表 - 端到端', () => {
      const response = buildAIResponseWithDiagnosis(
        '你的问题在于世界观设定过大，导致读者无法聚焦。建议先确定主角是谁，再从他的视角展开。',
        [
          { id: SyndromeId.WorldviewBloat, severity: 'L2', evidence: ['世界观设定过大'] },
          { id: SyndromeId.CharacterTool, severity: 'L1', evidence: ['人物关系复杂'] },
        ],
        [ActionId.NarrowScope, ActionId.ReturnToProtagonist],
      );

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.cleanResponse).toBe(
        '你的问题在于世界观设定过大，导致读者无法聚焦。建议先确定主角是谁，再从他的视角展开。',
      );
      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.syndromes).toHaveLength(2);
      expect(result.diagnosis!.syndromes[0].id).toBe(SyndromeId.WorldviewBloat);
      expect(result.diagnosis!.syndromes[1].id).toBe(SyndromeId.CharacterTool);
      expect(result.diagnosis!.suggestedActions).toContain(ActionId.NarrowScope);
      expect(result.diagnosis!.suggestedActions).toContain(ActionId.ReturnToProtagonist);
    });

    it('正确解析 P009-P010 症候', () => {
      const response = buildAIResponseWithDiagnosis(
        '你的角色缺乏内在驱动力。',
        [
          { id: SyndromeId.MotivationDeficit, severity: 'L2', evidence: ['角色行为缺乏内在驱动力'] },
          { id: SyndromeId.OCPlanarization, severity: 'L2', evidence: ['性格从头到尾没变'] },
        ],
        [ActionId.ContrastShow],
      );

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.syndromes).toHaveLength(2);
      expect(result.diagnosis!.syndromes[0].id).toBe(SyndromeId.MotivationDeficit);
      expect(result.diagnosis!.syndromes[1].id).toBe(SyndromeId.OCPlanarization);
      expect(result.diagnosis!.syndromes[0].severity).toBe('L2');
      expect(result.diagnosis!.syndromes[1].severity).toBe('L2');
    });
  });

  describe('边界情况', () => {
    it('无诊断表标记时返回原始回复和 null', () => {
      const response = buildPlainAIResponse('只是一段普通对话，没有诊断信息。');

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.cleanResponse).toBe(response);
      expect(result.diagnosis).toBeNull();
    });

    it('仅存在开始标记但缺少结束标记时返回原始回复和 null', () => {
      const response = '一些内容\n---DIAGNOSIS_START---\n{"syndromes":[]}';

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.cleanResponse).toBe(response);
      expect(result.diagnosis).toBeNull();
    });

    it('诊断表 JSON 格式错误时返回纯净回复和 null', () => {
      const response = `前面内容\n\n---DIAGNOSIS_START---\n{ invalid json }\n---DIAGNOSIS_END---`;

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.cleanResponse).toBe('前面内容');
      expect(result.diagnosis).toBeNull();
    });

    it('AI 回复为空字符串时返回空和 null', () => {
      const result = parseDiagnosisFromAIResponse('', SESSION_ID, MESSAGE_ID);

      expect(result.cleanResponse).toBe('');
      expect(result.diagnosis).toBeNull();
    });
  });

  describe('安全性过滤', () => {
    it('不存在的病症 ID 被过滤', () => {
      const response = buildAIResponseWithDiagnosis(
        '诊断内容',
        [{ id: SyndromeId.WorldviewBloat, severity: 'L2' }],
        [],
      );
      // 注入非法 ID 的原始 JSON（不走工厂以测试过滤逻辑）
      const injected = response.replace(
        `"id": "${SyndromeId.WorldviewBloat}"`,
        '"id": "P999"',
      );

      const result = parseDiagnosisFromAIResponse(injected, SESSION_ID, MESSAGE_ID);

      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.syndromes).toHaveLength(0);
    });

    it('非法严重度等级被过滤', () => {
      const response = buildAIResponseWithDiagnosis(
        '测试',
        [{ id: SyndromeId.WorldviewBloat, severity: 'L2' }],
        [],
      );
      const injected = response.replace('"L2"', '"L5"');

      const result = parseDiagnosisFromAIResponse(injected, SESSION_ID, MESSAGE_ID);

      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.syndromes).toHaveLength(0);
    });

    it('所有枚举中的病症 ID 都应被认可', () => {
      const syndromes = ALL_SYNDROME_IDS.slice(0, 3).map((id) => ({ id }));
      const response = buildAIResponseWithDiagnosis('多病症测试', syndromes, []);

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.syndromes).toHaveLength(3);
    });
  });

  describe('值域裁剪', () => {
    it('confidence 大值被裁剪到 1', () => {
      const response = buildAIResponseWithDiagnosis('测试', [], [], 99);

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.confidence).toBe(1);
    });

    it('confidence 负值被裁剪到 0', () => {
      const response = buildAIResponseWithDiagnosis('测试', [], [], -1);

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.confidence).toBe(0);
    });

    it('无病症但有建议动作时生成有效诊断条目', () => {
      const response = buildAIResponseWithDiagnosis(
        '建议',
        [],
        [ActionId.NarrowScope, ActionId.StageSplit],
        0.9,
      );

      const result = parseDiagnosisFromAIResponse(response, SESSION_ID, MESSAGE_ID);

      expect(result.diagnosis).not.toBeNull();
      expect(result.diagnosis!.syndromes).toHaveLength(0);
      expect(result.diagnosis!.suggestedActions).toContain(ActionId.NarrowScope);
      expect(result.diagnosis!.suggestedActions).toContain(ActionId.StageSplit);
    });
  });
});
