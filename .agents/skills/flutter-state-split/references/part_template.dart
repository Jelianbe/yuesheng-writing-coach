// ─────────────────────────────────────────────────────────────
// 大 State 类拆分模板（part of + 私有扩展）
// 复制本文件为真实 part 文件，把宿主里的方法体整段粘进扩展即可。
// 宿主类形如：class _HostState extends ConsumerState<HostWidget> { ... }
// ─────────────────────────────────────────────────────────────
// ignore_for_file: invalid_use_of_protected_member
part of '宿主文件.dart';

extension _HostXxx on _HostState {
  // 原方法体整段贴过来，保留 _ 前缀方法名与私有字段调用。
  // 例：
  // void _handleSomething() {
  //   if (!mounted) return;
  //   setState(() { _count++; });
  //   ref.read(someProvider).doWork();
  // }
}

// ───────────────────── 宿主文件.dart（另一侧） ─────────────────────
//
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// // ... 其它 import
//
// part '宿主文件_xxx.dart';          // ← 新增 part 声明
//
// class _HostState extends ConsumerState<HostWidget> {
//   // 字段、initState、dispose、build() 留在宿主
//   // 被迁走的方法体在这里【删除】，只留签名注释（可选）
// }
