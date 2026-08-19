// ─────────────────────────────────────────────────────────────
// 契约测试 — 引用能力
//
// 验证 ReferenceCapability 接口与实现（ReferenceRepository）的满足关系。
// 依赖倒置：ReferenceRepository 直接 implements ReferenceCapability，
// 方法签名一致性由 dart analyze（门禁 1）保证；本测试做编译期子类型断言 + 注册表断言。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/reference_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';

// 编译期子类型断言：若 ReferenceRepository 未正确 implements ReferenceCapability，
// 本文件无法通过 dart analyze（门禁 1）。运行期无需实例化（避免依赖 DB）。
ReferenceCapability _referenceImplIsCapability(ReferenceRepository repo) => repo;

void main() {
  group('ReferenceCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(ReferenceCapability),
      );
    });

    test('ReferencedItem 字段与契约一致', () {
      const item = ReferencedItem(
        refId: 'r1',
        refType: 'chapter',
        isPrimary: 1,
        title: '第一章',
        manuscriptId: 'm1',
        excerptRange: '{"chapterId":"ch1","startPara":1,"endPara":2}',
      );
      expect(item.refId, 'r1');
      expect(item.refType, 'chapter');
      expect(item.isPrimary, 1);
      expect(item.title, '第一章');
      expect(item.manuscriptId, 'm1');
      expect(item.excerptRange, isNotNull);
    });

    test('ReferenceRepository 编译期满足 ReferenceCapability', () {
      // 经 _referenceImplIsCapability 的类型签名保证 implements 成立。
      expect(_referenceImplIsCapability, isA<Function>());
    });
  });
}
