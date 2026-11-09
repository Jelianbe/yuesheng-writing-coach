// ─────────────────────────────────────────────────────────────
// 落点乙新装配面牙测（R-027 · T-20261109-01 施工批）。
//
// 对应报批稿 `.ai/reports/2026-11-09-报批稿-落点乙-*.md` 能变红判据：
//   A1  S-2 · 方向集为代码常量（枚举长度 + 逐值断言 + 兜底永不缺席）
//   A2  S-2 · 方向值只准来自枚举（断言牙 + 轮转函数值域断言）
//   C1  装配完整性：方向段标题 + 域声明段标题同现
//   C2  单域声明：`### 证据域声明（` 恰一次
//   C3  S-1 · 装配产物不含症候库判据正文（oneLine / manual，分母非空）
//   D2 默认装配（裁点乙）：D2 在、D1/D3 不在（D3 备而不装）
//
// 读数口径：本文件只断言结构态，不产出语义读数（行为挂 U4，E3 未验）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/discovery_chat_pilot.dart';
import 'package:writingcoach/services/discovery_prompt.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';

void main() {
  group('A1 S-2 · 方向集为代码常量', () {
    test('六值逐字 + 兜底永不缺席', () {
      expect(kDiscoveryDirections, <String>[
        '人物动机与行为逻辑',
        '情节因果与伏笔照应',
        '信息组织与叙事节奏',
        '语言表达与文字规范',
        '读者理解与阅读体验',
        '通用观察',
      ]);
      expect(kDiscoveryDirections.last, '通用观察', reason: 'S-2 兜底永不缺席');
      expect(kDiscoveryDirections.length, 6);
    });

    test('方向名不含症候 ID 形态（方向 = 分析领域，非症候清单）', () {
      final pattern = RegExp(r'P0\d\d');
      for (final direction in kDiscoveryDirections) {
        expect(
          pattern.hasMatch(direction),
          isFalse,
          reason: '方向名含症候 ID ⇒ S-1 同源破防：$direction',
        );
      }
    });
  });

  group('A2 S-2 · 方向值只来自枚举', () {
    test('轮转函数输出恒为枚举成员，且兜底不作主方向', () {
      for (var i = 0; i < kDiscoveryDirections.length * 2; i++) {
        final direction = resolveChatDiscoveryDirection(ordinal: i);
        expect(
          kDiscoveryDirections.contains(direction),
          isTrue,
          reason: '轮转产出枚举外方向 ⇒ A2 破防：$direction',
        );
        expect(direction, isNot('通用观察'), reason: '兜底方向不作主方向（永不缺席即可）');
      }
    });

    test('非枚举方向被装配函数断言拦截（debug 断言）', () {
      expect(
        () => buildChatDiscoverySystemPrompt(direction: '自创方向'),
        throwsA(isA<AssertionError>()),
        reason: 'A2：调用侧无自由生成路径',
      );
    });

    test('槽位填充：主方向逐字进入装配产物', () {
      final prompt = buildChatDiscoverySystemPrompt(direction: '语言表达与文字规范');
      expect(prompt.contains('- 主方向：语言表达与文字规范'), isTrue);
      expect(prompt.contains('{direction}'), isFalse, reason: '槽位必须被填充');
    });
  });

  group('C1/C2/D2 · 装配完整性与单域声明', () {
    final prompt = buildChatDiscoverySystemPrompt(
      direction: resolveChatDiscoveryDirection(ordinal: 0),
    );

    test('C1：方向段标题 + 域声明段标题同现', () {
      expect(prompt.contains('## 分析方向（系统指定）'), isTrue);
      expect(prompt.contains('### 证据域声明（D'), isTrue);
    });

    test('C2：域声明恰一份', () {
      expect(
        '### 证据域声明（'.allMatches(prompt).length,
        1,
        reason: '叠装 = 域并集语义失控（报批稿装配规则）',
      );
    });

    test('裁点乙：默认装配 D2；D1/D3 不参与装配（D3 备而不装）', () {
      expect(prompt.contains('### 证据域声明（D2 · 正文 + 会话上下文）'), isTrue);
      expect(prompt.contains('### 证据域声明（D1'), isFalse);
      expect(prompt.contains('### 证据域声明（D3'), isFalse);
      // 反向对照（防「三份域文本都丢了」时上面恒真）：D3 文本常量必须还在。
      expect(kDiscoveryDomainD3.contains('### 证据域声明（D3'), isTrue);
    });

    test('域声明核心纪律逐字在场（回忆不等于证据）', () {
      expect(prompt.contains('回忆不等于证据'), isTrue);
    });
  });

  group('C3 S-1 · 装配产物不含症候库判据正文', () {
    test('oneLine 全文与手册判据行都不出现（分母非空）', () {
      final prompt = buildChatDiscoverySystemPrompt(
        direction: resolveChatDiscoveryDirection(ordinal: 3),
      );

      // 分母：取最长的 3 条 oneLine（与 discovery_call_test J1 同口径）。
      final oneLines = kSyndromeRegistry.map((r) => r.oneLine).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final samples = oneLines.take(3).toList();
      expect(samples.length, 3, reason: '分母非空：样本不足则断言无意义');
      for (final sample in samples) {
        expect(sample.length, greaterThan(10), reason: '样本过短 ⇒ 断言无牙');
        expect(
          prompt.contains(sample),
          isFalse,
          reason: '发现帧含症候判据正文 ⇒ S-1 破防：$sample',
        );
      }

      // 手册最长正文行（整段 contains 因换行必 false 是恒真断言，取单行才有牙）。
      final lines = kSyndromeManualContent
          .split('\n')
          .where(
            (String line) => line.trim().isNotEmpty && !line.startsWith('###'),
          );
      var longest = '';
      for (final line in lines) {
        if (line.length > longest.length) longest = line;
      }
      expect(longest.length, greaterThan(30), reason: '手册判据行样本过短 ⇒ 无牙');
      expect(prompt.contains(longest), isFalse, reason: '发现帧含手册判据正文');
    });
  });

  group('逐字锚定（授权面字节锚）', () {
    test('方向段与 D2 域声明关键句逐字在场', () {
      expect(
        kDiscoveryDirectionSegment.contains('1. 方向由系统指定。你不得更换、增加或自行发明分析方向。'),
        isTrue,
      );
      expect(kDiscoveryDomainD2.contains('② 本会话中用户与系统发来的消息。'), isTrue);
      expect(kDiscoveryDomainD1.contains('本章正文之外的一切文本'), isTrue);
      expect(kDiscoveryDomainD3.contains('设定与正文冲突时，须同时摘录两处原句'), isTrue);
    });
  });
}
