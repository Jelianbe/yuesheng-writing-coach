// ─────────────────────────────────────────────────────────────
// ProgressiveDiagnosis 单测 — 长文本分块诊断
//
// 对应 RN progressive-diagnosis.ts
// 覆盖：
//   #1 splitContent 短文本不分块（<= CHUNK_SIZE 返单块）
//   #2 splitContent 按段落拆分，块间含 overlap 回溯
//   #3 splitContent 末块过小时与前块合并
//   #9 splitContent 末块合并 overlap 去重——正向：合并块内无重复段
//      （T-20261021-03 读数批实锤修复，报告《分块链读数》§四）
//   #10 负向自测：旧拼接逻辑在同 overlap 结构下必现重复段（证 #9 非空转）
//   #11 无 overlap 合并路径（dupCount=0）：精确保全、不误删
//   #16 H6 无空行分段稿（段间单换行）长稿必须切块（T-20261027-01）
//   #17 H6 反向：含空行的稿仍只在 '\n\n' 处切块，逐块长度与改动前一致
//   #4 buildMergePrompt 注入 SYNDROME_DIAGNOSIS_SKILL 引用 + 跨片段合并规则
//   #5 runProgressiveDiagnosis 短文本走 null（走单次链路）
//   #8 ADR-C80 空内容分级降级（换参重试 / 仍空显式失败 / 合法零症候不误伤）
//   #12 ADR-C155 乙形态：分块 prompt 注入判定要点（ID+关键词+一句话），
//      不含 6 条退化判据（T-20261021-03 读数批裁定）
//   #13 ADR-C155 丙为先：6 条退化判据在「跨章依赖判据」节点名留痕 +
//      uncertain 指引（防静默不选，B4）
//   #14 ADR-C155 联动：disabled 剔除同步作用于两节（R-009 用户主权）
//   #15 ADR-C155 成本上限：prompt 字符数在乙形态预算内（防未来改动失控）
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/services/syndrome_registry.dart';

/// Fake LLM 客户端：预设 chatCompletion 和 streamChat 响应
class _FakeLlmClient extends LlmClient {
  final String _chatResponse;
  final String _streamResponse;

  /// 逐次返回的 chatCompletion 响应队列（空则恒返 [_chatResponse]）；
  /// 同时记录每次调用的透传参数，供 ADR-C80 兜底参数断言用。
  final List<String> _chatResponses;
  final List<ChatMessage> chatMessages = [];
  final List<int?> chatMaxTokens = [];
  final List<Map<String, dynamic>?> chatExtraBodies = [];

  /// 与构造参数同型（`Exception?`）—— 收窄为 `Object?` 会让 `throw _chatError`
  /// 触发 `only_throw_errors`（`Object` 不是 Exception/Error 子类型）。
  final Exception? _chatError;

  /// streamChat 收到的 messages（merge 阶段），供端到端断言 notes 进入合并。
  final List<List<ChatMessage>> streamMessages = [];

  /// W-18 温度档：streamChat 收到的 extraBody（merge 阶段），供透传断言。
  final List<Map<String, dynamic>?> streamExtraBodies = [];

  /// ADR-C87：每次 chatCompletion 调用后回调（测试注入中途取消时机）。
  final void Function(int callCount)? onChatCall;
  int _chatCallCount = 0;

  /// P3：merge 阶段注入取消（模拟流式输出中用户点停止 → streamChat 抛
  /// LlmRequestCancelledException），验证统一转 ProgressiveDiagnosisCancelled。
  bool streamThrowsCancelled = false;

