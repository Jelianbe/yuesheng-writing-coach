// ─────────────────────────────────────────────────────────────
// drift 表定义 — 严格复刻 yuesheng-android 的 SQLite schema
// 共 14 张表：SCHEMA_V1 内 11 张 + attached_files(v5)
//            + teacher_suggestion(v8) + editor_observation(v9)
// 所有时间戳存 unix 秒（INTEGER + unixepoch() 默认值）
// 所有 JSON 字段存 TEXT（DAO 层手动 parse/stringify）
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

/// ============================================================
/// 1. manuscripts — 作品
/// v25：tags 列（批次94-5 标签落库，JSON string[]）
/// ============================================================
@DataClassName('Manuscript')
class Manuscripts extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get genre => text().withDefault(const Constant(''))();
  TextColumn get language => text().withDefault(const Constant('中文'))();
  TextColumn get status => text()
      .withDefault(const Constant('active'))
      .check(status.isIn(const ['active', 'archived']))();
  // 批次94-5：作品标签（JSON string[]，DAO 层 parse/stringify）
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 2. chapters — 章节（SCHEMA_V1 + v2 last_diagnosed_at + v7 previous_content + v23 volume_id）
/// v24：status CHECK 扩 'archived'（批次94-2 章节回收站软删）
/// ============================================================
@DataClassName('Chapter')
class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  // 批次89：卷归属（可空 = 未分卷；删卷时 SET NULL 回未分卷）
  TextColumn get volumeId =>
      text().nullable().references(Volumes, #id, onDelete: KeyAction.setNull)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get previousContent => text().nullable()(); // v7 新增
  IntColumn get wordCount => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get status => text()
      .withDefault(const Constant('draft'))
      .check(
        status.isIn(const ['draft', 'revising', 'complete', 'archived']),
      )();
  IntColumn get lastDiagnosedAt => integer().nullable()(); // v2 新增
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 2.5 volumes — 卷（批次89 卷分组，v23 新增）
/// 卷内章节顺序仍由 chapters.sort_order 决定（同卷内连续）
/// ============================================================
@DataClassName('Volume')
class Volumes extends Table {
  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 3. sessions — 会话
/// manuscript_id/chapter_id 是主引用冗余缓存（ON DELETE SET NULL）
/// ============================================================
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant('新建会话'))();
  TextColumn get preview => text().withDefault(const Constant(''))();
  TextColumn get manuscriptId => text().nullable().references(
    Manuscripts,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get chapterId => text().nullable().references(
    Chapters,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get diagnosisSummary =>
      text().withDefault(const Constant('{}'))(); // JSON
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 4. messages — 消息（+ v3 message_type）
/// ============================================================
@DataClassName('Message')
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get role =>
      text().check(role.isIn(const ['user', 'assistant', 'system']))();
  TextColumn get content => text()();
  IntColumn get timestamp =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  TextColumn get messageType =>
      text().withDefault(const Constant('chat'))(); // v3 新增
  // v22 新增：本消息携带的 @ 引用快照（JSON 数组
  // [{refType, refId, manuscriptId, title}]），用于气泡底部引用徽章展示
  TextColumn get referencesJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 5. diagnosis_results — 诊断结果（+ v11 teaching_focus）
/// message_id 是软引用（无外键），但有 UNIQUE(session_id, message_id)
/// ============================================================
@DataClassName('DiagnosisRow')
class DiagnosisResults extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get messageId => text()(); // 软引用，无外键
  TextColumn get syndromes =>
      text().withDefault(const Constant('[]'))(); // JSON Syndrome[]
  TextColumn get suggestedActions =>
      text().withDefault(const Constant('[]'))(); // JSON string[]
  TextColumn get rootCauseAnalysis => text().nullable()();
  TextColumn get nextFocus => text().nullable()();
  TextColumn get feedbackSummary => text().nullable()();
  RealColumn get confidence => real().withDefault(const Constant(0.0))();
  TextColumn get teachingProgress => text().nullable()(); // JSON
  TextColumn get targetRefType => text().nullable().check(
    targetRefType.isNull() |
        targetRefType.isIn(const ['manuscript', 'chapter']),
  )();
  TextColumn get targetRefId => text().nullable()();
  IntColumn get timestamp =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  TextColumn get currentTeachingFocusId => text().nullable()(); // v11 新增
  TextColumn get focusReason => text().nullable()(); // v11 新增

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, messageId},
  ];
}

