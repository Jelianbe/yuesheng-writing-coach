// ─────────────────────────────────────────────────────────────
// fact_validator — [YS_FACT] 事实提取块 schema 校验（D4 批次9）
//
// 独立 validator 层（对齐 reviewer/editor/teacher validator 模式）：
//   - 人物/事件/支线三类各自 schema 校验
//   - 宽松策略：非法条目逐条跳过，保留合法条目（保持 parseFactExtraction
//     原有「三类独立解析，一类失败不影响其他」语义，与 outline 严格策略
//     不对称是有意设计，见模块审查包专题 B P1）
// 纯函数，无副作用，不 throw。
// ─────────────────────────────────────────────────────────────

import '../types/character_types.dart';

/// 校验错误
class FactValidationError {
  final String field;
  final String message;
  const FactValidationError({required this.field, required this.message});
}

/// 人物事实更新（对齐 CharacterFactRepository.upsertCharacter）
class CharacterFactUpdate {
  final String name;
  final List<CharacterAssertion> assertions;

  const CharacterFactUpdate({required this.name, required this.assertions});
}

/// 事件事实更新（对齐 EventFactRepository.upsertEvent）
class EventFactUpdate {
  final String name;
  final String eventType;
  final int? chapter;
  final List<String> participants;
  final String description;

  /// 批次3-D4：触发事件名（用名字引用，AI 更易输出）。
  /// 写入时由 chat_service 反查 id 填入 event_fact.cause_event_id。
  /// 为空表示无前因触发（如开篇事件）。
  final String? causeEventName;

  const EventFactUpdate({
    required this.name,
    required this.eventType,
    this.chapter,
    required this.participants,
    required this.description,
    this.causeEventName,
  });
}

/// 支线事实更新（对齐 SubplotFactRepository.upsertSubplot）
class SubplotFactUpdate {
  final String name;
  final int? introducedChapter;
  final int? resolvedChapter;
  final String description;

  const SubplotFactUpdate({
    required this.name,
    this.introducedChapter,
    this.resolvedChapter,
    required this.description,
  });
}

/// 事实提取结果
class FactExtraction {
  final List<CharacterFactUpdate> characters;
  final List<EventFactUpdate> events;
  final List<SubplotFactUpdate> subplots;

  const FactExtraction({
    required this.characters,
    required this.events,
    required this.subplots,
  });

  bool get isEmpty =>
      characters.isEmpty && events.isEmpty && subplots.isEmpty;
}

/// 校验结果
class FactValidationResult {
  final bool valid;
  final List<FactValidationError> errors;
  final FactExtraction? data;
  const FactValidationResult({
    required this.valid,
    required this.errors,
    this.data,
  });
}

/// [YS_FACT] 块 schema 校验（宽松：非法条目逐条跳过，保留合法条目）
///
/// 镜像 fact_parser 原内联解析语义：
///   - 根对象必须有 characters/events/subplots（各自可缺省）
///   - 人物：name 非空 + assertions 数组（内层经 CharacterAssertion.tryFromJson）
///   - 事件：name 非空 + event_type/eventType 非空；chapter/participants/description/cause_event_name 可选
///   - 支线：name 非空；introduced/resolved chapter 可选（支持 snake/camel 双键）
///   - 三类全空 → invalid（data=null）
FactValidationResult validateFactSchema(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    return FactValidationResult(
      valid: false,
      errors: const [
        FactValidationError(field: '<root>', message: '必须是 JSON 对象'),
      ],
    );
  }

  final errors = <FactValidationError>[];
  final characters = _parseCharacters(raw['characters'], errors);
  final events = _parseEvents(raw['events'], errors);
  final subplots = _parseSubplots(raw['subplots'], errors);

  if (characters.isEmpty && events.isEmpty && subplots.isEmpty) {
    return FactValidationResult(valid: false, errors: errors, data: null);
  }

  return FactValidationResult(
    valid: true,
    errors: errors,
    data: FactExtraction(
      characters: characters,
      events: events,
      subplots: subplots,
    ),
  );
}

