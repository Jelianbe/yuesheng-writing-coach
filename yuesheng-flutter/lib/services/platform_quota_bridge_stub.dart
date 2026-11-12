// platform_quota_bridge_stub.dart — 非 web 平台的空实现（条件导入的兜底支）
//
// 【为什么必须有这一支】`platform_quota_bridge_web.dart` 依赖
//   `dart:js_interop`，该库只在 web 编译目标下存在；Android 构建若解析到
//   那一支会直接编译失败。
//
// 【为什么返回 null 而不是「一个不可用的实现」】
//   手机端恒 BYOK（`T-20261112-01` 边界：不动手机端、不让移动流量绑额度）。
//   返回 null ⇒ `LlmClient` 走**接入前的老路**（离线示例文案）
//   ⇒ A3「手机端零变更」不是靠 if 判断保证，而是「这条通道在手机端根本不存在」。
//   若返回「存在但不可用」的空实现，将来一处漏判就会把手机端行为改掉。

import 'platform_quota_channel.dart';

/// 非 web：无平台资源点通道。
PlatformQuotaChannel? createPlatformQuotaChannel() => null;
