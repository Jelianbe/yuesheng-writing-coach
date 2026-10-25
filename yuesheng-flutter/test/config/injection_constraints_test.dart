// ─────────────────────────────────────────────────────────────
// injection_constraints_test — C-3 批：注入链约束目录单表（唯一真源）
//
// 覆盖对象：lib/config/injection_constraints.dart（49 行，0 覆盖）
//   公开符号：InjectionConstraints.r009NoWrite / densityOnePoint /
//              demoByAttitude / trendHonest / fullPictureException（5 个 static const）
//
// ★ 本文件只补 C-1 裁定（.ai/research/t13-c1-test-triage.md §①）点名的缺口：
//   · 判据 A：demoByAttitude 的正文**从未被任何断言**（test/ 全树检索 0 命中）
//     ⇒ 本文件钉住它的正文出现在临场输出约束里。
//   · 判据 C：元护栏 —— 5 条纪律正文在 lib/ 全树**各只允许出现于本文件一处**
//     （其余通道只许引用常量，不许手抄正文）。
//   · 判据 B（trendHonest 接线 or 退役）：**本文件不写** —— 两条路都要改 lib/
//     （接线 = 改消费方；退役 = 删常量），超本批授权 ⇒ 已回报主理人裁定。
//
// ★ 可红判据（改哪一处必红）：
//   ① 把 lib/config/injection_constraints.dart:38-39 的 demoByAttitude 正文
//      改一个字（如「最小示范」→「小示范」）⇒ 用例 #A 必红。
//   ② 在 lib/services/chat_service.dart:264 把 `${InjectionConstraints.r009NoWrite}`
//      改成手抄正文 ⇒ 用例 #C 必红（正文在两个文件出现）。
//   ③ 在任意 lib/ 文件里手抄 densityOnePoint / fullPictureException / trendHonest
//      正文 ⇒ 用例 #C 必红。
//
// ★ 判据 C 的实现要点（C-1 §① 点名的最大实现风险）：
//   ① 只比对**完整正文串**，绝不比对子串 —— 否则
//      「一次只抛一个点」「不替学员写句子」这类自然语句会假红。
//      （实测：lib/ 全树 512 个 .dart，5 条正文的**完整串**各只命中本文件一处。）
//   ② 本文件自身把 fullPictureException 拆成**两个相邻字面量**
//      （lib/config/injection_constraints.dart:46-48）⇒ 源文件里查不到完整串。
//      故比对前必须把**相邻字面量**归一化（去掉相邻单引号之间的空白与引号），
//      否则 fullPictureException 会 0 命中 → 假红。
//      归一化只用于「把源文本还原成它表达的字面量」，不改变任何判定口径。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';

/// 5 条纪律的**完整正文**（钉字面量，不引用被测常量 —— 否则是永真断言）。
const Map<String, String> kDisciplineBodies = {
  'r009NoWrite': '不替学员写句子、不替学员做决定；只给结构性提问与方向。',
  'densityOnePoint': '一次只抛一个点，删掉铺垫；学员问题多时按优先级分轮展开。',
  'demoByAttitude': '示范按态度档位执行：温柔语气/月笙给最小示范一例，Sensei 不给示范只指方向。',
  'trendHonest': '一次诊断不算趋势；不说「你改善了/恶化了/掌握了」，改说「练习中做对了方向」。',
  'fullPictureException':
      '症候数量达到阈值时全量编号列出，不给改法，末尾问「你想先动哪个」；'
      '学员选定一条后才对该条展开怎么改。',
};

/// 本文件（纪律目录单表）的仓库内相对路径。
const String kCatalogPath = 'lib/config/injection_constraints.dart';

Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

final Directory _root = _findPackageRoot();

/// 把源文件里的**相邻字面量**拼回去（`'甲'\n'乙'` ⇒ `'甲乙'`）。
///
/// 存在的唯一理由：纪律目录单表自己把 fullPictureException 拆成两个字面量，
/// 不归一化就查不到它的完整正文 ⇒ 判据 C 必假红。
String _joinAdjacentLiterals(String src) =>
    src.replaceAll(RegExp(r"'\s*'"), '');

/// 扫 lib/ 全树，返回「哪些文件含有该完整正文」。
List<String> _filesContainingBody(String body) {
  final hits = <String>[];
  final libDir = Directory('${_root.path}/lib');
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path
        .replaceAll(r'\', '/')
        .replaceFirst('${_root.path.replaceAll(r'\', '/')}/', '');
    final joined = _joinAdjacentLiterals(entity.readAsStringSync());
    if (joined.contains(body)) hits.add(rel);
  }
  hits.sort();
  return hits;
}

void main() {
  group('InjectionConstraints — 纪律正文被真正注入', () {
    test('#A demoByAttitude 正文出现在临场输出约束里（钉字面量，非引用常量）', () {
      expect(
        kLiveOutputConstraints,
        contains('示范按态度档位执行：温柔语气/月笙给最小示范一例，Sensei 不给示范只指方向。'),
        reason:
            '态度档示范是「态度档决定示范量」这条纪律的唯一落地口径，'
            '正文被改/被删 ⇒ 临场输出约束失效',
      );
    });
  });

  group('InjectionConstraints — 唯一真源元护栏', () {
    test('#C1 纪律正文在 lib/ 全树各只出现于目录单表一处（防手抄漂移）', () {
      for (final entry in kDisciplineBodies.entries) {
        final hits = _filesContainingBody(entry.value);
        expect(
          hits,
          <String>[kCatalogPath],
          reason:
              '${entry.key} 的纪律正文只允许出现在目录单表一处；'
              '其余通道必须引用常量，不许手抄正文（命中：$hits）',
        );
      }
    });

    test('#C2 扫描面本身非空（阳性对照：防扫描器静默失效造成零命中假绿）', () {
      final dartFiles = Directory('${_root.path}/lib')
          .listSync(recursive: true)
          .where((e) => e is File && e.path.endsWith('.dart'))
          .length;
      expect(
        dartFiles,
        greaterThan(100),
        reason: 'lib/ 下的 .dart 数量异常 ⇒ 扫描面没生效，#C1 的「零命中」是假绿',
      );
    });

    test('#C3 归一化能把拆开的相邻字面量拼回（阳性对照：证明扫描口径真的能命中）', () {
      final src = "'前半'\n      '后半'";
      expect(
        _joinAdjacentLiterals(src),
        contains('前半后半'),
        reason: '归一化失效 ⇒ fullPictureException 这类跨字面量正文会 0 命中 ⇒ #C1 假红',
      );
    });
  });
}