/// ============================================================
/// 6. teaching_state — 教学状态（v11 重建扩展 CHECK + v12 beginner_level）
/// session_id UNIQUE（一对一）
/// ============================================================
@DataClassName('TeachingStateRow')
class TeachingState extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().unique().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get currentPhase => text()
      .withDefault(const Constant('P0_ENGAGE'))
      .check(
        currentPhase.isIn(const [
          'P0_ENGAGE',
          'P1_WORLD',
          'P2_PRACTICE_LOOP',
          'P3_TRAINING',
          'P4_REVIEW',
        ]),
      )();
  TextColumn get currentSubphase => text().nullable()();
  TextColumn get attitudeLevel => text().nullable()();
  TextColumn get beginnerLevel => text().nullable().check(
    beginnerLevel.isNull() |
        beginnerLevel.isIn(const [
          'N0_ENGAGE',
          'N1_ELEMENTS',
          'N2_SCENE',
          'N3_DIAGNOSE',
          'N4_INDEPENDENT',
        ]),
  )();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 7. active_problem — 活跃症候（v10/v11 confirmation_status + confirmed_at）
/// UNIQUE(session_id, syndrome_id)
/// 注意：此表无 updated_at 字段（原项目 T-004 修复确认）
/// ============================================================
@DataClassName('ActiveProblem')
class ActiveProblems extends Table {
  @override
  String get tableName => 'active_problem';

  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get syndromeId => text()(); // 软引用
  TextColumn get syndromeName => text().withDefault(const Constant(''))();
  TextColumn get severity => text()
      .withDefault(const Constant('L2'))
      .check(severity.isIn(const ['L1', 'L2', 'L3']))();
  TextColumn get status => text()
      .withDefault(const Constant('active'))
      .check(status.isIn(const ['active', 'resolved']))();
  TextColumn get confirmationStatus => text()
      .withDefault(const Constant('suspected'))
      .check(
        confirmationStatus.isIn(const [
          'suspected',
          'confirmed',
          'rejected',
          'ignored',
        ]),
      )();
  TextColumn get teachingState => text().nullable().check(
    teachingState.isIn(const [
      'identified',
      'in_progress',
      'consolidating',
      'mastered',
    ]),
  )();
  IntColumn get confirmedAt => integer().nullable()();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get resolvedAt => integer().nullable()();
  IntColumn get updatedAt => integer().nullable()(); // v20 批次5（5.3）最后更新时间

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, syndromeId},
  ];
}

/// ============================================================
/// 8. student_model — 学员画像（+ v4 onboarding_data + v13 style_profile）
/// session_id ON DELETE SET NULL（不级联删）
/// ============================================================
@DataClassName('StudentModelRow')
class StudentModels extends Table {
  @override
  String get tableName => 'student_model';

  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.setNull)();
  TextColumn get attitudePreference => text().nullable()();
  TextColumn get teachingHistory =>
      text().withDefault(const Constant('[]'))(); // JSON
  TextColumn get onboardingData => text().nullable()(); // JSON，v4 新增
  TextColumn get styleProfile => text().nullable()(); // JSON，v13 新增（写作风格画像）
  TextColumn get styleFingerprint => text().nullable()(); // JSON，v15 新增（定量指纹）
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 9. session_reference — 对话 ↔ 书/章/素材文件 多对多桥表
/// ref_type CHECK IN ('manuscript','chapter','file')
/// （批次7 D2：v21 重建表扩 CHECK 允许 file 作次引用；file 不可设主，
///  setPrimaryReference 已有 ArgumentError 防御）
/// ref_id 是软引用（跨类型，无外键）
/// ============================================================
@DataClassName('SessionReference')
class SessionReferences extends Table {
  @override
  String get tableName => 'session_reference';

  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get refType =>
      text().check(refType.isIn(const ['manuscript', 'chapter', 'file']))();
  TextColumn get refId => text()(); // 软引用
  IntColumn get isPrimary => integer()
      .withDefault(const Constant(0))
      .check(isPrimary.isIn(const [0, 1]))();
  TextColumn get excerptRange => text().nullable()(); // JSON {start,end}
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, refType, refId},
  ];
}

/// ============================================================
/// 10. app_state — 应用级 key-value 存储
/// ============================================================
@DataClassName('AppStateEntry')
class AppStates extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().withDefault(const Constant(''))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'app_state'; // 单数表名
}

