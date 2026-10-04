// ─────────────────────────────────────────────────────────────
// custom_coach_persona_dedup_test — 自定义教练名称查重（ADR-C132 批3 · E）
//
// 背景：`AppStateRepository.saveCustomCoachPersona` 在批3 新增「同名拦截」——
//   名称（trim 后）与**其他**自定义人格同名时抛
//   [DuplicateCoachPersonaNameException]。此前该异常在整个 test/ 零引用
//   （grep 实证），属「产品代码已交付但零行为证据」的假绿形态，故补本文件。
//
// 覆盖（对应 ADR-C132 E 项 + UI 捕获分支）：
//   #1 同名新建 → 抛 DuplicateCoachPersonaNameException，且**未落库**
//      （拦截发生在写入前，库里仍是原那条）
//   #2 异常类型正确（isA，而非笼统的 Exception），且携带重复名
//   #3 编辑自身（同 id）保留同名 → **不拦**（upsert 语义）
//   #4 名称 trim 后才比较：' 毒舌编辑 ' 与 '毒舌编辑' 视为同名 → 拦
//   #5 空名不参与查重：两条空名都能各自落库（空名回退默认语气，与查重正交）
//   #6 不同名 → 正常落库（对照组，证明查重不误伤）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/teaching_types.dart';

CoachPersona _persona({
  required String id,
  required String name,
  String fragment = '',
}) {
  return CoachPersona(
    id: id,
    name: name,
    label: '测试简介',
    isSystem: false,
    attitudeLevel: AttitudeLevel.gentle,
    systemPromptFragment: fragment,
  );
}

void main() {
  late AppDatabase db;
  late AppStateRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppStateRepository(db);
  });

  tearDown(() => db.close());

  test('#1 同名新建 → 抛异常且未落库（库中仍是原那条）', () async {
    await repo.saveCustomCoachPersona(_persona(id: 'a1', name: '毒舌编辑'));

    // 另一个 id、同名 → 必须被拦
    await expectLater(
      repo.saveCustomCoachPersona(_persona(id: 'a2', name: '毒舌编辑')),
      throwsA(isA<DuplicateCoachPersonaNameException>()),
    );

    // 拦截发生在写入前：库里仍只有 a1
    final all = await repo.getCustomCoachPersonas();
    expect(all, hasLength(1));
    expect(all.single.id, 'a1');
  });

  test('#2 异常携带重复名（UI 据此提示）', () async {
    await repo.saveCustomCoachPersona(_persona(id: 'a1', name: '毒舌编辑'));

    Object? caught;
    try {
      await repo.saveCustomCoachPersona(_persona(id: 'a2', name: '毒舌编辑'));
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<DuplicateCoachPersonaNameException>());
    expect((caught as DuplicateCoachPersonaNameException).name, '毒舌编辑');
  });

  test('#3 编辑自身（同 id）保留同名 → 不拦，正常 upsert', () async {
    await repo.saveCustomCoachPersona(_persona(id: 'a1', name: '毒舌编辑'));

    // 同 id、同名（仅改语气段）→ 不抛，且原地更新
    await repo.saveCustomCoachPersona(
      _persona(id: 'a1', name: '毒舌编辑', fragment: '更新后的语气'),
    );

    final all = await repo.getCustomCoachPersonas();
    expect(all, hasLength(1));
    expect(all.single.systemPromptFragment, '更新后的语气');
  });

  test('#4 名称 trim 后比较：首尾空格的同名仍判重', () async {
    await repo.saveCustomCoachPersona(_persona(id: 'a1', name: '毒舌编辑'));

    // ' 毒舌编辑 ' trim 后 == '毒舌编辑' ⇒ 拦
    await expectLater(
      repo.saveCustomCoachPersona(_persona(id: 'a2', name: ' 毒舌编辑 ')),
      throwsA(isA<DuplicateCoachPersonaNameException>()),
    );
    expect(await repo.getCustomCoachPersonas(), hasLength(1));
  });

  test('#5 空名不参与查重：两条空名人格均可落库', () async {
    // 空名与查重正交（空名回退默认语气，由 UI 层保证「名称必填」）。
    // 仓库层对空名跳过查重循环，两条空名都应能存。
    await repo.saveCustomCoachPersona(_persona(id: 'a1', name: ''));
    await repo.saveCustomCoachPersona(_persona(id: 'a2', name: ''));

    final all = await repo.getCustomCoachPersonas();
    expect(all, hasLength(2), reason: '空名不查重，两条空名互不冲突');
  });

  test('#6 不同名 → 正常落库（对照组）', () async {
    await repo.saveCustomCoachPersona(_persona(id: 'a1', name: '毒舌编辑'));
    await repo.saveCustomCoachPersona(_persona(id: 'a2', name: '温柔教练'));

    final all = await repo.getCustomCoachPersonas();
    expect(all.map((p) => p.name).toSet(), {'毒舌编辑', '温柔教练'});
  });
}
