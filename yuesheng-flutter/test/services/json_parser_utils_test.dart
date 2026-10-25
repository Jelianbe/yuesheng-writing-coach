// ─────────────────────────────────────────────────────────────
// json_parser_utils_test — C-3 批：JSON 解析容错工具
//
// 覆盖对象：lib/services/json_parser_utils.dart（54 行，0 覆盖）
//   公开符号：parseJsonLenient（2 分支：容错 / rethrow）· stripMarkdownFence（围栏剥离）
//
// ★ 本文件只补 C-1 裁定（.ai/research/t13-c1-test-triage.md §⑨）点名的缺口：
//   · parseJsonLenient 的**中文引号容错路径**（:25）—— 从未被走过（test/ 全树零命中）。
//   · stripMarkdownFence 的**围栏剥离路径**（:38-52）—— 从未被走过。
//   · parseJsonLenient 的 rethrow 路径（:28）—— 已被 editor_service_test.dart:385 间接覆盖
//     ⇒ 本文件补的是**异常类型**那一维（原用例只断言「结果为 null」）。
//
// ★ 可红判据（改哪一处必红）：
//   ① 删 lib/services/json_parser_utils.dart:25 的
//      .replaceAll('\u201C','"').replaceAll('\u201D','"')
//      ⇒ 用例 #A1 必红（jsonDecode 抛异常）。
//   ② 把 :26-28 的「无可替换 ⇒ rethrow」改成 `return null`
//      ⇒ 用例 #A2（异常类型）/ #A3（部分替换后仍失败）必红。
//   ③ 删 :38-46 的围栏剥离块 ⇒ 用例 #B1/#B2/#B3 必红（输出仍含 ``` ）。
//   ④ 删 :49-52 的尾部围栏剥离 ⇒ 用例 #B1 与 #B4 必红。
//   ⑤ 把 :38 的正则改成贪婪匹配到串尾 ⇒ 用例 #B4 必红。
//
// ★ 口径锁定：stripMarkdownFence 的首行正则用 multiLine:false + '^'
//   ⇒ **只有字符串开头**的围栏会被剥（C-1 §⑨「实现风险」条已点名）。
//   ⇒ 用例 #B4 的期望值钉住这一现行口径，**不写 failsWith**。
//
// ★ 中文引号用 String.fromCharCode(0x201C/0x201D) 构造：既避开源码里的
//   \u 转义（可读性差 + 复制易错），也把「码位」写死在用例里 ——
//   码位错一个字符，本用例必红（这正是 C-1 要求的「改错码位也必红」）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/json_parser_utils.dart';

/// 左双引号 U+201C（LLM 偶发输出）。
final String kLeftSmartQuote = String.fromCharCode(0x201C);

/// 右双引号 U+201D（LLM 偶发输出）。
final String kRightSmartQuote = String.fromCharCode(0x201D);

void main() {
  group('parseJsonLenient — 中文引号容错路径', () {
    test('#A1 中文引号包裹的值 → 解析成功且取值正确', () {
      final input = '{"a": $kLeftSmartQuote你好$kRightSmartQuote}';

      final out = parseJsonLenient(input);

      expect(out, isA<Map<String, dynamic>>());
      expect(
        (out! as Map<String, dynamic>)['a'],
        '你好',
        reason: '中文引号被替换为直引号后，值必须原样取出',
      );
    });

    test('#A2 中文引号包裹的键 → 解析成功且取值正确', () {
      final input = '{${kLeftSmartQuote}a$kRightSmartQuote: 1}';

      final out = parseJsonLenient(input);

      expect(out, isA<Map<String, dynamic>>());
      expect((out! as Map<String, dynamic>)['a'], 1);
    });

    test('#A3 只有一半中文引号（替换后仍非法）→ 抛 FormatException，不得静默返回 null', () {
      final input = '{"a": $kLeftSmartQuote你好}';

      expect(
        () => parseJsonLenient(input),
        throwsA(isA<FormatException>()),
        reason: '容错只修引号；修完仍非法必须抛错，不得吞掉（否则调用方拿 null 当合法结果）',
      );
    });

    test('#A4 无中文引号且 JSON 非法 → 抛 FormatException（钉异常类型）', () {
      expect(
        () => parseJsonLenient('{"a": }'),
        throwsA(isA<FormatException>()),
        reason: 'rethrow 必须保留原始 FormatException 类型，调用方据此区分「格式错」',
      );
    });

    test('#A5 合法 JSON → 原样解析（零开销路径不被容错逻辑污染）', () {
      final out = parseJsonLenient('{"a":1}');

      expect(out, isA<Map<String, dynamic>>());
      expect((out! as Map<String, dynamic>)['a'], 1);
    });
  });

  group('stripMarkdownFence — 围栏剥离路径', () {
    test('#B1 ```json 围栏 → 完全剥离', () {
      expect(stripMarkdownFence('```json\n{"a":1}\n```'), '{"a":1}');
    });

    test('#B2 无语言标记的 ``` 围栏 → 完全剥离', () {
      expect(stripMarkdownFence('```\n{"a":1}\n```'), '{"a":1}');
    });

    test('#B3 单行内联围栏（无换行）→ 完全剥离', () {
      expect(stripMarkdownFence('```json{"a":1}```'), '{"a":1}');
    });

    test('#B4 围栏不在字符串开头 → 只剥尾部（现行口径锁定：head 锚定 multiLine:false）', () {
      expect(
        stripMarkdownFence('pre\n```json\n{"a":1}\n```'),
        'pre\n```json\n{"a":1}',
        reason: '首行正则 multiLine:false + ^ ⇒ 只有串首围栏会被剥；本例钉住现行口径',
      );
    });

    test('#B5 无围栏 → 原样返回（不得误伤）', () {
      expect(stripMarkdownFence('{"a":1}'), '{"a":1}');
    });

    test('#B6 字符串内嵌 ``` → 不得被误剥（仅尾部 ``` 且为串尾才剥）', () {
      expect(
        stripMarkdownFence('{"code":"```","a":1}'),
        '{"code":"```","a":1}',
      );
    });
  });
}
