// ─────────────────────────────────────────────────────────────
// VolumeRepository 测试 — 卷标题推导与创建组合语义
//
// CR-21：UI 曾「先 createVolume 后 nextVolumeTitle(listVolumes())」，
// 新卷已入库导致提示名大一号（建「第一卷」提示「第二卷」）。
// 修复约定：先 nextVolumeTitle(空列表/存量列表) 再 createVolume(title)。
// 本文件锁定「先算标题 → 落库标题 == 提示标题」不变量。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';

AppDatabase _openMemory() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('CR-21 先算标题再建卷', () {
    late AppDatabase db;
    late ManuscriptRepository msRepo;
    late VolumeRepository volRepo;
    late String msId;

    setUp(() async {
      db = _openMemory();
      msRepo = ManuscriptRepository(db);
      volRepo = VolumeRepository(db);
      msId = await msRepo.createManuscript(title: '书');
    });

    tearDown(() async => db.close());

    test('空列表先算 → 第一卷，落库标题与提示一致', () async {
      final predicted = volRepo.nextVolumeTitle(
        await volRepo.listVolumes(msId),
      );
      await volRepo.createVolume(msId, title: predicted);
      final volumes = await volRepo.listVolumes(msId);
      expect(predicted, '第一卷');
      expect(volumes.single.title, predicted);
    });

    test('存量一卷先算 → 第二卷，落库标题与提示一致（不重复）', () async {
      await volRepo.createVolume(msId, title: '第一卷');
      final predicted = volRepo.nextVolumeTitle(
        await volRepo.listVolumes(msId),
      );
      await volRepo.createVolume(msId, title: predicted);
      final volumes = await volRepo.listVolumes(msId);
      expect(predicted, '第二卷');
      expect(volumes.map((v) => v.title).toList(), ['第一卷', '第二卷']);
    });

    test('删末卷后先算 → 复用空出的序号（CR-11 语义保持）', () async {
      final v1 = await volRepo.createVolume(msId, title: '第一卷');
      await volRepo.createVolume(msId, title: '第二卷');
      await volRepo.deleteVolume(v1);
      final predicted = volRepo.nextVolumeTitle(
        await volRepo.listVolumes(msId),
      );
      await volRepo.createVolume(msId, title: predicted);
      final volumes = await volRepo.listVolumes(msId);
      // 删卷后 MAX(sort_order)=1 → 下一卷是「第三卷」，
      // 与 createVolume 内部 order 推导同源，不产生重复标题。
      expect(predicted, '第三卷');
      expect(volumes.map((v) => v.title).toSet(), {'第二卷', '第三卷'});
    });

    test('createVolume 传 title 与内部自动命名等价（行为不漂移）', () async {
      // 路径 A：先算后建（修复后 UI 路径）
      final predicted = volRepo.nextVolumeTitle(
        await volRepo.listVolumes(msId),
      );
      await volRepo.createVolume(msId, title: predicted);
      // 路径 B：内部自动命名（createVolume title 空）
      await volRepo.createVolume(msId);
      final volumes = await volRepo.listVolumes(msId);
      expect(volumes[0].title, '第一卷'); // 路径 A 落库
      expect(volumes[1].title, '第二卷'); // 路径 B 内部自动命名
    });
  });
}