/// ============================================================
/// 11. error_logs — 错误日志
/// ============================================================
@DataClassName('ErrorLog')
class ErrorLogs extends Table {
  TextColumn get id => text()();
  TextColumn get level => text()
      .withDefault(const Constant('error'))
      .check(level.isIn(const ['debug', 'info', 'warn', 'error', 'fatal']))();
  TextColumn get category => text()
      .withDefault(const Constant('general'))
      .check(
        category.isIn(const [
          'general',
          'api',
          'database',
          'render',
          'network',
          'skill',
          'validation',
        ]),
      )();
  TextColumn get message => text()();
  TextColumn get stack => text().nullable()();
  TextColumn get context => text().nullable()(); // JSON
  TextColumn get deviceInfo => text().nullable()(); // JSON
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 12. attached_files — 附属文件（v5 新增）
/// ============================================================
@DataClassName('AttachedFile')
class AttachedFiles extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text().withDefault(const Constant(''))();
  TextColumn get fileRole => text()
      .withDefault(const Constant('general'))
      .check(fileRole.isIn(const ['outline', 'material', 'general']))();
  TextColumn get mimeType => text().withDefault(const Constant('text/plain'))();
  TextColumn get content => text().withDefault(const Constant(''))();
  IntColumn get byteSize => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 13. teacher_suggestion — 教师建议（v8 新增）
/// ============================================================
@DataClassName('TeacherSuggestionRow')
class TeacherSuggestions extends Table {
  @override
  String get tableName => 'teacher_suggestion';

  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get messageId =>
      text().references(Messages, #id, onDelete: KeyAction.cascade)();
  TextColumn get source =>
      text().check(source.isIn(const ['editor', 'diagnosis']))();
  TextColumn get teachingDecision =>
      text().check(teachingDecision.isIn(const ['guide', 'train']))();
  TextColumn get targetSyndromeId => text().nullable()();
  TextColumn get targetDimension => text().nullable()();
  TextColumn get taskType => text().check(
    taskType.isIn(const ['rewrite', 'analyze', 'compare', 'generate']),
  )();
  TextColumn get taskDescription => text()();
  TextColumn get difficulty =>
      text().check(difficulty.isIn(const ['easy', 'medium', 'hard']))();
  TextColumn get evaluationCriteria =>
      text().withDefault(const Constant('[]'))(); // JSON string[]
  TextColumn get status => text()
      .withDefault(const Constant('active'))
      .check(status.isIn(const ['active', 'resolved']))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get resolvedAt => integer().nullable()();

  /// 批次62：用户采纳时间（「开始练习」时写入；null = 未采纳）
  IntColumn get adoptedAt => integer().nullable()();

  /// 批次62：用户跳过时间（「跳过此建议」时写入；null = 未跳过）
  IntColumn get dismissedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 14. editor_observation — 编辑观察（v9 新增）
/// UNIQUE(session_id, message_id)
/// ============================================================
@DataClassName('EditorObservationRow')
class EditorObservations extends Table {
  @override
  String get tableName => 'editor_observation';

  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get messageId =>
      text().references(Messages, #id, onDelete: KeyAction.cascade)();
  TextColumn get possibleIntent => text()();
  TextColumn get intentConfidence =>
      text().check(intentConfidence.isIn(const ['low', 'moderate', 'high']))();
  TextColumn get observations => text()(); // JSON
  TextColumn get overallImpression => text()();
  TextColumn get strengths =>
      text().withDefault(const Constant('[]'))(); // JSON string[]
  IntColumn get teacherTriggered => integer()
      .withDefault(const Constant(0))
      .check(teacherTriggered.isIn(const [0, 1]))();
  IntColumn get pronouncedCount => integer().withDefault(const Constant(0))();
  IntColumn get againstCount => integer().withDefault(const Constant(0))();
  TextColumn get targetRefType => text().nullable().check(
    targetRefType.isNull() |
        targetRefType.isIn(const ['manuscript', 'chapter']),
  )();
  TextColumn get targetRefId => text().nullable()();
  IntColumn get timestamp =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, messageId},
  ];
}

/// ============================================================
/// 15. character_fact — 人物知识结构（A6 首步，批次66 B62i）
/// 作品级（manuscript_id 维度），TKG 时间维度节点
/// 断言带章节/时间双维度（区别于 KV 的根本）
/// ============================================================
@DataClassName('CharacterFact')
class CharacterFacts extends Table {
  @override
  String get tableName => 'character_fact';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get firstSeenChapter => integer().nullable()(); // 首次出现章节序号
  IntColumn get firstSeenAt => integer().nullable()(); // 首次出现时间（unix 秒）
  TextColumn get assertions =>
      text().withDefault(const Constant('[]'))(); // JSON CharacterAssertion[]
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {manuscriptId, name},
  ];
}

/// ============================================================
/// 16. event_fact — 事件知识节点（A6 第二迭代，批次67 B62j F07）
/// 作品级（manuscript_id 维度），TKG 时间维度节点
/// 事件带章节 + 因果边（cause/effect），供「因果链断裂」检测
/// ============================================================
@DataClassName('EventFact')
class EventFacts extends Table {
  @override
  String get tableName => 'event_fact';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()(); // 事件名（如「阿禾决定去金陵」）
  IntColumn get chapter => integer().nullable()(); // 发生章节序号
  TextColumn get eventType => text()(); // 事件类型（决定/转折/突发/冲突/日常）
  TextColumn get causeEventId => text().nullable()(); // 因果前驱事件 id（可空）
  TextColumn get effectEventId => text().nullable()(); // 因果后继事件 id（可空）
  TextColumn get participants =>
      text().withDefault(const Constant('[]'))(); // 参与人物列表 JSON
  TextColumn get description =>
      text().withDefault(const Constant(''))(); // 一句话描述
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {manuscriptId, name},
  ];
}

