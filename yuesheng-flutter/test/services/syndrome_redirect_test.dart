// T-20261031-12 撤销改道：33 条登记的遍历断言 + 改道字段失配净化单测。
//
// 判据来源：报批稿 §2.3（遍历断言）/ §2.4（三项校验落点 + 失配即丢字段）/
// §6（判据变红清单）。真源：症状真源 `kSyndromeIds`（注册表）·
// 动作真源 `kActionShortNames`（动作目录）——本文件不另立真源。
//
// ★ 文案唯一真源 = 温知新终稿表 §二（逐字）；本文件只断言**结构与指向**，
//   不复制第二份文案（防漂移的第二份副本）。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chunk_prompt.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/syndrome_redirect.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 文案里的 id 记号（Pxxx / Axxx）。
final RegExp _idPattern = RegExp(r'[PA]\d{3}');

Set<String> _idsIn(String text) =>
    _idPattern.allMatches(text).map((m) => m.group(0)!).toSet();

void main() {
  group('撤销改道登记表 · 遍历断言（报批稿 §2.3）', () {
    test('33 条齐全：S→15 · A→7 · T 11', () {
      expect(kSyndromeRedirects.length, 33);
      expect(kSyndromeRedirects.values.where((r) => r.type == 'S').length, 15);
      expect(kSyndromeRedirects.values.where((r) => r.type == 'A').length, 7);
      expect(kSyndromeRedirects.values.where((r) => r.type == 'T').length, 11);
    });

    test('每条文案里的 id 集 == 该行 allowed 集（不多不少）', () {
      for (final e in kSyndromeRedirects.entries) {
        final ids = _idsIn(e.value.text);
        expect(
          ids,
          e.value.allowed,
          reason:
              '${e.key}：文案里的 id 集 ${ids.toList()} '
              '与登记 allowed 集 ${e.value.allowed.toList()} 不一致',
        );
      }
    });

    test('每个指向 ∈ 真源（注册表症状 id ∪ 动作目录 id）', () {
      for (final e in kSyndromeRedirects.entries) {
        for (final id in e.value.allowed) {
          final known =
              kSyndromeIds.contains(id) || kActionShortNames.containsKey(id);
          expect(known, isTrue, reason: '${e.key} 的指向 $id 不在真源里');
        }
      }
    });

    test('primary ∈ allowed；T 行无 primary 且 allowed 为空', () {
      for (final e in kSyndromeRedirects.entries) {
        final row = e.value;
        if (row.type == 'T') {
          expect(row.primary, isNull, reason: '${e.key} 是 T 行，不该有主指向');
          expect(row.allowed, isEmpty, reason: '${e.key} 是 T 行，不该有指向');
          expect(row.inModelFace, isFalse, reason: '${e.key} 是 T 行，不进模型面');
          continue;
        }
        expect(row.primary, isNotNull, reason: '${e.key} 缺主指向');
        expect(
          row.allowed.contains(row.primary!),
          isTrue,
          reason: '${e.key} 的主指向 ${row.primary} 不在 allowed 集内',
        );
        expect(row.inModelFace, isTrue, reason: '${e.key} 是 S/A 行，应进模型面');
      }
    });

    test('分支切分：S/A 行每支恰含一个 allowed id，且分支 id 集 == allowed', () {
      for (final e in kSyndromeRedirects.entries) {
        final row = e.value;
        if (!row.inModelFace) continue;
        final branches = redirectBranchesOf(row);
        expect(
          branches.length,
          row.allowed.length,
          reason: '${e.key} 分支数与 allowed 数不一致',
        );
        expect(
          branches.map((b) => b.id).toSet(),
          row.allowed,
          reason: '${e.key} 分支 id 集与 allowed 集不一致',
        );
        for (final b in branches) {
          expect(
            b.clause.contains(b.id),
            isTrue,
            reason: '${e.key} 的分支句未含自己的 id',
          );
          final others = row.allowed.where((id) => id != b.id).toList();
          for (final other in others) {
            expect(
              b.clause.contains(other),
              isFalse,
              reason: '${e.key} 的分支句混入了另一个指向 $other',
            );
          }
        }
      }
    });
  });

  group('模型面例外行注入（分块链）', () {
    test('只有 S/A 22 条进模型面，T 11 条不进', () {
      final prompt = buildChunkSystemPrompt();
      for (final e in kSyndromeRedirects.entries) {
        final present = prompt.contains('撤销 ${e.key}（');
        expect(present, e.value.inModelFace, reason: '${e.key} 的模型面落位与登记类型不符');
      }
    });

    test('协议行含 redirect 字段与说明段', () {
      final prompt = buildChunkSystemPrompt();
      expect(prompt.contains('"redirect"'), isTrue);
      expect(prompt.contains('redirect 字段说明'), isTrue);
    });
  });

  group('改道字段净化 · 失配即丢字段（报批稿 §2.4）', () {
    test('合法 redirect：三字段全保留且无留痕', () {
      final f = sanitizeRedirect({
        'syndrome_id': 'P009',
        'text': '对话段落里先修对话结构（P009）',
      }, ownerSyndromeId: 'P001');
      expect(f.syndromeId, 'P009');
      expect(f.actionId, isNull);
      expect(f.text, '对话段落里先修对话结构（P009）');
      expect(f.traces, isEmpty);
    });

    test('指向不在该行 allowed ⇒ 丢字段并留痕', () {
      final f = sanitizeRedirect({
        'syndrome_id': 'P099',
        'text': '随便一句',
      }, ownerSyndromeId: 'P001');
      expect(f.syndromeId, isNull);
      expect(f.text, isNull);
      expect(f.traces, isNotEmpty);
    });

    test('text 非逐字取自该行 ⇒ 丢 text、留痕，指向保留', () {
      final f = sanitizeRedirect({
        'syndrome_id': 'P009',
        'text': '你自己重写一遍',
      }, ownerSyndromeId: 'P001');
      expect(f.syndromeId, 'P009');
      expect(f.text, isNull);
      expect(f.traces, isNotEmpty);
    });

    test('同时给两个指向 ⇒ 按择一丢一支并留痕', () {
      final f = sanitizeRedirect({
        'syndrome_id': 'P024',
        'action_id': 'A003',
      }, ownerSyndromeId: 'P010');
      expect(f.syndromeId, isNull, reason: '该行主指向是 A003 ⇒ 留 A003');
      expect(f.actionId, 'A003');
      expect(f.traces, isNotEmpty);
    });

    test('未登记症候的 redirect ⇒ 全丢并留痕', () {
      final f = sanitizeRedirect({
        'syndrome_id': 'P009',
        'text': '任意',
      }, ownerSyndromeId: 'P002');
      expect(f.syndromeId, isNull);
      expect(f.actionId, isNull);
      expect(f.text, isNull);
      expect(f.traces, isNotEmpty);
    });

    test('无 redirect ⇒ 未指认且不留痕', () {
      final f = sanitizeRedirect(null, ownerSyndromeId: 'P001');
      expect(f.syndromeId, isNull);
      expect(f.actionId, isNull);
      expect(f.text, isNull);
      expect(f.traces, isEmpty);
    });
  });

  // ── 卡面 V1：协议字段双向键集合（写入 / 读出对称）+ 缺省容错有单测 ──
  group('ParsedExclusion 读写对称（卡面 V1）', () {
    test('toJson → fromJson 往返：指向 + 逐字句对称，缺省方向仍为 null', () {
      const e = ParsedExclusion(
        syndromeId: 'P007',
        reason: '动机已立住，行为前后矛盾',
        redirectSyndromeId: 'P015',
        redirectText: '角色空心化不成立时：动机本已立住而行为前后矛盾，转 P015 的训练',
      );
      final json = e.toJson();
      expect(json['redirect'], isA<Map<String, dynamic>>());
      final back = ParsedExclusion.fromJson(json);
      expect(back.syndromeId, 'P007');
      expect(back.reason, '动机已立住，行为前后矛盾');
      expect(back.redirectSyndromeId, 'P015');
      expect(back.redirectActionId, isNull);
      expect(back.redirectText, '角色空心化不成立时：动机本已立住而行为前后矛盾，转 P015 的训练');
    });

    test('缺省容错：三字段皆空 ⇒ 不落 redirect 键 ⇒ 往返仍皆空', () {
      const e = ParsedExclusion(syndromeId: 'P002', reason: '证据不足');
      final json = e.toJson();
      expect(
        json.containsKey('redirect'),
        isFalse,
        reason: '未指认时整个 redirect 不落 key（往返稳定）',
      );
      final back = ParsedExclusion.fromJson(json);
      expect(back.redirectSyndromeId, isNull);
      expect(back.redirectActionId, isNull);
      expect(back.redirectText, isNull);
    });

    test('动作指向（A 行）同样对称', () {
      const e = ParsedExclusion(
        syndromeId: 'P006',
        reason: '不成立',
        redirectActionId: 'A011',
        redirectText: '语言堆砌不成立而文字仍显繁复时，同域的练法是场景裁剪（A011）——是否使用由你决定。',
      );
      final back = ParsedExclusion.fromJson(e.toJson());
      expect(back.redirectActionId, 'A011');
      expect(back.redirectSyndromeId, isNull);
      expect(back.redirectText, e.redirectText);
    });
  });
}
