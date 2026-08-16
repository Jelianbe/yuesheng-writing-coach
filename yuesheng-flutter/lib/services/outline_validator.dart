// ─────────────────────────────────────────────────────────────
// outline_validator — [YS_ENTITY] 大纲提取块 schema 校验（D4 批次9）
//
// 独立 validator 层（对齐 reviewer/editor/teacher validator 模式）：
//   - schema 白名单：type ∈ character/setting/plot
//   - 字段校验：key/aliases/matched_entity_id/impressions 逐字段
//   - 严格策略：任一实体非法 → 整体 invalid（保持 parseOutlineExtraction
//     原有「任一非法整体 null」语义，防错关联；与 fact 的逐条隔离不对称
//     是有意设计，见模块审查包专题 B P1）
// 纯函数，无副作用，不 throw。
// ─────────────────────────────────────────────────────────────

/// 实体类型白名单
const List<String> kValidEntityTypes = ['character', 'setting', 'plot'];

/// 校验错误
class OutlineValidationError {
  final String field;
  final String message;
  const OutlineValidationError({required this.field, required this.message});
}

/// 单条印象更新
class OutlineImpressionUpdate {
  final String text; // 印象/梗概片段
  final String? conflictWith; // 指向已有印象 id（AI 标注矛盾，可能幻觉，调用方校验）

  const OutlineImpressionUpdate({required this.text, this.conflictWith});
}

/// 单个实体更新
class OutlineEntityUpdate {
  final String type; // character | setting | plot
  final String key; // 规范名
  final List<String> aliases; // 别名表
  final String? matchedEntityId; // 命中已有实体 id；null = 新建
  final List<OutlineImpressionUpdate> impressions;

  const OutlineEntityUpdate({
    required this.type,
    required this.key,
    required this.aliases,
    this.matchedEntityId,
    required this.impressions,
  });
}

/// 大纲提取结果
class OutlineExtraction {
  final List<OutlineEntityUpdate> entities;
  const OutlineExtraction({required this.entities});
}

/// 校验结果
class OutlineValidationResult {
  final bool valid;
  final List<OutlineValidationError> errors;
  final OutlineExtraction? data;
  const OutlineValidationResult({
    required this.valid,
    required this.errors,
    this.data,
  });
}

/// [YS_ENTITY] 块 schema 校验（严格：任一实体非法 → 整体 invalid）
///
/// 镜像 outline_parser 原内联校验语义：
///   - 根对象必须有 entities 数组（允许空数组 → valid）
///   - type 必须在白名单；key 非空；matched_entity_id 为字符串或 null
///   - impressions 数组；text 非空；conflict_with 为字符串或 null
OutlineValidationResult validateOutlineSchema(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    return OutlineValidationResult(
      valid: false,
      errors: const [
        OutlineValidationError(field: '<root>', message: '必须是 JSON 对象'),
      ],
    );
  }

  final entitiesRaw = raw['entities'];
  if (entitiesRaw is! List) {
    return OutlineValidationResult(
      valid: false,
      errors: const [
        OutlineValidationError(field: 'entities', message: '必须是数组'),
      ],
    );
  }

  final errors = <OutlineValidationError>[];
  final entities = <OutlineEntityUpdate>[];

  for (var i = 0; i < entitiesRaw.length; i++) {
    final e = entitiesRaw[i];
    if (e is! Map<String, dynamic>) {
      errors.add(
        OutlineValidationError(
          field: 'entities[$i]',
          message: '必须是对象',
        ),
      );
      continue;
    }

    final type = e['type'];
    if (type is! String || !kValidEntityTypes.contains(type)) {
      errors.add(
        OutlineValidationError(
          field: 'entities[$i].type',
          message: '必须为 character/setting/plot（实际: $type）',
        ),
      );
      continue;
    }

    final key = e['key'];
    if (key is! String || key.trim().isEmpty) {
      errors.add(
        OutlineValidationError(
          field: 'entities[$i].key',
          message: '必须为非空字符串',
        ),
      );
      continue;
    }

    final aliasesRaw = e['aliases'];
    final aliases = aliasesRaw is List
        ? aliasesRaw.whereType<String>().where((a) => a.isNotEmpty).toList()
        : const <String>[];

    final matchedEntityId = e['matched_entity_id'];
    if (matchedEntityId != null && matchedEntityId is! String) {
      errors.add(
        OutlineValidationError(
          field: 'entities[$i].matched_entity_id',
          message: '必须是字符串或 null',
        ),
      );
      continue;
    }

    final impressionsRaw = e['impressions'];
    if (impressionsRaw is! List) {
      errors.add(
        OutlineValidationError(
          field: 'entities[$i].impressions',
          message: '必须是数组',
        ),
      );
      continue;
    }

    final impressions = <OutlineImpressionUpdate>[];
    for (var j = 0; j < impressionsRaw.length; j++) {
      final im = impressionsRaw[j];
      if (im is! Map<String, dynamic>) {
        errors.add(
          OutlineValidationError(
            field: 'entities[$i].impressions[$j]',
            message: '必须是对象',
          ),
        );
        continue;
      }

      final text = im['text'];
      if (text is! String || text.trim().isEmpty) {
        errors.add(
          OutlineValidationError(
            field: 'entities[$i].impressions[$j].text',
            message: '必须为非空字符串',
          ),
        );
        continue;
      }

      final conflictWith = im['conflict_with'];
      if (conflictWith != null && conflictWith is! String) {
        errors.add(
          OutlineValidationError(
            field: 'entities[$i].impressions[$j].conflict_with',
            message: '必须是字符串或 null',
          ),
        );
        continue;
      }

      impressions.add(
        OutlineImpressionUpdate(
          text: text,
          conflictWith: conflictWith as String?,
        ),
      );
    }

    entities.add(
      OutlineEntityUpdate(
        type: type,
        key: key,
        aliases: aliases,
        matchedEntityId: matchedEntityId as String?,
        impressions: impressions,
      ),
    );
  }

  return OutlineValidationResult(
    valid: errors.isEmpty,
    errors: errors,
    data: errors.isEmpty ? OutlineExtraction(entities: entities) : null,
  );
}
