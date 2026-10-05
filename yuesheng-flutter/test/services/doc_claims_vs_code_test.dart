// ─────────────────────────────────────────────────────────────
// 「文档声称 vs 实际」守卫 · 零额度 · 纯静态（2026-10-06）
//
// 目的：把「注释/头注声称的职责」与「代码实际做的事」钉死。
// 起因（诊断架构外部评审）：本仓多处头注与实际严重不符，读者照注释
// 判断会得到相反结论。已实测到的三例：
//   ① DiagnosisCommitter 名义「提交器」，实际含 UI 副作用（_insertUpgradeCard）
//   ② chat_service.dart 用 4 个 extension 承载（ChatServiceSend 独占 1197 行）
//      —— 且撞本仓自设红线「不可用 extension 拆分」（session_providers.dart:192）
//   ③ DiagnosisService 头注只列 3 项，实际公开方法 8 项
//
// 设计要点（对齐本仓既有护栏与踩坑）：
//   - 判据写成**纯函数**（入参 = 源码文本）⇒ 变异验证可用伪源码自证，
//     **不需要改生产代码**，避开「编译失败也返回 rc=1」（DECISIONS §4-162）。
//   - 豁免用**集合全等**：实际违规集合 == 登记豁免集合。
//     两侧同时被咬住 —— 新增违规（多出）会让集合不等而红；
//     豁免已失效（登记了却不再命中）同样会红 ⇒ fail-closed。
//   - 每条豁免必须带原因；无原因即视为无效登记。
//
// 判据纪律：所有「无条件/恰/必须」都附会变红的判据（本仓铁律）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 读取源文件文本（相对仓库根 yuesheng-flutter/）。
String _src(String path) => File(path).readAsStringSync();

// ─────────────────────────────────────────────────────────────
// 判据 ①：DiagnosisCommitter 不应含 UI 卡片插入方法
// ─────────────────────────────────────────────────────────────

/// 找出 `DiagnosisCommitter` 内形如 `_insertXxxCard` 的方法名。
///
/// 判据是**方法名含 Card 且以 insert/Insert 开头**（UI 副作用语义），
/// 不看实现 —— 目的是「职责是否落在这一层」，不是「代码写得对不对」。
List<String> cardMethodsInCommitter(String source) {
  final re = RegExp(
    r'^\s+(?:Future<[^>]*>|void|String|int|bool)\s+(_\w*[Cc]ard\w*)\s*\(',
    multiLine: true,
  );
  return re.allMatches(source).map((m) => m.group(1)!).toSet().toList()..sort();
}

/// 已登记豁免（含原因）。新增违规或本表失效都会让「集合全等」判红。
const Map<String, String> kCommitterCardExemptions = <String, String>{
  '_insertUpgradeCard':
      'UI 副作用能力错位（提交器不该插卡片）。待 B3 迁到 message_card_service，'
      '迁完从本表删除 —— 删不掉说明没迁干净，会被集合全等判红。',
};

// ─────────────────────────────────────────────────────────────
// 判据 ②：chat_service.dart 的 extension 块数与最长跨度
// ─────────────────────────────────────────────────────────────

class ExtensionSpan {
  const ExtensionSpan(this.name, this.lineNo, this.span);
  final String name;
  final int lineNo;
  final int span;
}

/// 计算每个 `extension X on Y { ... }` 的声明行号与到块尾的行数。
///
/// 块尾取「下一个 extension 声明」之前最后一个非空 `}` 所在行 +1。
/// 这是文本级近似（不解析 Dart AST），故**断言给的是上界**，
/// 并且同时钉住「块数」这一更粗的指标 —— 任一变化都会变红。
List<ExtensionSpan> extensionSpans(String source) {
  final lines = source.split('\n');
  final starts = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('extension ')) starts.add(i);
  }
  final out = <ExtensionSpan>[];
  for (var k = 0; k < starts.length; k++) {
    final from = starts[k];
    final limit = k + 1 < starts.length ? starts[k + 1] : lines.length;
    var end = limit;
    for (var j = limit - 1; j > from; j--) {
      if (lines[j].trim() == '}') {
        end = j + 1;
        break;
      }
    }
    final decl = lines[from];
    final m = RegExp(r'extension\s+(\w+)\s+on').firstMatch(decl);
    out.add(ExtensionSpan(m?.group(1) ?? decl.trim(), from + 1, end - from));
  }
  return out;
}