/// ============================================================
/// 17. subplot_fact — 支线/子线节点（A6 第二迭代，批次67 B62j F11）
/// 作品级（manuscript_id 维度），TKG 时间维度节点
/// 支线带引入章节 + 回收章节，供「情节闭环」检测
/// ============================================================
@DataClassName('SubplotFact')
class SubplotFacts extends Table {
  @override
  String get tableName => 'subplot_fact';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()(); // 支线名（如「钥匙的秘密」）
  IntColumn get introducedChapter => integer().nullable()(); // 引入章节序号
  IntColumn get resolvedChapter => integer().nullable()(); // 回收章节序号（null=未回收）
  IntColumn get resolvedAt => integer().nullable()(); // 回收时间（unix 秒）
  TextColumn get description =>
      text().withDefault(const Constant(''))(); // 一句话描述
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {manuscriptId, name},
  ];
}

/// ============================================================
/// 18. outline_entity — 大纲实体（批次72 大纲层）
/// 作品级（manuscript_id 维度），AI 自主提取的实体（人物/设定/情节梗概）
/// 实体带规范名 + 别名表，status 分 pending/active/rejected（用户确认态）
/// 别名交集匹配 + matched_entity_id 双通道，防同实体重复入库
/// ============================================================
@DataClassName('OutlineEntity')
class OutlineEntities extends Table {
  @override
  String get tableName => 'outline_entity';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get entityType => text()(); // character | setting | plot
  TextColumn get entityKey => text()(); // 规范名（如「王建国」）
  TextColumn get aliases =>
      text().withDefault(const Constant('[]'))(); // 别名表 JSON string[]
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending | active | rejected
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {manuscriptId, entityKey},
  ];
}

/// ============================================================
/// 19. outline_impression — 大纲印象（批次72 大纲层）
/// 单条梗概片段，挂在实体下，来源章节可追溯
/// conflict_with 标记与另一条印象的矛盾关系（用户裁决）
/// UNIQUE(entity_id, impression) 防同实体同文本重复入库
/// ============================================================
@DataClassName('OutlineImpression')
class OutlineImpressions extends Table {
  @override
  String get tableName => 'outline_impression';

  TextColumn get id => text()();
  TextColumn get entityId =>
      text().references(OutlineEntities, #id, onDelete: KeyAction.cascade)();
  TextColumn get impression => text()(); // 单条印象/梗概片段
  TextColumn get sourceChapterId => text().nullable()(); // 来源章节 id
  IntColumn get sourceChapterNo => integer().nullable()(); // 来源章节序号
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get conflictWith => text().nullable()(); // 冲突的印象 id（待用户裁决）
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending | active | rejected | superseded
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {entityId, impression},
  ];
}

/// ============================================================
/// 20. training_results — 训练结果（X-041a P0：训练结果持久化）
/// 会话级（session_id 维度），记录每次练习尝试的结果
/// 关联 teacher_suggestion（可空，SET NULL：删建议不删训练历史）
/// 关联 syndrome_id（软引用，无外键，症候 ID 永不复用）
/// 真源：PracticeStore.trainingResult 当前仅存内存 state，本表补全持久化路径
/// ============================================================
@DataClassName('TrainingResultRow')
class TrainingResults extends Table {
  @override
  String get tableName => 'training_results';

  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  // 关联建议（可空：无建议触发的自主训练）— 删建议时 SET NULL 保留训练历史
  TextColumn get suggestionId => text().nullable().references(
    TeacherSuggestions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get syndromeId => text()(); // 软引用，无外键
  TextColumn get taskType => text().check(
    taskType.isIn(const ['rewrite', 'analyze', 'compare', 'generate']),
  )();
  TextColumn get userContent => text()(); // 用户提交的练习内容
  TextColumn get result =>
      text().check(result.isIn(const ['passed', 'partial', 'failed']))();
  TextColumn get feedbackJson => text().nullable()(); // AI 评分反馈 JSON
  RealColumn get score => real().nullable()(); // 0.0-1.0 评分
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}
