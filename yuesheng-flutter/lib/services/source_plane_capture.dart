// ─────────────────────────────────────────────────────────────
// 源面快照接线（B0c 后半件 · 纯 instrumentation · R-027 零报批）。
//
// 授权：裁点戊「源面落盘归 B0c」（报批单 §四，舰长「都批」）
//   + 报批单 §四.2「L0-b + 源面落盘与 AER 无关，批后即可开工」。
// 语义：诊断发起时把 D2 源面（本章正文 + 会话 user/system 消息）落盘留痕，
//   供 L0-① 锚定闸与 R1 假红率人评对源面复验；D3 的证据源当前无消费通路
//   （报批稿 §1.③ 理由 2）⇒ 留空，绝不拿别处文本冒充设定。
//
// ★ 硬边界（违反即红）：
//   1. 不进任何 prompt / schema / 判据真源，不触诊断结论；
//   2. 失败 / 挂起 / 超限一律吞掉返回 null，绝不阻断或延迟诊断主链；
//   3. 调用点必须 unawaited（平台通道挂起不得拖死诊断，同 B13-1）；
//   4. 不建立诊断记录外键（零 DB 迁移），人评按 createdAt 秒对齐快照。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../data/database/database.dart';
import '../data/repositories/session_repository.dart';
import 'source_plane_snapshot.dart';

/// 会话消息读取器（注入便于单测；生产实现见 [sessionMessageLoader]）。
typedef SourcePlaneMessageLoader = Future<List<SourcePlaneMessage>> Function();

/// 单次落盘的兜底超时（挂起 ≠ 成功，也不许拖住诊断）。
const Duration kSourcePlaneCaptureTimeout = Duration(milliseconds: 500);

/// 生产读取器：把会话表逐行映射成源面消息桩（role 逐字取 wire 值）。
SourcePlaneMessageLoader sessionMessageLoader(
  AppDatabase db,
  String sessionId,
) => () async {
  final rows = await SessionRepository(db).listMessages(sessionId);
  return <SourcePlaneMessage>[
    for (final row in rows)
      SourcePlaneMessage(role: row.role, content: row.content),
  ];
};

/// 诊断源面快照：成功返回快照，任何失败返回 null（调用方 unawaited）。
Future<SourcePlaneSnapshot?> captureDiagnosisSourcePlane({
  required String chapterText,
  required SourcePlaneMessageLoader loader,
  SourcePlaneStore? store,
  Duration timeout = kSourcePlaneCaptureTimeout,
}) async {
  try {
    final messages = await loader().timeout(timeout);
    final snapshot = await (store ?? SourcePlaneStore())
        .save(
          domain: SourcePlaneDomain.d2,
          chapterText: chapterText,
          messages: messages,
        )
        .timeout(timeout);
    debugPrint(
      '[source_plane] snapshot=${snapshot.snapshotId} '
      'domain=${snapshot.domain.name} sha=${snapshot.contentSha}',
    );
    return snapshot;
  } catch (error) {
    debugPrint('[source_plane] 快照落盘失败（诊断主链不受影响）: $error');
    return null;
  }
}
