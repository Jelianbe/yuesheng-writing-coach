// ─────────────────────────────────────────────────────────────
// 注入链约束目录单表（R-027 · L-INJ 层唯一真源）
//
// 背景（D7-硬编码话术溯源 §4.4 / §4.5 / C-P1-4）：
//   R-009 不替写、表达密度（一次只抛一个点）、态度档示范、趋势诚实等纪律
//   此前散落在 prompt_assembly / shared_constants / chat_service / realtime /
//   diagnosis_committer / intent_classifier 等 ≥8 处各写各的，措辞互相漂移；
//   且「回复纪律 / 临场输出约束 / 按需介入」三块内容重叠却各自自称「最高优先级」，
//   规则冲突时模型无裁决序。
//
// 本文件 = 注入链纪律的**唯一权威**。各注入块只 import 本类引用下列常量，
// 再补本通道特化尾巴（如：实时通道示范 ≤2 句、完整章模式不打分/不开处方、
// 全貌模式编号清单格式），不再手抄规则正文。
//
// 边界：
//   - 判据 P-code → 中文名**不在这里硬编码**，走
//     `syndrome_registry.syndromeNameOf(code)` 运行时查询（见 chat_context_builder
//     F-blocks）——判据改名/退休时注入散文自动跟随，不留旧名残留。
//   - 本层不 import L-UI（teaching_labels）；严重度标签由各层自持同值副本。
// ─────────────────────────────────────────────────────────────
abstract final class InjectionConstraints {
  const InjectionConstraints._();

  /// R-009 不替写：不替学员写句子、不替学员做决定；只给结构性提问与方向。
  ///
  /// 各通道特化尾巴示例：完整章模式另「不打分、不开处方」；
  /// 编辑观察通道另「只定位问题与位置，不代改正文」；资料摘要通道另「不替作者判断」。
  static const String r009NoWrite = '不替学员写句子、不替学员做决定；只给结构性提问与方向。';

  /// 表达密度：一次只抛一个点，删掉铺垫；学员问题多时按优先级分轮展开。
  ///
  /// 全貌模式是其唯一例外（见 [fullPictureException]）。
  static const String densityOnePoint = '一次只抛一个点，删掉铺垫；学员问题多时按优先级分轮展开。';

  /// 态度档示范：按态度档位决定示范量。统一「月笙」措辞
  /// （修复 prompt_assembly 旧文用拼音「yuesheng」与 shared_constants
  /// 用汉字「月笙」的漂移，D7 §4.10）。
  static const String demoByAttitude =
      '示范按态度档位执行：温柔语气/月笙给最小示范一例，Sensei 不给示范只指方向。';

  /// 趋势诚实：一次诊断不算趋势，单次证据不冒充长期走向。
  static const String trendHonest = '一次诊断不算趋势；不说「你改善了/恶化了/掌握了」，改说「练习中做对了方向」。';

  /// 全貌模式 = [densityOnePoint] 的例外（识别症候数达阈值时）：
  /// 全量编号列出、不给改法，末尾把选择权交回学员；学员选定后才展开「怎么改」。
  static const String fullPictureException =
      '症候数量达到阈值时全量编号列出，不给改法，末尾问「你想先动哪个」；'
      '学员选定一条后才对该条展开怎么改。';
}
