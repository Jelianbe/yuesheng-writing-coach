// ─────────────────────────────────────────────────────────────
// diagnosis_temperature — 诊断温度档位（用户可调「诊断风格」真源）
//
// 背景（W-18 诊断稳定性实验，2026-10-15；报告
// .ai/reports/2026-10-15-W18-诊断稳定性实验报告.md）：
//   现网诊断 merge 段（流式）温度 0.7（streamTemperature），单块分析段
//   恒 0.3（chatTemperature）。实验测得：0.7 档轮间一致性 Jaccard 0.447
//   （噪声约 ±55%），0.3 档 0.532（+19%）且总命中守恒——但两档对人工
//   标注的命中效基本持平（并集 57%/52%），无压倒性证据替用户做单边决定
//   ⇒ 舰长裁定（2026-10-16）：不直接切现网，改为**用户可选档位** +
//   形态标注（只标「保守/灵活」区分，不承诺好坏）。
//
// 本文件是「档位 → 温度值」的唯一真源：
//   UI（设置页「诊断风格」）只引用 [diagnosisTemperaturePresets]；
//   诊断链路只经 [mergeTemperatureFor] 消费（落在 merge 段 extraBody）。
//
// 作用域边界（刻意的，勿外溢）：
//   - 只作用于**诊断 merge（流式）段**。单块分析段恒 0.3——W-18 两档
//     实验中该段本就固定 0.3（YS_TEST_TEMP 只覆盖流式段），本档位与
//     实验装置完全同构：保守档 = 实验档完整复现，灵活档 = 现网基线。
//   - 教学对话（chat/stream）不受影响——thinking 开关曾实证「参数效果
//     随诊断/教学场景翻转」（诊断零退化、教学 6/6 任务失败），W-18 只
//     验证了诊断链路，档位不得外溢到教学链路。
//   - 灵活档（0.7）= 现网值：[mergeTemperatureFor] 对灵活档返回 null
//     （不产 extraBody 键）⇒ 请求体**逐字节不变**。
// ─────────────────────────────────────────────────────────────

/// 档位 key：灵活（0.7，现网默认）。
const String diagnosisTempFlexible = 'flexible';

/// 档位 key：保守（0.3，W-18 实验档）。
const String diagnosisTempSteady = 'steady';

/// app_state 存储键（AppStateRepository.getValue / setValue）。
const String kDiagnosisTemperatureKey = 'diagnosis_temperature';

/// 诊断温度档位预设（key 为存储值，value 为 merge 段请求体温度）。
class DiagnosisTemperaturePreset {
  /// 档位 key（存储值）。
  final String key;

  /// 界面展示名。
  final String label;

  /// 界面副文案（形态说明；只描述差异，不承诺好坏）。
  final String hint;

  /// merge（流式）段请求体温度。
  final double value;

  const DiagnosisTemperaturePreset({
    required this.key,
    required this.label,
    required this.hint,
    required this.value,
  });
}

/// 档位预设列表（顺序即界面顺序；首个为默认档 = 现网行为）。
const List<DiagnosisTemperaturePreset> diagnosisTemperaturePresets = [
  DiagnosisTemperaturePreset(
    key: diagnosisTempFlexible,
    label: '灵活',
    hint: '诊断视角更发散：同一篇稿子多次诊断，可能侧重不同侧面的问题',
    value: 0.7,
  ),
  DiagnosisTemperaturePreset(
    key: diagnosisTempSteady,
    label: '保守',
    hint: '诊断更聚焦：同一篇稿子多次诊断，结果更一致',
    value: 0.3,
  ),
];

/// key → 预设（未命中 / null 回退灵活档 = 现网行为，保证旧数据与前向兼容）。
DiagnosisTemperaturePreset diagnosisTemperatureOf(String? key) {
  for (final preset in diagnosisTemperaturePresets) {
    if (preset.key == key) return preset;
  }
  return diagnosisTemperaturePresets.first;
}

/// 档位 key → merge 段温度覆盖值（诊断 runner 传给
/// runProgressiveDiagnosis.mergeTemperature）。
///
/// 灵活档返回 **null**：调用方不产 extraBody 键 ⇒ merge 请求体与改造前
/// **逐字节不变**；保守档返回 0.3（经 extraBody 覆盖骨架 temperature）。
/// null 存储值 / 未知 key 归一为灵活档 ⇒ 同为 null。
double? mergeTemperatureFor(String? key) {
  final preset = diagnosisTemperatureOf(key);
  return preset.key == diagnosisTempFlexible ? null : preset.value;
}