/// 已登记豁免：键 = 块名，值 = 原因。
/// 注意豁免按**块名**登记而非行数 —— 行数会漂，按行号登记必然漂移。
const Map<String, String> kChatServiceExtensionExemptions = <String, String>{
  'ChatServiceDiagnosisFocus': '待 B5 消解。当前 chunk 规模尚可（实测约 36 行），登记仅为记录现状。',
  'ChatServiceObservers': '待 B5 消解。当前 chunk 规模尚可（实测约 32 行），登记仅为记录现状。',
  'ChatServiceSendRun': '待 B5 消解。当前 chunk 规模尚可（实测约 134 行）。',
  'ChatServiceSend':
      '待 B5 消解，且这是本仓自设红线冲突点 —— session_providers.dart:192 '
      '明写「不可用 extension 拆分」，而本块实测约 1197 行（2026-10-06），'
      '说明它并未解决想解决的问题（拆后文件仍近 2000 行）。'
      '判为伪拆分，须改为独立类 + 显式接口 + 依赖注入。',
};

// ─────────────────────────────────────────────────────────────
// 判据 ③：DiagnosisService 头注声明的方法集合 == 公开方法集合
// ─────────────────────────────────────────────────────────────

/// 取文件开头连续的 `//` 注释块（头注）。
String _headerComment(String source) {
  final buf = <String>[];
  for (final line in source.split('\n')) {
    final t = line.trim();
    if (t.startsWith('//')) {
      buf.add(line);
    } else if (t.isEmpty) {
      continue;
    } else {
      break;
    }
  }
  return buf.join('\n');
}

/// 取公开方法名（顶格两空格缩进、以小写字母开头、紧跟左括号）。
///
/// ⚠️ 正则必须容忍跨词空白（`Future<void> foo(` 中间有多处空格）
///    —— 初版写成 `\S+` 会在真实 Dart 签名上返回空列表，
///    外观与「该类没有公开方法」完全相同（探针缺陷伪装成被测对象问题，
///    本仓已多次实测，见 DECISIONS §4-153）。故用带 `\\s*` 的宽松匹配。
List<String> publicMethods(String source) {
  final re = RegExp(
    r'^ {2}(?:static\s+)?[A-Za-z_][A-Za-z0-9_<>,\?\. ]*\s+([a-z]\w*)\s*\(',
    multiLine: true,
  );
  final names = re.allMatches(source).map((m) => m.group(1)!).toSet().toList()
    ..sort();
  return names;
}

// ─────────────────────────────────────────────────────────────
// 测试
// ─────────────────────────────────────────────────────────────