List<CharacterFactUpdate> _parseCharacters(
  dynamic raw,
  List<FactValidationError> errors,
) {
  if (raw is! List) return const [];
  final result = <CharacterFactUpdate>[];
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c is! Map<String, dynamic>) {
      errors.add(FactValidationError(field: 'characters[$i]', message: '必须是对象'));
      continue;
    }
    final name = c['name'];
    if (name is! String || name.trim().isEmpty) {
      errors.add(
        FactValidationError(field: 'characters[$i].name', message: '必须为非空字符串'),
      );
      continue;
    }
    final assertionsRaw = c['assertions'];
    if (assertionsRaw is! List) {
      errors.add(
        FactValidationError(field: 'characters[$i].assertions', message: '必须是数组'),
      );
      continue;
    }
    final assertions = <CharacterAssertion>[];
    for (final a in assertionsRaw) {
      if (a is! Map<String, dynamic>) continue;
      final assertion = CharacterAssertion.tryFromJson(a);
      if (assertion != null) assertions.add(assertion);
    }
    if (assertions.isNotEmpty) {
      result.add(CharacterFactUpdate(name: name, assertions: assertions));
    } else {
      errors.add(
        FactValidationError(
          field: 'characters[$i].assertions',
          message: '没有任何合法断言',
        ),
      );
    }
  }
  return result;
}

List<EventFactUpdate> _parseEvents(
  dynamic raw,
  List<FactValidationError> errors,
) {
  if (raw is! List) return const [];
  final result = <EventFactUpdate>[];
  for (var i = 0; i < raw.length; i++) {
    final e = raw[i];
    if (e is! Map<String, dynamic>) {
      errors.add(FactValidationError(field: 'events[$i]', message: '必须是对象'));
      continue;
    }
    final name = e['name'];
    if (name is! String || name.trim().isEmpty) {
      errors.add(
        FactValidationError(field: 'events[$i].name', message: '必须为非空字符串'),
      );
      continue;
    }
    final eventType = e['event_type'] ?? e['eventType'];
    if (eventType is! String || eventType.trim().isEmpty) {
      errors.add(
        FactValidationError(
          field: 'events[$i].event_type',
          message: '必须为非空字符串（支持 event_type/eventType 双键）',
        ),
      );
      continue;
    }
    final chapter = (e['chapter'] as num?)?.toInt();
    final participantsRaw = e['participants'];
    final participants = participantsRaw is List
        ? participantsRaw.whereType<String>().where((p) => p.isNotEmpty).toList()
        : const <String>[];
    final description = (e['description'] as String?) ?? '';
    // 批次3-D4：解析触发事件名（支持 cause_event_name / causeEventName 两种键）
    final causeEventName =
        (e['cause_event_name'] as String? ?? e['causeEventName'] as String?)
            ?.trim();
    final cause = (causeEventName?.isEmpty ?? true) ? null : causeEventName;

    result.add(
      EventFactUpdate(
        name: name,
        eventType: eventType,
        chapter: chapter,
        participants: participants,
        description: description,
        causeEventName: cause,
      ),
    );
  }
  return result;
}

List<SubplotFactUpdate> _parseSubplots(
  dynamic raw,
  List<FactValidationError> errors,
) {
  if (raw is! List) return const [];
  final result = <SubplotFactUpdate>[];
  for (var i = 0; i < raw.length; i++) {
    final s = raw[i];
    if (s is! Map<String, dynamic>) {
      errors.add(FactValidationError(field: 'subplots[$i]', message: '必须是对象'));
      continue;
    }
    final name = s['name'];
    if (name is! String || name.trim().isEmpty) {
      errors.add(
        FactValidationError(field: 'subplots[$i].name', message: '必须为非空字符串'),
      );
      continue;
    }
    final introduced = (s['introduced_chapter'] as num?)?.toInt() ??
        (s['introducedChapter'] as num?)?.toInt();
    final resolved = (s['resolved_chapter'] as num?)?.toInt() ??
        (s['resolvedChapter'] as num?)?.toInt();
    final description = (s['description'] as String?) ?? '';

    result.add(
      SubplotFactUpdate(
        name: name,
        introducedChapter: introduced,
        resolvedChapter: resolved,
        description: description,
      ),
    );
  }
  return result;
}
