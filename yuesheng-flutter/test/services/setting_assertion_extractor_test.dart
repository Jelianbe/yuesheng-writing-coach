// setting_assertion_extractor_test — 正文提炼断言解析器测试（创建体验 A2）
//
//   1. 标准 JSON 数组 → 断言（pending/ai/chapterSortOrder）
//   2. ```json 围栏 + 前导文本 → 截取解析
//   3. 非 JSON / 缺字段项 → 容错（跳过 + 空数组）
//   4. 空数组 / 全无效 → 空列表
//   5. `N12-F3c` 章号落点：身份必须进 **chapterSortOrder**，旧列 `chapter` 留空
//
// 管线自检组（G8 缺口上半）：`extractFromText` 全链路改由注入 fake LLM 覆盖。
// 此前只测纯函数 `parseExtractedAssertions`，`_llmClient` 那一跳从未被测 ——
// 无 key 时 dio 重试会挂起，测试环境不可控。fake 只 override
// `chatCompletionWithMeta`（基类 `chatCompletionWithContinuation` 已实现并委托它）；
// 不传 finishReason ⇒ 无截断续接副作用。**常驻可跑、不触网。**
//
// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_retry.dart';
import 'package:writingcoach/services/setting_assertion_extractor.dart';

/// Fake LLM：预设响应串，可选抛异常（骨架同 `editor_service_test.dart:35`）。
///
/// **只覆写元数据方法**：`chatCompletionWithContinuation` 是基类实现，
/// 会委托到它；覆写它反而绕过被测链路（续接逻辑就不在路径上了）。
class _FakeLlm extends LlmClient {
  final String _response;
  final Exception? _error;

  _FakeLlm(this._response, {Exception? error}) : _error = error;

  @override
  Future<ChatCompletionResult> chatCompletionWithMeta(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
  }) async {
    if (_error != null) throw _error;
    return ChatCompletionResult(content: _response);
  }
}

void main() {
  test('#1 标准 JSON 数组 → pending/ai 断言', () {
    final result = parseExtractedAssertions(
      '[{"attribute": "身份", "value": "守夜人"},'
      '{"attribute": "武器", "value": "青铜剑"}]',
      chapterIdentity: 3,
    );
    expect(result.length, 2);
    expect(result[0].attribute, '身份');
    expect(result[0].value, '守夜人');
    expect(result[0].status, 'pending');
    expect(result[0].source, 'ai');
  });

  test('#5 章号落**身份载体** `chapterSortOrder`，旧列 `chapter` 留空（`N12-F3c`）', () {
    // 判别性：身份取 7（一个不可能是「展示号直觉值」的数），旧列必须为 null。
    // 若退回旧写法（把身份写进 `chapter`），本用例前两条断言同时转红。
    final result = parseExtractedAssertions(
      '[{"attribute": "身份", "value": "守夜人"}]',
      chapterIdentity: 7,
    );
    expect(result.single.chapterSortOrder, 7, reason: '身份落新载体');
    expect(
      result.single.chapter,
      isNull,
      reason: '旧列装的是「用户原写的数 / AI 标称号」，提炼协议里没有它 ⇒ 不得占用',
    );
  });

  test('#2 围栏 + 前导文本容错', () {
    final result = parseExtractedAssertions(
      '好的，以下是提炼结果：\n```json\n'
      '[{"attribute": "外貌", "value": "银发"}]'
      '\n```',
    );
    expect(result.length, 1);
    expect(result.single.attribute, '外貌');
  });

  test('#3 缺字段项跳过 + 非 JSON 返回空', () {
    expect(
      parseExtractedAssertions('[{"attribute": "身份"}]'),
      isEmpty,
      reason: '缺 value 跳过',
    );
    expect(parseExtractedAssertions('这不是 JSON'), isEmpty);
    expect(parseExtractedAssertions('[]'), isEmpty);
  });

  test('#4 截断 JSON 容错（不抛）', () {
    expect(
      parseExtractedAssertions('[{"attribute": "身份", "value": "守夜人"}'),
      isEmpty,
      reason: '无闭合括号 → 截取失败',
    );
  });

  // ─────────────────────────────────────────────────────────────
  // 管线自检组：真走 `extractFromText`（LLM 那一跳换成注入 fake）
  // ─────────────────────────────────────────────────────────────

  group('extractFromText 管线（注入 fake LLM，无 key 可跑）', () {
    test('P1 正常 JSON 数组 → 条数与全字段保真', () async {
      final extractor = SettingAssertionExtractor(
        _FakeLlm(
          '[{"attribute": "身份", "value": "守夜人"},'
          '{"attribute": "武器", "value": "青铜剑"}]',
        ),
      );

      final result = await extractor.extractFromText(
        entityName: '林晚',
        text: '她是守夜人，持青铜剑。',
        chapterIdentity: 3,
      );

      expect(result.length, 2);
      expect(result[0].attribute, '身份');
      expect(result[0].value, '守夜人');
      expect(result[1].attribute, '武器');
      expect(result[1].value, '青铜剑');
      for (final a in result) {
        expect(a.status, 'pending');
        expect(a.source, 'ai');
        expect(a.chapterSortOrder, 3);
        expect(a.chapter, isNull, reason: '旧列不得被身份占用');
      }
    });

    test('P2 ```json 围栏 + 前导说明文字 → 仍解析出断言', () async {
      final extractor = SettingAssertionExtractor(
        _FakeLlm(
          '好的，以下是提炼结果：\n```json\n'
          '[{"attribute": "外貌", "value": "银发"}]\n```',
        ),
      );

      final result = await extractor.extractFromText(
        entityName: '林晚',
        text: '她有一头银发。',
        chapterIdentity: 5,
      );

      expect(result.length, 1);
      expect(result.single.attribute, '外貌');
      expect(result.single.value, '银发');
      expect(result.single.chapterSortOrder, 5);
    });

    test('P3 完全非 JSON → 空列表且不抛', () async {
      final extractor = SettingAssertionExtractor(_FakeLlm('抱歉，我无法处理。'));

      final result = await extractor.extractFromText(
        entityName: '林晚',
        text: '随便什么正文。',
      );

      expect(result, isEmpty, reason: '解析降级为空，不向调用方抛');
    });

    test('P4 缺字段项被跳过，其余保留', () async {
      final extractor = SettingAssertionExtractor(
        _FakeLlm(
          '[{"attribute": "", "value": "空属性"},'
          '{"attribute": "职业", "value": "医生"},'
          '{"attribute": "武器"}]',
        ),
      );

      final result = await extractor.extractFromText(
        entityName: '林晚',
        text: '她是医生。',
        chapterIdentity: 2,
      );

      expect(result.length, 1, reason: '空 attribute / 缺 value 各跳一条');
      expect(result.single.attribute, '职业');
      expect(result.single.value, '医生');
    });

    test('P5 LLM 抛异常 → extractFromText 向上抛（不吞）', () async {
      final extractor = SettingAssertionExtractor(
        _FakeLlm('', error: Exception('boom')),
      );

      await expectLater(
        extractor.extractFromText(entityName: '林晚', text: '正文'),
        throwsA(isA<Exception>()),
      );
    });

    test('P6 chapterIdentity 为 null → chapterSortOrder 为 null', () async {
      final extractor = SettingAssertionExtractor(
        _FakeLlm('[{"attribute": "身份", "value": "守夜人"}]'),
      );

      final result = await extractor.extractFromText(
        entityName: '林晚',
        text: '她是守夜人。',
      );

      expect(result.single.chapterSortOrder, isNull);
    });
  });
}