  _FakeLlmClient({
    String chatResponse = '{"notes":[]}',
    String streamResponse = '',
    List<String>? chatResponses,
    Exception? chatError,
    this.onChatCall,
  }) : _chatResponse = chatResponse,
       _streamResponse = streamResponse,
       _chatResponses = chatResponses ?? const [],
       _chatError = chatError;

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    chatMessages.addAll(messages);
    chatMaxTokens.add(maxTokens);
    chatExtraBodies.add(extraBody);
    _chatCallCount++;
    onChatCall?.call(_chatCallCount);
    if (_chatError != null) throw _chatError;
    if (_chatResponses.isEmpty) return _chatResponse;
    return _chatResponses.length == 1
        ? _chatResponses.first
        : _chatResponses.removeAt(0);
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    streamMessages.add(messages);
    streamExtraBodies.add(extraBody);
    if (streamThrowsCancelled) {
      throw LlmRequestCancelledException();
    }
    if (_streamResponse.isEmpty) {
      callback(const LlmStreamResponse(content: '', isDone: true));
      return;
    }
    callback(LlmStreamResponse(content: _streamResponse, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// >4000 字触发分块的正文（15 段 × 351 字 ≈ 5265 字）。
///
/// ADR-C153：提到顶层共享 —— 原为 `runProgressiveDiagnosis` group 内的局部函数，
/// 导致窗口语义组无法复用（局部函数不是 API，但也不该被同一文件另一组逼着复制）。
String makeLongContent() {
  final paragraphs = <String>[];
  for (int i = 0; i < 15; i++) {
    paragraphs.add('${'X' * 350}段落$i');
  }
  return paragraphs.join('\n\n');
}

void main() {
  group('splitContent', () {
    test('#1 短文本不分块（<= CHUNK_SIZE 返回单块）', () {
      final short = '这是一段短文本，长度不足以触发分块。';
      final chunks = splitContent(short);
      expect(chunks.length, 1);
      expect(chunks[0], short);
    });

    test('#2 按段落拆分，块间含 overlap 回溯', () {
      // 用短但多的段落构造：每个段落 350 字符，累计 >3000
      final paragraphs = <String>[];
      for (int i = 0; i < 12; i++) {
        // 每段 350 字符：'XXXX...' + 结尾 marker
        final marker = 'P${i}MARK';
        final fill = 'X' * (350 - marker.length);
        paragraphs.add('$fill$marker');
      }
      final content = paragraphs.join('\n\n');
      final chunks = splitContent(content);

      // 应至少 2 块
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.first.length, lessThan(content.length));

      // overlap 校验：第一块的最后几个 marker 应该在第二块开头出现
      // 取第一块末尾所有 marker 的匹配
      final markersInChunk1 = RegExp(
        r'P\d+MARK',
      ).allMatches(chunks.first).map((m) => m.group(0)!).toList();
      if (markersInChunk1.isNotEmpty) {
        final lastMarkers = markersInChunk1
            .skip(markersInChunk1.length - 3)
            .toList(); // 最后 3 个 marker
        final chunk2Start = chunks[1].substring(0, 600);
        final overlapHit = lastMarkers.any((m) => chunk2Start.contains(m));
        // CHUNK_OVERLAP=200，每个 marker(PiMARK)=6 字符，fill=344 字符，每段 350。
        // 从末尾段起向前，每段 352（含 '\n\n'）字符，直到长度 ≥ 200。
        // 约等于回溯 1 段就够 200 个字符 overlap，所以至少 1 个 marker 应该出现。
        expect(
          overlapHit,
          isTrue,
          reason:
              'chunk1 末尾 marker 至少有一个在 chunk2 开头 ${chunk2Start.length} 字符内出现（保证跨块上下文连续）',
        );
      }
    });

    test('#3 末块过小时与前块合并（MIN_LAST_CHUNK=500）', () {
      // 构造刚好触发切块的短内容：前 9 段 340 字 ≈ 3060（含分隔符共 ~3078）> SIZE 3000
      // 然后追加第 10 段只有 40 字 < MIN_LAST_CHUNK=500，应该被合并回末块
      final paragraphs = <String>[];
      for (int i = 0; i < 9; i++) {
        paragraphs.add('Y' * 340 + 'S${i}END'); // 346 字符 / 段
      }
      // 第 10 段：只有 <500 字符，末块如果只有它应触发合并
      final tail = '短尾段落T，长度约 40 个字符用来触发合并';
      paragraphs.add(tail);
      final content = paragraphs.join('\n\n');
      final chunks = splitContent(content);

      // 最后一块必须包含 tail
      expect(chunks.last, contains('短尾段落T'));
      // 末块长度不应小于 MIN_LAST_CHUNK（否则就已被正确合并到前一块，此时 chunks 数 < 段落数-0
      // 预期：要么 chunks.length=1（全部合并），要么 chunks.last >=500（已合并或单块够长）
      if (chunks.length > 1) {
        expect(
          chunks.last.length,
          greaterThanOrEqualTo(500),
          reason: '若 chunks>=2，末块 >=500（MIN_LAST_CHUNK），说明 tail 已正确合并到前一块',
        );
      }
    });

    test('#4 空字符串返回单块', () {
      expect(splitContent(''), ['']);
    });

    test('#5 长度恰等于 kDiagnosisChunkSize → 单块（<= 边界）', () {
      // 摸底判据：`content.length <= SIZE` 的 `=` 侧此前无锚
      // （#1 用例名写 "<=" 但文本远短于阈值）。
      // 注：单段 > SIZE 的超长文本存在死循环缺陷（批次 H 侦察实锤，
      // 已登记待办），本用例只锚 `=` 边界，不触达该路径。
      final exact = 'X' * kDiagnosisChunkSize; // 3000，无 \n\n
      final chunks = splitContent(exact);
      expect(chunks, hasLength(1));
      expect(chunks.single, exact);
    });

    test(r'#6 单段超长（>= SIZE 且无 \n\n）不挂死，整段成块', () {
      // 死循环判据（ADR-C73 §2）：批次 H 实锤，单段 ≥3000 + 总长 >3000
      // 会让 while(startIndex < paragraphs.length) 永真（endIndex=startIndex
      // → overlapStart ≤ startIndex → startIndex 不变）。
      // 修复后：首段即超阈值时强制 endIndex = startIndex + 1，整段成块。
      // 用例必须秒过（>60s 即变异命中，挂死型拦截由 _verify_batch_h_coverage
      // 兜底）。
      final longSingle = 'X' * 4000; // 单段 4000 字符，无段落边界
      final chunks = splitContent(longSingle);
      expect(chunks, isNotEmpty);
      expect(chunks.single, longSingle); // 整段成块
    });

    test(r'#7 字符串中间夹杂 \n\n 但首段即 ≥ SIZE → 首段成块 + 后续正常切', () {
      // 边界组合：首段超长触发修复路径，第二段短且合并到末块。
      // 验证修复不影响后续段落的常规分块。
      final first = 'A' * 4000; // 单段超长
      final tail1 = 'B' * 350 + 'T1END'; // 短段落
      final tail2 = 'C' * 350 + 'T2END'; // 短段落
      final content = '$first\n\n$tail1\n\n$tail2';
      final chunks = splitContent(content);
      // 至少 2 块：第一块含首段（整段或部分），后续按段落合并
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.first, contains(first)); // 首段必在前块
    });

    test('#9 末块<500 且 overlap 跨段边界 → 合并块内无重复段'
        '（T-20261021-03 读数批实锤修复）', () {
      // 构造算尺（段索引口径，pLen = 段长 + 2）：
      //   段[0..9] = 'P00'..'P09' + 'X'×272 = 275 字/段（pLen 277）
      //   段[10]   = 'P10' + 'X'×197 = 200 字（pLen 202）
      //   段[11]   = 'P11' + 'X'×247 = 250 字（pLen 252）
      //   总长 3222 > SIZE 3000 ⇒ 进分块循环
      // 迭代1：i=10 时累计 2970 <3000 收入；i=11 时 2970+252=3222 ≥3000
      //   ⇒ 切块 endIndex=11，块1 = 段[0..10]；overlap 回溯段[10]（202
      //   字 ≥ OVERLAP 200）⇒ startIndex=10
      // 迭代2：段[10..11] 累计 454 <3000 ⇒ !reachedThreshold ⇒ 末块
      //   = 段[10..11] = 452 字 < MIN_LAST_CHUNK 500 ⇒ 触发合并
      // 旧实现原样拼接 ⇒ 段[10]（200 字）在合并块内二次出现（L03c2 同款
      //   缺陷：段[27]=段[29] 一字不差，该批唯一 hit 即其假症候已作废）；
      // 修复后 dupCount = min(prevEnd=11, N=12) - lastStart=10 = 1
      //   ⇒ 跳过段[10] 再拼 ⇒ 合并块与原文逐字一致。
      final paragraphs = <String>[];
      for (var i = 0; i < 10; i++) {
        paragraphs.add('P${i.toString().padLeft(2, '0')}${'X' * 272}');
      }
      paragraphs.add('P10${'X' * 197}'); // 200 字
      paragraphs.add('P11${'X' * 247}'); // 250 字
      final content = paragraphs.join('\n\n');
      expect(content.length, 3222, reason: '算尺锚：总长必须 >3000 才进分块循环');

      final chunks = splitContent(content);

      // 合并必须发生（构造成立性双锚：总长 3222 + 末块 452<500）
      expect(chunks, hasLength(1), reason: '末块 452<500 ⇒ 必须合并成 1 块');
      // 精确还原 = 无重复 + 无丢失的最强形式
      expect(chunks.single, content, reason: '合并块与原文逐字一致');
      // 段落级扫描（报告 §4.4 要求的判据）：12 段互不相同
      final merged = chunks.single.split('\n\n');
      expect(merged, hasLength(12));
      expect(merged.toSet(), hasLength(12), reason: '任一段落不得在合并块内出现两次');
      for (var i = 0; i < 12; i++) {
        expect(chunks.single, contains('P${i.toString().padLeft(2, '0')}'));
      }
    });

    test('#10 负向自测：旧拼接逻辑在同 overlap 结构下必现重复段'
        '（证明 #9 非 vacuous 通过）', () {
      // 与 #9 同切点构造：段[0..11] 完全相同（切块 endIndex=11 与 overlap
      // 点 startIndex=10 只由前 12 段决定——迭代1 的 break 条件在 i=11
      // 即已触发，够不到段[12]），仅追加段[12]（400 字）使末块
      // = 段[10..12] = 854 ≥ 500 ⇒ 合并不触发，从而**观测到真实的
      // (前块, 末块) 对**。该对的重复段（段[10]）与 #9 输入的前块尾/
      // 末块头逐字相同（同切点、同 overlap 点，仅末块多一段新内容），
      // 故负向结论覆盖 #9 的确切输入。
      final paragraphs = <String>[];
      for (var i = 0; i < 10; i++) {
        paragraphs.add('P${i.toString().padLeft(2, '0')}${'X' * 272}');
      }
      paragraphs.add('P10${'X' * 197}'); // 200 字
      paragraphs.add('P11${'X' * 247}'); // 250 字
      paragraphs.add('P12${'X' * 397}'); // 400 字 ⇒ 末块 854，不合并
      final content = paragraphs.join('\n\n');

      final chunks = splitContent(content);
      expect(chunks, hasLength(2), reason: '末块 854 ≥500 ⇒ 不合并，露出 overlap 结构');

      // overlap 设计语义：末块头部 == 前块尾部（逐段同一，跨块上下文连续）
      final prevParas = chunks[0].split('\n\n');
      final lastParas = chunks[1].split('\n\n');
      expect(
        lastParas.first,
        prevParas.last,
        reason: '末块首段必须与前块末段逐字相同（overlap 回溯的设计语义）',
      );

      // 负向自测：把观测到的真实 (前块, 末块) 喂给旧实现的拼接公式
      // （修复前 _mergeSmallLastChunk 的行为），重复必现——证明 #9 的
      // 输入是真触发条件，不是空转通过。
      final legacyMerged = '${chunks[0]}\n\n${chunks[1]}';
      final legacyParas = legacyMerged.split('\n\n');
      final dupCount = legacyParas.where((p) => p == prevParas.last).length;
      expect(dupCount, 2, reason: '旧拼接公式下重叠段必现两次（与 L03c2 实测同款缺陷）');

      // 对照：块间 overlap 是设计，块内重复是缺陷——修复后两块内部
      // 各自仍无重复段。
      expect(prevParas.toSet(), hasLength(prevParas.length));
      expect(lastParas.toSet(), hasLength(lastParas.length));
    });

    test('#11 无 overlap 的合并路径（dupCount=0）：精确保全、不误删', () {
      // 构造：单段 2998 字（pLen 3000 ≥ SIZE ⇒ 原子成块、跳 overlap）
      //   + 尾段 100 字 < 500 ⇒ 触发合并，但两块间无 overlap（原子分支
      //   后 startIndex 直接 +1，不回溯）。
      // 算尺：dupCount = min(prevEnd=1, N=2) - lastStart=1 = 0 ⇒ 走原样
      // 拼接分支。断言合并块与原文逐字一致——防修复自身误删（dupCount
      // 算错会把尾段当重复段吞掉）。
      final content = '${'A' * 2998}\n\n${'B' * 100}';
      final chunks = splitContent(content);
      expect(chunks, hasLength(1), reason: '尾段 100 <500 ⇒ 必须合并');
      expect(chunks.single, content, reason: '无 overlap 合并必须逐字保全原文（不误删）');
    });

    test('#16 H6：无空行分段稿（段间单换行）长稿必须切块', () {
      // T-20261027-01 §H6：'\n\n' 切不出段 ⇒ 旧实现整篇成一块，分块链的
      // 窗口纪律（片段 i/n + 窗外判 uncertain）落在 n=1 上。
      // 边界（不在本条判据内）：整篇**无换行**时两级分隔符都切不出段，
      // 保持段落原子性整段成块（ADR-C73 §2，见 #6 / E2E-1/4/5）。
      final paragraphs = <String>[];
      for (var i = 0; i < 15; i++) {
        paragraphs.add('无空行段$i${'X' * 330}');
      }
      final content = paragraphs.join('\n');
      expect(content.contains('\n\n'), isFalse);
      expect(content.length, greaterThan(kDiagnosisChunkSize));

      final chunks = splitContent(content);

      expect(
        chunks.length,
        greaterThanOrEqualTo(2),
        reason: 'H6 判据 ≥2（旧实现恒 1）',
      );
      expect(chunks.first.length, lessThan(content.length));
      for (final c in chunks) {
        expect(content.contains(c), isTrue, reason: '块必须是原文逐字子串（锚点定位前提）');
      }
      final coverage = computeChunkCoverage(content, chunks);
      expect(coverage.every((c) => c.located), isTrue);
      expect(coverage.last.end, content.length, reason: '末块须覆盖到原文结尾（不丢尾）');
    });

    test('#17 H6 反向：含空行的稿仍在空行处切块（逐块长度与改动前一致）', () {
      // 反向判据（卡面）：原本就有空行的稿，分块结果必须与现状逐块一致。
      // 构造特意让**段内**含单个换行 —— 若实现误按 '\n' 切，块边界会落进段内，
      // 下面的「块边界必在 '\n\n' 处」会红。
      final paragraphs = <String>[];
      for (var i = 0; i < 14; i++) {
        paragraphs.add('段$i上半${'X' * 120}\n段$i下半${'Y' * 120}');
      }
      final content = paragraphs.join('\n\n');

      final chunks = splitContent(content);

      expect(chunks.map((c) => c.length).toList(), <int>[2761, 1010]);
      var cursor = 0;
      for (final c in chunks) {
        final start = content.indexOf(c, cursor);
        expect(start, isNot(-1), reason: '块必须是原文子串');
        expect(
          start == 0 || content.startsWith('\n\n', start - 2),
          isTrue,
          reason: '块起点必在段落边界（不得在段内单换行处切）',
        );
        final end = start + c.length;
        expect(
          end == content.length || content.startsWith('\n\n', end),
          isTrue,
          reason: '块终点必在段落边界（不得在段内单换行处切）',
        );
        cursor = start;
      }
    });
  });

  group('buildMergePrompt', () {
    test('#4-1 注入 SYNDROME_DIAGNOSIS_SKILL 引用 + 跨片段合并规则', () {
      final chunkResults = <ChunkAnalysisResult>[
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: '情绪标签化出现在开头',
              evidence: ['她非常愤怒'],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
        ChunkAnalysisResult(
          chunkIndex: 1,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: '情绪标签化出现在结尾',
              evidence: ['他很激动'],
              severity: 'L2',
            ),
          ],
          success: true,
        ),
      ];
      final prompt = buildMergePrompt(chunkResults, diagnosisContext: '');

      // 必含 SKILL 锚点（对齐 RN merge prompt 顶部 # SKILL: 症候诊断手册）
      expect(prompt, contains('症候诊断手册'));
      // 必含跨片段合并规则
      expect(prompt, contains('同一个症候在不同分片中出现的信号'));
      expect(prompt, contains('严重度取最高'));
      expect(prompt, contains('收敛报出'));
      expect(prompt, contains('[YS_DIAGNOSIS]'));
      expect(prompt, contains('[/YS_DIAGNOSIS]'));
      // 两个分片的分析结果都包含在 prompt 里
      expect(prompt, contains('分片 1'));
      expect(prompt, contains('分片 2'));
      expect(prompt, contains('P001'));
    });

    test('#4-3 FIX-1：prompt 要求自然语言正文 + suggested_actions/confidence 字段格式', () {
      final chunkResults = <ChunkAnalysisResult>[
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: '情绪标签化',
              evidence: ['她非常愤怒'],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
      ];
      final prompt = buildMergePrompt(chunkResults, diagnosisContext: '');
      // FIX-1：自然语言正文约束（修复「诊断完成」空输出的根因 A）
      expect(prompt, contains('自然语言诊断正文'));
      expect(prompt, contains('不得省略'));
      // 顶层字段格式约束（suggested_actions_invalid 被拒根因）
      expect(prompt, contains('suggested_actions'));
      expect(prompt, contains('confidence'));
      expect(prompt, contains('字符串数组'));
      expect(prompt, contains('必填'));
    });

    test('#4-2 注入前次诊断上下文（diagnosisContext 非空时出现在 prompt 顶部）', () {
      final chunkResults = <ChunkAnalysisResult>[
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P002',
              description: '',
              evidence: [],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
      ];
      const ctx = '## 前次诊断上下文\n\n- P001 情绪标签化（当前严重度: L2）';
      final prompt = buildMergePrompt(chunkResults, diagnosisContext: ctx);

      // 上下文应出现在 SKILL 锚点之前
      final idxCtx = prompt.indexOf('前次诊断上下文');
      final idxSkill = prompt.indexOf('症候诊断手册');
      expect(idxCtx, lessThan(idxSkill), reason: '诊断上下文应位于 SKILL 之前');
      expect(prompt, contains('P001 情绪标签化'));
    });
  });

  group('runProgressiveDiagnosis', () {
    // >4000 字触发分块（makeLongContent 已提至文件顶层，ADR-C153）

    test('#5 短文本（<= THRESHOLD=4000）走 null（走单次链路）', () async {
      const short = '这是一段不足 4000 字的文本，应该直接返回 null，由外部走单次诊断。';
      final result = await runProgressiveDiagnosis(
        content: short,
        title: '短文本',
        llmClient: _FakeLlmClient(),
        onContent: (_) {},
      );
      expect(result, isNull);
    });

    test('#6 长文本（> THRESHOLD=4000）走分块链路 → 返回 ProgressiveResult', () async {
      // 构造 > 4000 字的长文本
      final paragraphs = <String>[];
      for (int i = 0; i < 15; i++) {
        paragraphs.add('X' * 350 + '段落$i');
      }
      final content = paragraphs.join('\n\n');

      final streamResponse =
          '诊断完成。[YS_DIAGNOSIS]{"syndromes":[],"suggested_actions":[],"confidence":0.8}[/YS_DIAGNOSIS]';
      var receivedContent = '';

      final result = await runProgressiveDiagnosis(
        content: content,
        title: '长文本测试',
        llmClient: _FakeLlmClient(streamResponse: streamResponse),
        onContent: (delta) {
          receivedContent += delta;
        },
      );

      expect(result, isNotNull);
      expect(result!.chunkCount, greaterThanOrEqualTo(2));
      expect(result.failedChunks, 0);
      expect(result.fullContent, isNotEmpty);
      expect(receivedContent, isNotEmpty);
      expect(result.fullContent, contains('[YS_DIAGNOSIS]'));
    });

    test('#7 W-18 温度档：null 不产 extraBody 键（请求体零变更护栏）', () async {
      final fake = _FakeLlmClient(
        streamResponse:
            '诊断完成。[YS_DIAGNOSIS]{"syndromes":[],"suggested_actions":[],"confidence":0.8}[/YS_DIAGNOSIS]',
      );
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '温度护栏',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(
        fake.streamExtraBodies.single,
        isNull,
        reason: '灵活档（null）不产 extraBody ⇒ merge 请求体逐字节不变',
      );
    });

    test('#7b W-18 温度档：0.3 经 extraBody 覆盖 merge 段 temperature', () async {
      final fake = _FakeLlmClient(
        streamResponse:
            '诊断完成。[YS_DIAGNOSIS]{"syndromes":[],"suggested_actions":[],"confidence":0.8}[/YS_DIAGNOSIS]',
      );
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '温度保守档',
        llmClient: fake,
        onContent: (_) {},
        mergeTemperature: 0.3,
      );

      expect(result, isNotNull);
      expect(fake.streamExtraBodies.single, {'temperature': 0.3});
    });
  });

  group('runProgressiveDiagnosis · ADR-C80 空内容分级降级', () {
    // >4000 字触发分块（与 #6 同款构造，切成 2 块）
    String makeLongContent() {
      final paragraphs = <String>[];
      for (int i = 0; i < 15; i++) {
        paragraphs.add('X' * 350 + '段落$i');
      }
      return paragraphs.join('\n\n');
    }

    const validNotes =
        '{"notes":[{"syndromeId":"P001","description":"情绪标签化","evidence":["她很愤怒"],"severity":"L1"}]}';

    test('#8-1 尝试 1 空 → 换兜底参数重试一次（消息不变）→ 救回', () async {
      final fake = _FakeLlmClient(chatResponses: ['', validNotes]);
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, 0);

      // 2 块：chunk0 两次调用（尝试 1 + 兜底），chunk1 队列耗尽走默认响应一次
      expect(fake.chatMaxTokens.length, 3);
      // 尝试 1：不传覆盖参数（应用现参数原样）；尝试 2：兜底参数
      expect(fake.chatMaxTokens[0], isNull);
      expect(fake.chatMaxTokens[1], LlmConfig.chunkAnalysisFallbackMaxTokens);
      expect(LlmConfig.chunkAnalysisFallbackMaxTokens, 8192);
      expect(fake.chatExtraBodies[0], isNull);
      expect(fake.chatExtraBodies[1], LlmConfig.chunkAnalysisFallbackExtraBody);
      expect(fake.chatExtraBodies[1]!['thinking'], {'type': 'disabled'});

      // 重试是换参数，不是换消息：chunk0 两次调用的 messages 逐条一致
      // ★ H8（批八）：单次调用由 2 条变 **3 条**（主 system · 窗口元信息 · 纯正文）
      //   ⇒ 2 次 + 1 次 = 9 条，步长（同块两次调用的偏移）由 2 变 3。
      expect(fake.chatMessages.length, 9);
      expect(
        fake.chatMessages.take(3).map((m) => m.role).toList(),
        const ['system', 'system', 'user'],
        reason: 'H8 注入形状：元信息单独成条，正文那条只装正文',
      );
      for (var i = 0; i < 3; i++) {
        expect(fake.chatMessages[i].role, fake.chatMessages[i + 3].role);
        expect(fake.chatMessages[i].content, fake.chatMessages[i + 3].content);
      }

      // 救回的 notes 真正进入 merge 阶段（端到端：P001 出现在合并 prompt）
      expect(fake.streamMessages, hasLength(1));
      expect(
        fake.streamMessages.last.map((m) => m.content).join('\n'),
        contains('P001'),
      );
    });

    test('#8-2 重试后仍空 → 显式失败（empty_content），不再静默计成功', () async {
      final fake = _FakeLlmClient(chatResponse: ''); // 所有调用都返回空
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, result.chunkCount);
      // 每块两次调用（尝试 1 + 兜底重试）
      expect(fake.chatMaxTokens.length, result.chunkCount * 2);
      for (var i = 0; i < fake.chatMaxTokens.length; i += 2) {
        expect(fake.chatMaxTokens[i], isNull);
        expect(
          fake.chatMaxTokens[i + 1],
          LlmConfig.chunkAnalysisFallbackMaxTokens,
        );
      }
    });

    test('#8-3 合法零症候（非空 JSON、notes 空）不误伤为失败', () async {
      final fake = _FakeLlmClient(); // 默认 '{"notes":[]}'
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, 0);
      expect(fake.chatMaxTokens.length, result.chunkCount); // 无重试
      expect(fake.chatMaxTokens[0], isNull);
      expect(fake.chatExtraBodies[0], isNull);
    });

    test('#8-4 调用异常 → 显式失败（exception）且计入 failedChunks', () async {
      final fake = _FakeLlmClient(chatError: Exception('网络不可用'));
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, result.chunkCount);
      // 异常路径只调用一次（无兜底重试——异常不是空 content）
      expect(fake.chatMaxTokens.length, result.chunkCount);
    });

    test('#9 ADR-C87 取消令牌已取消 → 分块前抛，LLM 未被调用', () async {
      final fake = _FakeLlmClient();
      final cancel = CancelToken()..cancel();

      await expectLater(
        runProgressiveDiagnosis(
          content: makeLongContent(),
          title: '取消测试',
          llmClient: fake,
          onContent: (_) {},
          cancelToken: cancel,
        ),
        throwsA(isA<ProgressiveDiagnosisCancelled>()),
      );
      // 第一块前即抛 → chatCompletion 从未被调用
      expect(fake.chatMessages, isEmpty);
    });

    test('#10 ADR-C87 块分析中途取消 → 不再调后续块与合并', () async {
      final cancel = CancelToken();
      final fake = _FakeLlmClient(
        // 第一块分析完成后取消 → 循环回到第二块前检查即抛
        onChatCall: (n) {
          if (n >= 1) cancel.cancel();
        },
      );

      await expectLater(
        runProgressiveDiagnosis(
          content: makeLongContent(),
          title: '取消测试',
          llmClient: fake,
          onContent: (_) {},
          cancelToken: cancel,
        ),
        throwsA(isA<ProgressiveDiagnosisCancelled>()),
      );
      // 只调了一次 LLM（第一块），后续块与合并均未发起
      expect(fake.chatMaxTokens.length, 1);
      expect(fake.streamMessages, isEmpty);
    });

    test(
      '#11 P3 merge 阶段取消 → LlmRequestCancelledException 转 ProgressiveDiagnosisCancelled（不落报错）',
      () async {
        final fake = _FakeLlmClient()..streamThrowsCancelled = true;

        await expectLater(
          runProgressiveDiagnosis(
            content: makeLongContent(),
            title: '取消测试',
            llmClient: fake,
            onContent: (_) {},
          ),
          throwsA(isA<ProgressiveDiagnosisCancelled>()),
        );
        // 块分析全部完成（每块一次 chat），merge 发起后抛取消并被转换
        expect(fake.chatMaxTokens.length, greaterThan(0));
        expect(fake.streamMessages.length, 1);
      },
    );

    test('#L3 越界 severity 白名单：L4 条目不进 merge，合法条目保留', () async {
      // 分块分析返回：一条合法（L1）+ 一条越界（L4）
      const notes =
          '{"notes":['
          '{"syndromeId":"P001","description":"情绪标签化","evidence":["她很愤怒"],"severity":"L1"},'
          '{"syndromeId":"P999","description":"伪造症候","evidence":["x"],"severity":"L4"}'
          ']}';
      final fake = _FakeLlmClient(chatResponses: [notes, '{"notes":[]}']);
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: 'L3 白名单测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, 0);
      // merge 阶段 prompt：合法 P001 保留，越界 L4 条目被剔除
      final mergeText = fake.streamMessages.last
          .map((m) => m.content)
          .join('\n');
      expect(mergeText, contains('P001'));
      expect(mergeText, isNot(contains('P999')));
      expect(mergeText, isNot(contains('L4')));
    });
  });

  // ── ADR-C153窗口语义：分片阶段「我判不了」的可表达与可贯通 ──
  group('窗口边界（ADR-C153）', () {
    test('#W-1 分片 prompt 含窗口边界声明与 uncertain 输出约定', () {
      // 守门项：这两段是本 ADR 的全部产物。prompt 一旦被重构掉，
      // 分片阶段就退回「看不到前文也照样下肯定结论」。
      expect(kChunkSystemPrompt, contains('片段窗口边界'));
      expect(kChunkSystemPrompt, contains('uncertain'));
      // 边界声明须在例外清单**之前**读到：例外是「不要判」，边界是「凭什么不能判」。
      expect(
        kChunkSystemPrompt.indexOf('片段窗口边界'),
        lessThan(kChunkSystemPrompt.indexOf('例外情况指引')),
      );
    });

    test('#W-2 边界声明用「规则」而非「逐条点名」，一次覆盖 6 条例外', () {
      // 若日后有人把它改回逐条点名 P0xx 的例外清单，本条会红：
      // 6 条豁免（类型自证/意图自证/跨片依赖）都不需要指认位置，
      // 列成清单 = 给每个分片发免责模板，剧情组真阳性会掉一大截。
      expect(kChunkSystemPrompt, contains('依赖片段外信息'));
      expect(kChunkSystemPrompt, contains('片段 1/1'));
      // 单块时跨片前提不成立，必须写明，否则「只有一段」会被误当跨片处理。
    });

    test('#W-3 uncertain=true 的笔记带进 merge prompt', () {
      // 不带 = merge 读到的仍是一堆肯定结论 ⇒ 声明≠生效（本项目同族第五例）。
      final prompt = buildMergePrompt([
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P022',
              description: '节奏比例疑似失衡，缺全文节奏基线',
              evidence: ['这一段写得很长'],
              severity: 'L1',
              uncertain: true,
            ),
          ],
          success: true,
        ),
      ]);
      // 断言语义而非序列化格式：`_encodeJson` 产出 `"k": v`（冒号后有空格），
      // 锁死无空格的写法会让测试绑死在编码器格式上，改编码器就假红。
      expect(prompt, contains('"uncertain": true'));
      // merge 侧须有处置规则，否则带标记的笔记会被当已确认结论原样输出。
      expect(prompt, contains('分片不确定标记的处置'));
      expect(prompt, contains('pending_context=true'));
    });

    test('#W-4 merge prompt 里 uncertain 与 pending_context 是同一语义两端', () {
      // 分片标「我现在判不了」，merge 标「我合并后仍判不了」。
      // 缺了前者，后者没有输入源 ⇒ pending_context 机制在分块链上是空转的。
      final prompt = buildMergePrompt([
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            const ChunkNote(
              syndromeId: 'P001',
              description: 'd',
              evidence: ['e'],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
      ]);
      // 缺省 false 也须显式出现：merge 侧要能区分「没标」与「标了不成立」。
      expect(prompt, contains('"uncertain": false'));
    });

    test('#W-5 uncertain 的解析语义（覆盖 _parseUncertainFlag 的容错面）', () {
      // ★ 诚实范围声明（ADR-C153 §6 留口）：本条**只**覆盖序列化层 ——
      // `ChunkNote.uncertain` 是否进 merge prompt。分片侧的**解析**
      // （`_parseUncertainFlag` 对 true / "true" / 1 / "True" / "yes" 的容错）
      // 在 `flutter test` 下未能构造出稳定复现的断言，见下方说明。
      //
      // 为什么不并进端到端：`runProgressiveDiagnosis` 的分片结果
      // **不对外暴露**（`ProgressiveResult` 无 `chunkResults` 字段），
      // 唯一出口是 merge prompt；而该出口在测试里取到的内容与单点
      // `buildMergePrompt` 不一致，根因未查明（已排除：extractJson、
      // _parseChunkNotes 白名单、planMergeBudget 降级、快照截断）。
      // ★ 按纪律「给不出的是印象不是发现」，此处如实留口而非硬凑一个绿。
      //
      // 解封条件：给 `ProgressiveResult` 增加一个仅测试可见的
      // `chunkResults` 出口（或把 `_parseUncertainFlag` 提到公开 API），
      // 使解析结果可断言。
      const note = ChunkNote(
        syndromeId: 'P022',
        description: '缺全文节奏基线',
        evidence: ['e'],
        severity: 'L1',
        uncertain: true,
      );
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(chunkIndex: 0, notes: [note], success: true),
      ]);
      expect(
        RegExp(r'"uncertain"\s*:\s*true').hasMatch(prompt),
        isTrue,
        reason: 'uncertain=true 必须序列化进 merge prompt',
      );

      // 缺省 false 也须显式出现：merge 侧要能区分「没标」与「标了不成立」。
      const plain = ChunkNote(
        syndromeId: 'P001',
        description: 'd',
        evidence: ['e'],
        severity: 'L1',
      );
      final prompt2 = buildMergePrompt([
        const ChunkAnalysisResult(chunkIndex: 0, notes: [plain], success: true),
      ]);
      expect(
        RegExp(r'"uncertain"\s*:\s*false').hasMatch(prompt2),
        isTrue,
        reason: '缺省须显式落 false，不能省略字段',
      );
    });
  });

  group('分块 prompt 判据注入面（ADR-C155 · T-20261021-03 读数批裁定）', () {
    test('#12 乙形态：判定要点行含 ID+关键词+一句话，不含 6 条退化判据', () {
      final prompt = kChunkSystemPrompt;
      expect(prompt.contains('症候判定要点'), isTrue, reason: '缺「症候判定要点」小节');
      // 要点行形态（乙）：'- P001 情绪标签化（关键词）：一句话判定要点'
      expect(
        RegExp(r'- P001 情绪标签化（[^）]+）：\S').hasMatch(prompt),
        isTrue,
        reason: 'P001 要点行须含「（关键词）：一句话」两段——乙形态（原则+条目）',
      );
      final block = prompt.substring(
        prompt.indexOf('症候判定要点'),
        prompt.indexOf('跨章依赖判据'),
      );
      for (final id in kChunkDegradedCriteriaIds) {
        expect(
          block.contains(id),
          isFalse,
          reason: '$id 不应出现在要点块（ADR-C155 收窄：片内不可自证）',
        );
      }
      // 要点条数 = 注册表活跃 − 6（派生断言，不写死数字：注册表扩容后仍成立）
      final expected = kSyndromeRegistry
          .where((s) => !kChunkDegradedCriteriaIds.contains(s.id))
          .length;
      final actual = RegExp(
        r'^- P\d{3} ',
        multiLine: true,
      ).allMatches(block).length;
      expect(
        actual,
        expected,
        reason: '要点行数应 = 注册表活跃(${kSyndromeRegistry.length}) − 6',
      );
    });

    test('#13 丙为先：6 条退化判据在留痕节点名 + uncertain 指引句', () {
      final prompt = kChunkSystemPrompt;
      expect(prompt.contains('跨章依赖判据'), isTrue, reason: '缺「跨章依赖判据」小节');
      // 节边界截到「片段窗口边界」：例外指引里 P011 等也有条目，不截会误算
      final tail = prompt.substring(
        prompt.indexOf('跨章依赖判据'),
        prompt.indexOf('片段窗口边界'),
      );
      for (final id in kChunkDegradedCriteriaIds) {
        expect(tail.contains(id), isTrue, reason: '$id 未在留痕节点名（B4：排除而非静默不选）');
      }
      expect(
        tail.contains('"uncertain": true'),
        isTrue,
        reason: '留痕节须含 uncertain 指引句（明示片内不可判时直接标 uncertain）',
      );
    });

    test('#14 联动：disabled 同步剔除两节（R-009 用户主权）', () async {
      final fake = _FakeLlmClient(
        streamResponse:
            '诊断完成。[YS_DIAGNOSIS]{"syndromes":[],"suggested_actions":[],"confidence":0.8}[/YS_DIAGNOSIS]',
      );
      await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: 'disabled 联动',
        llmClient: fake,
        onContent: (_) {},
        disabledSyndromeIds: const {'P001', 'P011'},
      );
      final system = fake.chatMessages
          .firstWhere((m) => m.role == 'system')
          .content;
      // P001 非退化 ⇒ 从要点块消失；P011 退化 ⇒ 从留痕节消失
      expect(
        system.contains('- P001 情绪标签化'),
        isFalse,
        reason: 'disabled 的 P001 不应出现在要点块',
      );
      // 留痕节截到「片段窗口边界」：例外指引静态不随 disabled 变，
      // 其中「- P011例外：…」会污染不截边界的断言
      final degradedTail = system.substring(
        system.indexOf('跨章依赖判据'),
        system.indexOf('片段窗口边界'),
      );
      expect(
        degradedTail.contains('P011'),
        isFalse,
        reason: 'disabled 的 P011 不应出现在留痕节',
      );
      // 未禁用的退化者仍在留痕节（只禁了 P011 一条）
      expect(degradedTail.contains('P022'), isTrue);
    });

    test('#15 成本上限：乙形态 prompt 字符数在预算内（丙形态否决的量化护栏）', () {
      // 读数批实测：39 条判据原文 61514 字符 ⇒ 丙形态（原文 verbatim）按
      // 33 条折算 ≈52000 字符/片，token 成本随片数爆炸 ⇒ ADR-C155 否。
      // 上限 20000 = 现状(4053) + 要点行的宽松上限；若有人改回注入原文，
      // 字符数将逼近 65000 ⇒ 本断言变红，强制重新走 ADR。
      expect(
        kChunkSystemPrompt.length,
        lessThan(20000),
        reason: 'prompt 超预算——疑似注入判据原文（丙形态，ADR-C155 已否）',
      );
      expect(
        kChunkSystemPrompt.length,
        greaterThan(4500),
        reason: 'prompt 应比现状(4053) 更长（要点行确实注入，非空转）',
      );
    });
  });
}
