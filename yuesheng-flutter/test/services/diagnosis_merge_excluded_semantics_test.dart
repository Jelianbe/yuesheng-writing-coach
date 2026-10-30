// ─────────────────────────────────────────────────────────────
// T-20261024-06 · merge 链 excluded 传播 —— 判据 4（语义 B1-B4）+ 判据 6（两源归因）
//
// 语义判据真源：设计批 §4.2 B1-B4（章可循会审段）。
// 本文件全部 fixture 标注「分片级源」——设计批 §6 登记风险 1：
// merge 场景集外率归因必须区分「分片级透传 excluded」与「聊天轮次级 excluded」
// 两源（轮次级源见批 2 test/services/diagnosis_excluded_validator_test.dart）。
//
// 观测面同文件1：buildMergePrompt 公开产物（不直测私有函数）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('判据 4 · 语义不错合（设计批 §4.2 B1-B4）', () {
    test('B1 跨轮矛盾保轨迹：片1报出 P017 + 片2排除 P017 → 两路记录各自保留，不去重二选一', () {
      // B1：同 S 在 A 轮 syndromes、B 轮 excluded 不是矛盾，是修订轨迹。
      // 呈现须锚定轮次读作「已收敛」，不得去重二选一丢弃（设计批 §4.2 B1）。
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P017',
              description: '报出：开篇视角问题成立',
              evidence: ['她反复跳视角'],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
        const ChunkAnalysisResult(
          chunkIndex: 1,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: '情绪标签化',
              evidence: ['他很激动'],
              severity: 'L1',
              excluded: [
                ParsedExclusion(
                  syndromeId: 'P017',
                  reason: '片2语境下证据不足，降级为未触发记录',
                ),
              ],
            ),
          ],
          success: true,
        ),
      ], diagnosisContext: '');

      // 阳性对照：报出 note（片1）在。
      expect(
        prompt,
        contains('报出：开篇视角问题成立'),
        reason: '片1 报出 P017 必须保留在 merge notes',
      );
      // 排除记录（片2）在 = 轨迹保留；若实现把 P017 二选一去重，本理由消失即红。
      expect(
        prompt,
        contains('片2语境下证据不足，降级为未触发记录'),
        reason: '片2 排除 P017 必须与片1 报出并存（修订轨迹保不丢）',
      );
    });

    test('B2 去重不膨胀：两片同 ID 不同理由 → 两份理由各自出现，数据层不聚合替代', () {
      // B2：跨轮按 ID 去重后若用单条 reason 代表多轮 ⇒ 语义膨胀红。
      // 形态甲数据层不聚合（设计批 §3.1：数据层与呈现层分离，折叠只在 L3）。
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: 'd1',
              evidence: ['e1'],
              severity: 'L1',
              excluded: [
                ParsedExclusion(syndromeId: 'P017', reason: '理由甲：本段场景内不成立'),
              ],
            ),
          ],
          success: true,
        ),
        const ChunkAnalysisResult(
          chunkIndex: 1,
          notes: [
            ChunkNote(
              syndromeId: 'P002',
              description: 'd2',
              evidence: ['e2'],
              severity: 'L1',
              excluded: [
                ParsedExclusion(syndromeId: 'P017', reason: '理由乙：跨片关系未支持'),
              ],
            ),
          ],
          success: true,
        ),
      ], diagnosisContext: '');

      // 阳性对照：P017 作为 excluded 键值出现（至少一次）。
      expect(prompt, contains('"excluded"'));
      // R1/R2 必须都在——若实现误按 ID 聚合成单条，R2 被 R1 覆盖即红。
      expect(
        prompt,
        contains('理由甲：本段场景内不成立'),
        reason: '片1 排除理由必须独立保留（不得被片2 理由替代）',
      );
      expect(
        prompt,
        contains('理由乙：跨片关系未支持'),
        reason: '片2 排除理由必须独立保留（不得用单条 reason 代表多轮，B2）',
      );
    });

    test('B3 不互译：uncertain=true 与 excluded 是独立两键，互不顶替', () {
      // B3：excluded=已判否（肯定否定句）；uncertain=判不了（缺信息）。
      // merge 态若把 uncertain 静默改写进 excluded ⇒ 互译红（设计批 §4.2 B3）。
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P022',
              description: '节奏比例疑似失衡，缺全文基线',
              evidence: ['这一段写得很长'],
              severity: 'L1',
              uncertain: true,
              excluded: [
                ParsedExclusion(syndromeId: 'P017', reason: '本段证据不足，明确判否'),
              ],
            ),
          ],
          success: true,
        ),
      ], diagnosisContext: '');

      // uncertain 标记独立保留（判不了仍留待补信息桶）。
      expect(
        prompt,
        contains('"uncertain": true'),
        reason: 'uncertain=true 必须独立保留，不得被改写进 excluded（B3）',
      );
      // excluded 元素是肯定否定句理由（不是「缺…信息」型）。
      expect(
        prompt,
        contains('本段证据不足，明确判否'),
        reason: 'excluded reason 必须是肯定否定句，uncertain 的「缺信息」理由不得混入',
      );
      expect(prompt, contains('"excluded"'));
    });

    test('B4 不接 rejected 名册：excluded 序列化产物无 confirmationStatus/rejected 键', () {
      // B4 硬边界（设计批 §4.2 + 裁定单 §二.3）：excluded ≠
      // activeProblems.confirmationStatus='rejected' ≠ weak→excluded from injection。
      // 本批不落库，测序列化层形状守卫：excluded 元素只带 syndromeId+reason，
      // 绝不携带确认状态机字段（互写即污染确认状态机）。
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: 'd',
              evidence: ['e'],
              severity: 'L1',
              excluded: [
                ParsedExclusion(syndromeId: 'P017', reason: '卡外硬边界守卫样本'),
              ],
            ),
          ],
          success: true,
        ),
      ], diagnosisContext: '');

      // 阳性对照：excluded 产物确实在（防 findsNothing 空过，假绿①）。
      expect(prompt, contains('"excluded"'));
      expect(prompt, contains('P017'));
      // 反向：excluded 序列化产物里不得出现确认状态机键。
      // ⑦ 鉴别力：excluded 产物里出现 confirmationStatus 是「完全另一个值」，
      // isNot 等值否定有效（缺陷态与守卫值距离非 0）。
      expect(
        prompt,
        isNot(contains('confirmationStatus')),
        reason: 'excluded 不得携带 confirmationStatus（B4：不接 rejected 名册）',
      );
      expect(
        prompt,
        isNot(contains('rejected')),
        reason: 'excluded 元素不得携带 rejected 状态（B4 同名不同义）',
      );
    });
  });

  group('判据 6 · 集外率两源归因（分片级 vs 轮次级，夹具标注）', () {
    test('S1 分片级源：excluded 经 notes 透传到达 merge prompt，不经轮次级候选集复写', () {
      // 设计批 §6 登记风险 1：merge 态 validator 复跑候选集口径与分片当时口径
      // 可能不一致 ⇒ 读数归因必须分源。本测试夹具全部来自分片级源（buildMergePrompt
      // 直接注入 ChunkNote.excluded），与轮次级（批 2 validator 测试）分开计数。
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: 'd',
              evidence: ['e'],
              severity: 'L1',
              excluded: [
                ParsedExclusion(syndromeId: 'P099', reason: '集外样本：注册表外 ID'),
              ],
            ),
          ],
          success: true,
        ),
      ], diagnosisContext: '');

      // 分片级透传原样到达——merge 侧不得重算替换（重算=伪造，设计批 §2.2）。
      expect(
        prompt,
        contains('集外样本：注册表外 ID'),
        reason: '分片级 excluded 原样透传（merge 不重判，不重算）',
      );
      expect(prompt, contains('P099'));
      // 标注：P099 这类「注册表外 ID」若触发 validator 集外 warning，
      // 归因须记为「分片级源」（merge 态复跑口径），不与轮次级基线混淆。
    });
  });
}
