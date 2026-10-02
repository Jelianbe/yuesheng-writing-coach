// coach_persona_injection_test — D1/D2 Phase 2 注入切换语义（选人卡 → ChatService → prompt）
//
// 覆盖三条关键契约：
//   1. 用户自定义人格激活 → 注入其 systemPromptFragment，替换默认态度档位，
//      loadedIds 记 persona-<id>，且不再出现 attitude-* 内容。
//   2. 系统预设 / 无激活人格 → 走原 attitude-* 路径（快照锁守护，逐字节不变）。
//   3. resolveActiveCoachPersona 纯函数解析规则（系统预设优先 → 用户自定义 → 回退 doubao）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/coach_persona_seed.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:drift/native.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';

void main() {
  const userPersona = CoachPersona(
    id: 'custom_1',
    name: '毒舌大师兄',
    label: '一针见血，专挑毛病',
    isSystem: false,
    attitudeLevel: AttitudeLevel.sensei,
    systemPromptFragment: '你是用户的毒舌大师兄，说话带刺但句句在理，绝不留情面。',
  );

  SkillLoadContext ctx({
    AttitudeLevel attitude = AttitudeLevel.doubao,
    CoachPersona? activePersona,
  }) => SkillLoadContext(
    phase: TeachingPhase.p2PracticeLoop,
    attitude: attitude,
    subphase: TeachingSubphase.diagnosis,
    activePersona: activePersona,
  );

  group('Phase 2 · 用户自定义人格注入', () {
    test('#B1 注入用户 fragment、替换态度档、loadedIds 记 persona-<id>', () {
      final r = buildSystemPromptV2(ctx(activePersona: userPersona));

      expect(r.systemPrompt, contains('毒舌大师兄'));
      expect(r.systemPrompt, contains('说话带刺但句句在理'));
      // 态度档被替换：不再出现默认 attitude-doubao 的声明
      expect(r.systemPrompt, isNot(contains('态度：豆包')));
      expect(r.loadedSkillIds, contains('persona-custom_1'));
      expect(r.loadedSkillIds, isNot(contains('attitude-doubao')));
    });

    test('#B2 空 fragment 的用户人格不注入（防御性跳过，走原路径）', () {
      const emptyFrag = CoachPersona(
        id: 'custom_2',
        name: '空嗓门',
        label: '没写语气',
        isSystem: false,
        attitudeLevel: AttitudeLevel.doubao,
        systemPromptFragment: '   ',
      );
      final r = buildSystemPromptV2(ctx(activePersona: emptyFrag));
      // 空格 fragment trim 后为空 → 回退默认态度档
      expect(r.systemPrompt, contains('态度：豆包'));
      expect(r.loadedSkillIds, isNot(contains('persona-custom_2')));
    });
  });

  group('Phase 2 · 系统预设 / 无激活人格（快照零漂移护栏）', () {
    test('#C1 无 activePersona → 原 attitude-* 路径', () {
      final r = buildSystemPromptV2(ctx());
      expect(r.systemPrompt, contains('态度：豆包'));
      expect(r.loadedSkillIds, contains('attitude-doubao'));
      expect(r.loadedSkillIds, isNot(contains('persona-')));
    });

    test('#C2 系统预设激活（isSystem=true）→ 仍走 attitude-*，不注入 fragment', () {
      final system = builtInCoachPersonas.first; // doubao，isSystem=true
      final r = buildSystemPromptV2(ctx(activePersona: system));
      // 系统预设即便带上 fragment，也绝不替换态度档（快照锁守护的路径不动）
      expect(r.systemPrompt, contains('态度：豆包'));
      expect(r.loadedSkillIds, contains('attitude-doubao'));
      expect(r.loadedSkillIds, isNot(contains('persona-doubao')));
    });
  });

  group('Phase 2 · D2 人设层叠加注入', () {
    const layeredPersona = CoachPersona(
      id: 'custom_layer_1',
      name: '文学编辑',
      label: '沉稳讲究',
      isSystem: false,
      attitudeLevel: AttitudeLevel.yuesheng,
      systemPromptFragment: '你是用户的写作陪练，语气沉稳。',
      personaLayer: '以资深文学编辑口吻说话，多用比喻，少用术语。',
    );

    test('#E1 用户人格带 personaLayer → 叠加注入（fragment + layer 都在，含顺序）', () {
      final r = buildSystemPromptV2(ctx(activePersona: layeredPersona));

      expect(r.systemPrompt, contains('你是用户的写作陪练，语气沉稳。'));
      expect(r.systemPrompt, contains('以资深文学编辑口吻说话，多用比喻，少用术语。'));
      // 人设层紧随基础语气之后（fragment 索引 < layer 索引）
      final fragIdx = r.systemPrompt.indexOf('语气沉稳');
      final layerIdx = r.systemPrompt.indexOf('资深文学编辑口吻');
      expect(layerIdx, greaterThan(fragIdx));
      // 态度档被替换
      expect(r.systemPrompt, isNot(contains('态度：豆包')));
      expect(r.loadedSkillIds, contains('persona-custom_layer_1'));
      expect(r.loadedSkillIds, contains('persona-layer-custom_layer_1'));
    });

    test('#E2 无 personaLayer（null）→ 只注入基础语气，无 persona-layer 标记', () {
      final r = buildSystemPromptV2(
        ctx(activePersona: userPersona),
      ); // userPersona 无 layer
      expect(r.systemPrompt, contains('毒舌大师兄'));
      expect(r.loadedSkillIds, contains('persona-custom_1'));
      expect(r.loadedSkillIds, isNot(contains('persona-layer-')));
    });

    test('#E3 空字符串 personaLayer → 按无 layer 处理', () {
      const blankLayer = CoachPersona(
        id: 'custom_blank_layer',
        name: '无层',
        label: '只有基础语气',
        isSystem: false,
        attitudeLevel: AttitudeLevel.doubao,
        systemPromptFragment: '你是基础语气。',
        personaLayer: '   ',
      );
      final r = buildSystemPromptV2(ctx(activePersona: blankLayer));
      expect(r.systemPrompt, contains('你是基础语气。'));
      expect(r.loadedSkillIds, contains('persona-custom_blank_layer'));
      expect(
        r.loadedSkillIds,
        isNot(contains('persona-layer-custom_blank_layer')),
      );
    });
  });

  group('ADR-C132 批2 · 结构化约束 + R-009 边界句（用户预设路径）', () {
    const constrainedPersona = CoachPersona(
      id: 'custom_constrained_1',
      name: '克制教练',
      label: '结构化约束样例',
      isSystem: false,
      attitudeLevel: AttitudeLevel.yuesheng,
      systemPromptFragment: '你是用户的写作陪练，语气沉稳。',
      expressionDensity: 'low',
      questionPreference: 'direct',
      bufferWordPreference: 'none',
      emojiAllowed: false,
    );

    test('#F1 带结构化字段 → 约束块注入（各字段逐条可见）+ loadedIds', () {
      final r = buildSystemPromptV2(ctx(activePersona: constrainedPersona));

      expect(r.systemPrompt, contains('表达密度：简洁克制'));
      expect(r.systemPrompt, contains('提问直给偏好：倾向直接指出问题'));
      expect(r.systemPrompt, contains('缓冲词偏好：避免使用'));
      expect(r.systemPrompt, contains('emoji：不使用'));
      expect(
        r.loadedSkillIds,
        contains('persona-constraints-custom_constrained_1'),
      );
      expect(r.loadedSkillIds, isNot(contains('attitude-yuesheng')));
    });

    test('#F2 边界句无条件附加（无结构化字段也注入）+ loadedIds', () {
      final r = buildSystemPromptV2(ctx(activePersona: userPersona));

      expect(r.systemPrompt, contains('【人格红线】'));
      expect(r.systemPrompt, contains('不替学员写句子、不替学员做决定'));
      expect(r.loadedSkillIds, contains('persona-redline-custom_1'));
    });

    test('#F3 全空字段 → 无约束块但仍有边界句', () {
      const plain = CoachPersona(
        id: 'custom_plain_1',
        name: '无约束',
        label: '没有结构化字段',
        isSystem: false,
        attitudeLevel: AttitudeLevel.doubao,
        systemPromptFragment: '你是基础语气。',
      );
      final r = buildSystemPromptV2(ctx(activePersona: plain));

      expect(r.systemPrompt, isNot(contains('表达密度：')));
      expect(r.systemPrompt, isNot(contains('提问直给偏好：')));
      expect(r.systemPrompt, contains('【人格红线】'));
      expect(
        r.loadedSkillIds,
        isNot(contains('persona-constraints-custom_plain_1')),
      );
      expect(r.loadedSkillIds, contains('persona-redline-custom_plain_1'));
    });

    test('#F4 注入顺序：fragment < layer < 约束块 < 边界句', () {
      const layered = CoachPersona(
        id: 'custom_order_1',
        name: '顺序样本',
        label: '验证块顺序',
        isSystem: false,
        attitudeLevel: AttitudeLevel.sensei,
        systemPromptFragment: '你是顺序样本。',
        personaLayer: '人设层文本。',
        expressionDensity: 'high',
      );
      final r = buildSystemPromptV2(ctx(activePersona: layered));

      final fragIdx = r.systemPrompt.indexOf('顺序样本');
      final layerIdx = r.systemPrompt.indexOf('人设层文本');
      final constraintsIdx = r.systemPrompt.indexOf('表达密度：可以铺陈充分');
      final redlineIdx = r.systemPrompt.indexOf('【人格红线】');
      expect(fragIdx, lessThan(layerIdx));
      expect(layerIdx, lessThan(constraintsIdx));
      expect(constraintsIdx, lessThan(redlineIdx));
    });

    test('#F5 系统预设路径零漂移：不注入约束块与边界句', () {
      final system = builtInCoachPersonas.first; // doubao，isSystem=true
      final r = buildSystemPromptV2(ctx(activePersona: system));

      expect(r.systemPrompt, isNot(contains('表达密度：')));
      expect(r.systemPrompt, isNot(contains('【人格红线】')));
      expect(r.loadedSkillIds, isNot(contains('persona-constraints-')));
      expect(r.loadedSkillIds, isNot(contains('persona-redline-')));
    });
  });

  group('resolveActiveCoachPersona 纯函数解析', () {
    const custom = CoachPersona(
      id: 'custom_9',
      name: '自定义',
      label: '自定义语气',
      isSystem: false,
      attitudeLevel: AttitudeLevel.yuesheng,
      systemPromptFragment: '自定义片段',
    );

    test('#D1 系统预设 id → 命中系统预设', () {
      final r = resolveActiveCoachPersona('sensei', const [custom]);
      expect(r.isSystem, isTrue);
      expect(r.id, 'sensei');
    });

    test('#D2 用户自定义 id → 命中自定义', () {
      final r = resolveActiveCoachPersona('custom_9', const [custom]);
      expect(r.isSystem, isFalse);
      expect(r.id, 'custom_9');
    });

    test('#D3 两者都找不到 → 回退系统预设 doubao', () {
      final r = resolveActiveCoachPersona('ghost', const [custom]);
      expect(r.isSystem, isTrue);
      expect(r.id, 'doubao');
    });
  });

  group('A6 态度档/教练人格单一真源（coach_persona_active）', () {
    test(
      '头部切档走 setActiveCoachPersona，读取端 getActiveCoachPersonaId 一致',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = AppStateRepository(db);

        await repo.setActiveCoachPersona('yuesheng');
        expect(await repo.getActiveCoachPersonaId(), 'yuesheng');

        await repo.setActiveCoachPersona('sensei');
        expect(await repo.getActiveCoachPersonaId(), 'sensei');
      },
    );

    test('迁移兼容：老用户只写过 coach_attitude，读取回退到它（不丢配置）', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = AppStateRepository(db);

      await repo.setCoachAttitude('doubao');
      expect(
        await repo.getActiveCoachPersonaId(),
        'doubao',
        reason: 'coach_persona_active 为空时应回退到旧 key，老配置不丢',
      );
    });

    test('消除双真源：写 active 后旧 coach_attitude 不再影响读取；头部切档覆盖 active', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = AppStateRepository(db);

      // 教练设置里选过人格（写 active）
      await repo.setActiveCoachPersona('custom_abc');
      // 修前 bug 路径：头部只写 coach_attitude（不动 active）
      await repo.setCoachAttitude('doubao');
      // 读取端必须仍是 custom_abc（这正是修前「头部切档 UI 变了但语气没变」的根因）
      expect(await repo.getActiveCoachPersonaId(), 'custom_abc');

      // 修后头部切档改走 setActiveCoachPersona ⇒ 同步覆盖 active，两端一致
      await repo.setActiveCoachPersona('yuesheng');
      expect(await repo.getActiveCoachPersonaId(), 'yuesheng');
      expect(
        await repo.getCoachAttitude(),
        'yuesheng',
        reason: '系统预设应双写 coach_attitude 保持旧读取路径兼容',
      );
    });
  });
}