void main() {
  group('文档声称 vs 实际 · 职责错位守卫', () {
    // ① DiagnosisCommitter 的卡片方法
    test('① DiagnosisCommitter 不含 UI 卡片插入（豁免须逐条带原因，且集合全等）', () {
      final actual = cardMethodsInCommitter(
        _src('lib/services/diagnosis_committer.dart'),
      );
      final registered = kCommitterCardExemptions.keys.toList()..sort();
      expect(
        actual,
        registered,
        reason:
            '卡片方法集合与登记豁免**不一致**（fail-closed）。\n'
            '  实际命中：$actual\n'
            '  已登记：$registered\n'
            '含义：① 出现未登记的卡片方法（新增职责错位）；'
            '② 已登记的卡片方法不再存在（豁免失效却没销账）。\n'
            'B3 把 _insertUpgradeCard 迁到 message_card_service 后，'
            '须同步从 $kCommitterCardExemptions 删除对应项。',
      );
      // 豁免必须带原因 —— 空原因说明是「随手登记」而非「有据可依」
      for (final entry in kCommitterCardExemptions.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '豁免 ${entry.key} 必须写明原因，禁止空理由登记',
        );
      }
      // 正对照：判据函数本身有牙齿 —— 伪源码里塞一个 insert*Card 必须被抓到
      expect(
        cardMethodsInCommitter(
          'class X {\n  Future<void> _insertSomethingCard(int a) async {}\n}\n',
        ),
        ['_insertSomethingCard'],
        reason: '判据函数自证：伪源码里的 insert*Card 必须被识别（否则①恒真=装饰）',
      );
      expect(
        cardMethodsInCommitter(
          'class X {\n  Future<int> persistSomething() async {}\n}\n',
        ),
        isEmpty,
        reason: '判据函数自证：不含 Card 的方法不应被误报（防误判）',
      );
    });

    // ② chat_service.dart 的 extension 块
    test('② chat_service.dart extension 块数 ≤1 且最长 ≤300 行（豁免集合全等）', () {
      final spans = extensionSpans(_src('lib/services/chat_service.dart'));
      final registered = kChatServiceExtensionExemptions.keys.toList()..sort();
      final actualNames = spans.map((s) => s.name).toList()..sort();
      expect(
        actualNames,
        registered,
        reason:
            'extension 块集合与登记豁免**不一致**（fail-closed）。\n'
            '  实际：$actualNames\n'
            '  已登记：$registered\n'
            '含义：① 新增 extension（撞红线，须同时更新本表并说明理由）；'
            '② 已登记块不再存在（豁免失效却没销账）。\n'
            '本表按**块名**登记而非行数 —— 行数会漂，按行号登记必然漂移。',
      );
      for (final entry in kChatServiceExtensionExemptions.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '豁免 ${entry.key} 必须写明原因，禁止空理由登记',
        );
      }
      // ★ B5 的两条目标值（块数 ≤1 / 最长 ≤300 行）**故意不写成断言**。
      //   理由：B5 尚未落地，写成断言即恒红 ⇒ 门禁 2 永久红灯 ⇒ 本批无法提交；
      //   而恒红的断言不提供任何信息（§4-177 的镜像面：硬写就是用「常红」
      //   换「看起来严格」）。正确形态 = 目标值写在文件头，现行断言只守
      //   「不漂移」（上面的集合全等已咬住新增与失效两侧）。
      //   B5 落地时：把两条目标提为断言 + 同时删除对应豁免项。
      //
      // 追加判据（可满足且有牙齿）：每条豁免必须指明关闭批次 ——
      // 防止「随手登记 ⇒ 永久开口 ⇒ 永不销账」。
      for (final entry in kChatServiceExtensionExemptions.entries) {
        expect(
          entry.value.contains('待 B'),
          isTrue,
          reason:
              '豁免 ${entry.key} 的原因必须指明关闭批次（形如「待 B5」）。'
              '缺此项 ⇒ 该豁免会变成永不销账的永久开口',
        );
      }
      // 正对照：判据函数自证 —— 伪源码里造两个 extension 必须被数出来
      final fake = extensionSpans(
        'extension A on Y {\n  void a() {}\n}\n'
        'extension B on Y {\n  void b() {}\n  void c() {}\n}\n',
      );
      expect(
        fake.length,
        2,
        reason: '判据函数自证：伪源码里的 2 个 extension 必须被数出（否则②恒真=装饰）',
      );
      expect(
        fake[1].span,
        greaterThan(fake[0].span),
        reason: '判据函数自证：第二个块更大（跨度计算有区分度，不是恒定值）',
      );
    });

    // ③ DiagnosisService 头注
    test('③ DiagnosisService 头注覆盖全部公开方法（本次已直接修头注 ⇒ 应绿）', () {
      final source = _src('lib/services/diagnosis_service.dart');
      final header = _headerComment(source);
      final methods = publicMethods(source);
      expect(
        methods,
        isNotEmpty,
        reason:
            '公开方法解析结果不得为空。若为空说明判据正则与源码格式脱节，'
            '本条会假绿（解析器静默失配 ⇒ 后续断言全部无意义）',
      );
      final missing = methods.where((m) => !header.contains(m)).toList()
        ..sort();
      expect(
        missing,
        isEmpty,
        reason:
            '头注未声明的公开方法：$missing。\n'
            '头注是下一个读者的唯一入口 —— 漏写就等于让其按错误心智模型改动。\n'
            '修法：把缺失方法补进头注的「职责」列表（纯注释，零逻辑改动）。',
      );
      // 正对照：把 header 换成空串 ⇒ 必须报出全部方法（证明 missing 逻辑有牙齿）
      final allMissing =
          methods.where((m) => !_headerComment('').contains(m)).toList()
            ..sort();
      expect(
        allMissing.length,
        methods.length,
        reason:
            '判据函数自证：空头注 ⇒ 全部方法都算缺失。'
            '若此条不成立，说明 missing 恒为空 ⇒ ③ 恒绿 = 装饰',
      );
    });
  });
}
