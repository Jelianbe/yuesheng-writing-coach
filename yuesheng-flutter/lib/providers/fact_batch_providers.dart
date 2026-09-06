// ─────────────────────────────────────────────────────────────
// FactBatchProviders — FR-10 批次沉淀提示的内存态注册表（C78 批次3）
//
// 舰长裁决（ADR-C78 冲突 C，方案 C1）：**内存态，不落库**——
//   messageId → 本轮沉淀条数，渲染为消息尾部系统提示卡；
//   重启后卡片自然消失（「最近批次」语义本就是 transient，如实标注，
//   不伪装成持久；角色页「最近批次」视图仍可按断言 timestamp 过滤）。
//
// 服务层（DiagnosisFlowHandler）经 onFactBatch 回调写入本注册表——
// 服务层不 import Riverpod，依赖方向 services → 本文件为零；
// UI（MessageList）watch 本表决定是否在消息尾部渲染提示卡。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 服务层 → 注册表 的写入回调签名（依赖倒置接缝）
typedef OnFactBatch =
    void Function({
      required String messageId,
      required int count,
      required String? manuscriptId,
    });

/// 一条批次提示卡的注册记录
class FactBatchRecord {
  /// 本轮新增的人物断言条数（净新增：重抽去重不计）
  final int count;

  /// 所属作品（提示卡点入角色页的上下文）
  final String? manuscriptId;

  /// 注册时刻（unix 秒）——点入角色页后作为「最近批次」过滤起点
  final int at;

  const FactBatchRecord({
    required this.count,
    required this.manuscriptId,
    required this.at,
  });
}

/// 内存态注册表：messageId → FactBatchRecord
class FactBatchRegistry extends Notifier<Map<String, FactBatchRecord>> {
  @override
  Map<String, FactBatchRecord> build() => const {};

  /// 诊断落库完成后登记（同 messageId 重复登记以最新为准）
  void register({
    required String messageId,
    required int count,
    required String? manuscriptId,
  }) {
    if (count <= 0) return;
    state = {
      ...state,
      messageId: FactBatchRecord(
        count: count,
        manuscriptId: manuscriptId,
        at: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    };
  }
}

final factBatchProvider =
    NotifierProvider<FactBatchRegistry, Map<String, FactBatchRecord>>(
      FactBatchRegistry.new,
    );
