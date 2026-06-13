/**
 * 证据分组工具
 *
 * 职责：将 DiagnosisAnalysis.keyPassages 按 syndromeRef 分组，
 *       映射到各症候的 evidence 字段。
 *
 * 降级策略：如果 AI 未输出 syndromeRef（向后兼容），所有症候共享前 3 个 keyPassages。
 */

import { KeyPassage } from '../../renderer/shared/types';

/**
 * 检查 syndromeRef 是否有效（存在于症候元数据中）
 * 使用动态导入避免循环依赖
 */
function isValidSyndromeRef(ref: string): boolean {
  // 症候 ID 格式：P/H/E + 三位数字（P001 ~ P999, H001 ~ H003, E001 ~ E003）
  return /^[PHE]\d{3}$/.test(ref);
}

/**
 * 按 syndromeRef 分组 keyPassages
 *
 * 处理规则：
 * 1. 过滤掉 syndromeRef 无效的 keyPassage（拼写错误等）
 * 2. 每个症候最多保留 2 条证据（prompt 限制）
 * 3. 去重：同症候内相同的 text 只保留一条
 *
 * @returns Map<syndromeId, text[]>，按症候分组的原文片段
 */
export function groupPassagesBySyndrome(
  keyPassages: KeyPassage[],
): Map<string, string[]> {
  const hasSyndromeRef = keyPassages.some(kp => kp.syndromeRef);

  if (!hasSyndromeRef) {
    // 降级：所有症候共享前 3 个 keyPassages
    const shared = keyPassages.slice(0, 3).map(kp => kp.text);
    const result = new Map<string, string[]>();
    result.set('__shared__', shared);
    return result;
  }

  const passagesBySyndrome = new Map<string, string[]>();

  for (const kp of keyPassages) {
    if (!kp.syndromeRef) {
      // 未标注 syndromeRef 的 passage 在分组模式下被丢弃
      // （可能是通用评价，不影响核心证据）
      continue;
    }

    // 校验 syndromeRef 有效性
    if (!isValidSyndromeRef(kp.syndromeRef)) {
      console.warn(`[EvidenceGrouping] Invalid syndromeRef: "${kp.syndromeRef}" in passage: "${kp.text.slice(0, 30)}..."`);
      continue;
    }

    const existing = passagesBySyndrome.get(kp.syndromeRef) ?? [];

    // 去重：相同的 text 不重复添加
    if (existing.includes(kp.text)) {
      continue;
    }

    // 每个症候最多 2 条证据（添加前检查）
    if (existing.length >= 2) {
      continue;
    }

    existing.push(kp.text);
    passagesBySyndrome.set(kp.syndromeRef, existing);
  }

  return passagesBySyndrome;
}

/**
 * 获取某症候的证据片段
 *
 * @param passagesBySyndrome - 分组后的 keyPassages
 * @param syndromeId - 症候 ID
 * @param fallbackShared - 降级用的共享证据（当该症候无分组证据时使用）
 * @returns 原文片段数组
 */
export function getEvidenceForSyndrome(
  passagesBySyndrome: Map<string, string[]>,
  syndromeId: string,
  _fallbackShared: string[],
): string[] {
  // 如果是降级模式（__shared__ 键存在），所有症候用共享证据
  if (passagesBySyndrome.has('__shared__')) {
    return passagesBySyndrome.get('__shared__')!;
  }

  // 按症候取证据（已在分组阶段做了去重和上限控制）
  const evidence = passagesBySyndrome.get(syndromeId);

  if (!evidence || evidence.length === 0) {
    // 该症候无对应证据
    console.warn(`[EvidenceGrouping] No evidence found for syndrome: ${syndromeId}`);
    return [];
  }

  return evidence;
}
