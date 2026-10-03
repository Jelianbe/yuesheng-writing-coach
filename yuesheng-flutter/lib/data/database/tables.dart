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
  // v30：置顶标记（1=置顶，会话列表排最前）
  IntColumn get pinned => integer().withDefault(const Constant(0))();

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
  // v42：诊断结论裁决态（confirmed=权威正式诊断；pending=教学轮/反问学员未确认；
  // replaced=被后续正式诊断替换的旧 pending 行）。历史行默认 confirmed。
  TextColumn get status => text()
      .withDefault(const Constant('confirmed'))
      .check(status.isIn(const ['confirmed', 'pending', 'replaced']))();

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

  /// 证据把握度（信心系统 Part B）：本地计算（证据强度+复现），0-1。
  /// 弱把握（< kWeakEvidenceConfidence）且未确认 → 不进活跃症候注入/教学焦点。
  RealColumn get evidenceConfidence => real().nullable()();
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
  TextColumn get description => text().withDefault(
    const Constant(''),
  )(); // 设定资料库第四批：条目正文（用户自由写作；AI 抽取的 KV 断言仍走 assertions）
  TextColumn get aliases =>
      text().withDefault(const Constant('[]'))(); // C78 D-1：并入主角色的源名归档
  TextColumn get status =>
      text().withDefault(const Constant('active'))(); // C78：active | merged
  IntColumn get pinned =>
      integer().withDefault(const Constant(0))(); // v35：用户钉选（L2 退化层名片）
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
  // N12-F3b / ADR-C96：事件所属章节的**身份键**（chapters.sort_order，0 基）。
  // 与上一列**物理分开**：`chapter` 保留 AI 原值（标称号，R1′ 不篡改），身份另存
  // 于此。存量行为 NULL ⇒ 读取侧走 `CharacterAssertion.chapterIdentity` 式回退。
  IntColumn get chapterSortOrder => integer().nullable()();
  TextColumn get eventType => text()(); // 事件类型（决定/转折/突发/冲突/日常）
  TextColumn get causeEventId => text().nullable()(); // 因果前驱事件 id（可空）
  TextColumn get effectEventId => text().nullable()(); // 因果后继事件 id（可空）
  TextColumn get participants =>
      text().withDefault(const Constant('[]'))(); // 参与人物列表 JSON
  TextColumn get description =>
      text().withDefault(const Constant(''))(); // 一句话描述
  IntColumn get stale =>
      integer().withDefault(const Constant(0))(); // C78 D-8：事件行级 stale
  TextColumn get chapterHash => text().nullable()(); // C78 D-6：抽取时章节指纹
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
  // N12-F3b / ADR-C96：两列的**身份键**（chapters.sort_order，0 基），与上两列并列。
  // 为什么必须有它：`subplot_closure_detector` 拿 `currentChapter`（**恒身份**）与
  // `introducedChapter` 做减法判阈值，而后者一列两基号（AI 值 / 缺字段时退回身份）
  // ⇒ 相减无意义。身份落地后判据才有单一基线。
  IntColumn get introducedChapterSortOrder => integer().nullable()();
  IntColumn get resolvedChapterSortOrder => integer().nullable()();
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
  )(); // pending | active | rejected | superseded | expired
  //     ↑ B13 低风险对齐（2026-09-20）：`expired` 由 cleanupPendingImpressions
  //     写入（outline_repository 两处：超 7 天未确认 + 归档作品联动），读路径以
  //     `status='pending'` 排除 = 隐性退场终态，语义闭环。
  //     **无 DB CHECK 是 08-17 裁定的既定状态**（「夸大，勿当 P0 动刀」）——
  //     补 CHECK 属 schema 变更，需重建迁移 + ADR，非注释级对齐，勿顺手做。
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
  // 教学线 P0-1：自评三维证据（v32）
  // 对齐 mastery_evidence 契约：解释≥2 / 信心≥3 / 近迁移≥1，全部可空（R-009 不强制）
  IntColumn get confidenceRating => integer().nullable()(); // 自评信心 1-5
  TextColumn get explanationText => text().nullable()(); // 自评解释：为什么这样改
  TextColumn get transferText => text().nullable()(); // 自评近迁移：换个写法/场景怎么做
  // 批1·N2（FSRS 自评档位，v38）：回忆难度自评 'again'|'hard'|'good'|'easy'。
  // ★ 与上面三维自评语义不同：三维是「掌握证据」（供 mastery_evidence 门控），
  //   本列是「回忆难度」（供 FSRS 间隔调度）。可空 = 旧数据/未自评。
  TextColumn get userRating => text().nullable()();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 16. ai_accounts — LLM 多账号（v28，ADR-C91 批次 D-1）
/// 仅存元信息；api_key 存 flutter_secure_storage JSON map（R-029 密钥零 DB 面）
/// ============================================================
@DataClassName('AiAccountRow')
class AiAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get model => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 21. backup_history — 数据库备份记录（v29，外来设计文档 §二）
/// type: auto(自动) / manual(手动) / pre_migrate(迁移前自动)
/// status: success / failed / restored
/// file_path 存备份文件绝对路径；错误信息留痕供诊断
/// ============================================================
@DataClassName('BackupHistoryRow')
class BackupHistory extends Table {
  TextColumn get id => text()(); // 备份 ID（UUID）
  TextColumn get type =>
      text().check(type.isIn(const ['auto', 'manual', 'pre_migrate']))();
  TextColumn get filePath => text()();
  IntColumn get fileSize => integer()();
  TextColumn get status =>
      text().check(status.isIn(const ['success', 'failed', 'restored']))();
  TextColumn get errorMessage => text().withDefault(const Constant(''))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 22. world_fact — 世界观设定条目（书籍级成长叙事 · 批次 E1，v31）
/// 作品级（manuscript_id 维度）
///
/// 与 character_fact **同构**：一行 = 一个设定主题（name），行内 assertions
/// 是该主题的多条断言（attribute / value / chapter / chapterHash）。
/// 同构的收益：白拿 C78 批次2a 的 chapterHash 幽灵治理
/// （[FactStaleService]），无需为世界观重写一套 stale 机制。
///
/// ★ 判据**不复用** F05（方案 §4 E1 的关键技术判断）：世界观是「规则」，
///   天然带例外（「灵气稀薄」+「此地有灵脉」是层次感而非矛盾）。直接套
///   「同属性不同值 → 时序矛盾」会产出与幽灵事实同形态的**幽灵矛盾**，
///   故世界观判据须独立设计，不在此表层耦合。
///
/// status 取值 active | archived——与 character_fact 的 active | merged
/// **刻意不同**：世界观无同名合并场景（C78 §5.4 的合并源于同一角色被 AI
/// 用多名抽出），此列仅作归档槽位，值域按本表语义自定。
/// ============================================================
@DataClassName('WorldFact')
class WorldFacts extends Table {
  @override
  String get tableName => 'world_fact';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()(); // 设定主题名（如「灵气体系」）
  IntColumn get firstSeenChapter => integer().nullable()(); // 首次提出章节序号
  IntColumn get firstSeenAt => integer().nullable()(); // 首次提出时间（unix 秒）
  TextColumn get assertions =>
      text().withDefault(const Constant('[]'))(); // JSON CharacterAssertion[]
  TextColumn get description => text().withDefault(
    const Constant(''),
  )(); // 设定资料库第四批：条目正文（用户自由写作；AI 抽取的 KV 断言仍走 assertions）
  TextColumn get status =>
      text().withDefault(const Constant('active'))(); // active | archived
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

/// 条目互链（设定资料库·Codex 式互链第一批，schema v36）。
///
/// 四类设定实体（character / world / outline / setting）之间的跨实体引用。
/// - **方向性**：link(A→B) 与 link(B→A) 是两行——用户自定义方向与关系名；
///   详情页展示「涉及本实体的全部互链」（出链 + 入链）
/// - **软引用**：source_id / target_id 跨表无 FK（类型由 kind 决定），
///   目标行被删后展示容错（「已删除的条目」不可点）
/// - **本批不参与诊断注入**：仅管理 / 展示 / 详情页互跳（克制清单转正）
/// - UNIQUE 防重复互链（幂等 create）
@DataClassName('SettingLink')
class SettingLinks extends Table {
  @override
  String get tableName => 'setting_link';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceKind =>
      text()(); // character | world | outline | setting
  TextColumn get sourceId => text()();
  TextColumn get targetKind => text()();
  TextColumn get targetId => text()();
  TextColumn get label =>
      text().withDefault(const Constant(''))(); // 可选关系名（如「所属世界」）
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {manuscriptId, sourceKind, sourceId, targetKind, targetId},
  ];
}

/// 「其他」开放容器（设定资料库第二批）：用户自建类别 + 勾选参与诊断。
///
/// 武器 / 规则怪谈 / 组织等非角色、非世界观的自由设定。类别为自由字符串
/// （无独立类别表），默认不注入诊断，逐条勾选 participate 后才进上下文。
/// 刻意**不做** assertions 列：AI 抽取冻结（E1-b-3 裁定同源），无矛盾检测判据。
class SettingEntries extends Table {
  @override
  String get tableName => 'setting_entry';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get category =>
      text().withDefault(const Constant(''))(); // 用户自建类别标签
  TextColumn get name => text()();
  TextColumn get description =>
      text().withDefault(const Constant(''))(); // 自由正文（用户主权区，无 AI 写入）
  BoolColumn get participate =>
      boolean().withDefault(const Constant(false))(); // 勾选参与诊断
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

/// 条目标签（设定资料库·标签批次，v37）：Codex 式自由多标签。
///
/// 覆盖 character / world / setting（「其他」）三类实体，多对多自由字符串
/// （无独立标签表）。与 category 的关系：category 是「其他」的单值类别且
/// **参与诊断**（AI 上下文）；tag 是管理性自由多标签，**不参与诊断注入**
/// （克制清单）。outline 不纳入（大纲实体无直接写入路径，AI 沉淀）。
///
/// - 幂等：UNIQUE(manuscript_id, entity_kind, entity_id, tag)，addTag 先查后插
/// - 软引用：entity_id 跨表无 FK（类型由 entity_kind 决定），与 setting_link 同构
/// - 本批不做全稿标签聚合/筛选（后续批）
@DataClassName('SettingTag')
class SettingTags extends Table {
  @override
  String get tableName => 'setting_tag';

  TextColumn get id => text()();
  TextColumn get manuscriptId =>
      text().references(Manuscripts, #id, onDelete: KeyAction.cascade)();
  TextColumn get entityKind => text()(); // character | world | setting
  TextColumn get entityId => text()();
  TextColumn get tag => text()();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {manuscriptId, entityKind, entityId, tag},
  ];
}

/// ============================================================
/// 18. pilot_metric_event — 小白冷启动试点埋点事件（ADR-C121 v41）
/// 会话/用户级（session_id 维度，用户级事件 session_id 记 ''），
/// 追加式事件日志，供 C121-2 验收读数离线计算三指标：
///   30 秒产出率 / 可诊断率 / 二轮留存
///   ⚠ 口径降级（ADR-C133 §4.4）：二轮留存 = 复刷率，仅报次留/7留两窗口，
///     只作「产品是否还有人用」的存活信号；禁止用于教学成败判断与立项依据。
/// 事件类型：card_wall_entered · micro_task_submitted · app_opened
///   （可诊断率由 diagnosis_results 按会话 + 时间关联，不在此表）
/// 试点批次专用；正式设计批评估后决定去留（不承诺长期保留）。
/// ============================================================
@DataClassName('PilotMetricEvent')
class PilotMetricEvents extends Table {
  @override
  String get tableName => 'pilot_metric_event';

  TextColumn get id => text()();

  /// 会话 id；用户级事件（如 app_opened）记 ''（单用户 App，用户级语义）
  TextColumn get sessionId => text()();
  TextColumn get eventType => text()();

  /// JSON payload（如 card 类型 + 字数），无则 ''
  TextColumn get payload => text().withDefault(const Constant(''))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 19. edit_diff_event — 写作修改事件埋点（ADR-C132 批1 埋点地基，v43）
/// 北极星研讨 §10-4 三项事件（追加式事件日志，与 pilot_metric_event 同范式）：
///   diff       — 位置级 diff：反馈后用户对稿件的修改，定位到变化片段
///                （批 1 在 saveChapterContent 自动捕获）
///   anchor_ack — 指认事件：用户确认教练指认的片段位置（UI 接线批 3）
///   completion — 成稿事件：章节被标记完成（UI 接线批 3）
/// 埋点先行纪律（变体池验收⑤）：A/B 前必须有位置级 diff，无埋点不谈 A/B。
/// ============================================================
@DataClassName('EditDiffEvent')
class EditDiffEvents extends Table {
  @override
  String get tableName => 'edit_diff_event';

  TextColumn get id => text()();

  /// 会话 id；无法确定会话（章节级保存无会话上下文）记 ''
  TextColumn get sessionId => text().withDefault(const Constant(''))();

  TextColumn get chapterId => text()();

  /// 触发该次修改的教练消息 id（可空：无关联反馈的自主修改 / 成稿事件）
  TextColumn get messageId => text().nullable()();

  /// 事件类型：diff | anchor_ack | completion
  TextColumn get eventType => text().check(
    eventType.isIn(const ['diff', 'anchor_ack', 'completion']),
  )();

  /// 变化片段起止（字符偏移，[start, end) 前含后不含；null = 全章）
  IntColumn get anchorStart => integer().nullable()();
  IntColumn get anchorEnd => integer().nullable()();

  /// 变化前后文本（diff 事件必填；anchor_ack 记录被指认片段，completion 可空）
  TextColumn get beforeText => text().nullable()();
  TextColumn get afterText => text().nullable()();

  /// JSON payload（如 diff 段数 / 指认来源），无则 ''
  TextColumn get payload => text().withDefault(const Constant(''))();
  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 20. record_entry — 记录条目事件表（ADR-C143 书籍资料库 · 批A，v44）
///
/// 提议式留痕（裁定①：自动留痕降级为「AI/作者显式提议 → 作者裁决」）。
/// 复用 character_fact 既有状态机 pending→kept/rejected（character_types）。
///
/// R-009 / 摘录纪律：
///   - excerpt = 原文整句/整段**原样搬运**，本系统只加 created_at 时间戳 +
///     message_id 来源指针，**不做 LLM 改写/缩写/提炼**，不打业务定性标签
///     （定性权归作者）。
///   - manuscript_id / session_id / message_id 全为**软引用**（无外键）：
///     messages 有 ON DELETE CASCADE，只存 messageId 会悬空 ⇒ excerpt
///     冗余快照保回溯。删稿不级联删留痕（「不认识的东西不销毁」）。
///
/// 本批不进诊断注入链（未确认记录 ≠ 教学诊断依据，ADR-C143 §1.6）。
/// ============================================================
@DataClassName('RecordEntry')
class RecordEntries extends Table {
  @override
  String get tableName => 'record_entry';

  TextColumn get id => text()();

  /// 作品 id（软引用，无外键）
  TextColumn get manuscriptId => text()();

  /// 会话 id（软引用；无会话上下文记 ''）
  TextColumn get sessionId => text().withDefault(const Constant(''))();

  /// 来源消息 id（软引用，可空；级联删后由 excerpt 快照回溯）
  TextColumn get messageId => text().nullable()();

  /// 原文摘录（整句/整段原样搬运，禁改写）
  TextColumn get excerpt => text().withDefault(const Constant(''))();

  /// C147：作者意图归入位置（'' = 未定 / 'character' 人设 / 'outline' 大纲 /
  /// 'world' 世界观）。仅作者在确认卡里自选，AI 不替作者定性（R-009）；
  /// 不进诊断注入链。
  TextColumn get targetSection => text().withDefault(const Constant(''))();

  /// 裁决态：pending（提议待裁）| kept（作者确认留档）| rejected（作者拒绝）
  TextColumn get status => text()
      .withDefault(const Constant('pending'))
      .check(status.isIn(const ['pending', 'kept', 'rejected']))();

  /// 裁决时间（确认/拒绝时写；pending 期为 null）
  IntColumn get decidedAt => integer().nullable()();

  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// ============================================================
/// 21. material_entry — 资料条目事件表（ADR-C143 书籍资料库 · 批C，v44）
///
/// 外部参考资料（网页/书目原文），与作者自整理的 setting_entry 视觉上分开、
/// **永不自动升格 canon**（裁定④⑤）。
///
/// R-009 / 口径：
///   - 默认**存原文不提炼**（original_text 原样存）；「关键片段」= key_snippet
///     **原样截取** + anchor 原网页锚点，不生成摘要句。
///   - summary 列**仅作者主动点按钮（on-demand）才写**，默认 null——
///     不后台自动总结。
///   - source_credibility 默认 'unknown'，AI **不评级**（评级 = 替作者判断
///     来源靠不靠谱，踩 R-009）；只展示 source_name（域名/来源名）。
///   - 去重 UNIQUE(manuscript_id, url)；语义去重默认不做。
///     url 可空：无链接的粘贴原文允许多行（SQLite UNIQUE 视 NULL 互不相同）。
///   - manuscript_id 软引用（无外键），同 record_entry。
///
/// 本批不进诊断注入链（资料库默认不进诊断 prompt）。
/// ============================================================
@DataClassName('MaterialEntry')
class MaterialEntries extends Table {
  @override
  String get tableName => 'material_entry';

  TextColumn get id => text()();

  /// 作品 id（软引用，无外键）
  TextColumn get manuscriptId => text()();

  /// 来源 URL（UNIQUE(manuscript_id, url) 去重；可空 = 粘贴原文无链接）
  TextColumn get url => text().nullable()();

  /// 来源名/域名（只展示域名/来源名）
  TextColumn get sourceName => text().withDefault(const Constant(''))();

  /// 来源可信度：默认 unknown；AI 永不评级
  TextColumn get sourceCredibility =>
      text().withDefault(const Constant('unknown'))();

  /// 原文（默认存原文不提炼）
  TextColumn get originalText => text().withDefault(const Constant(''))();

  /// 关键片段 = 原样截取（非 AI 摘要句）
  TextColumn get keySnippet => text().withDefault(const Constant(''))();

  /// 原网页锚点（可定位；可空）
  TextColumn get anchor => text().nullable()();

  /// AI 摘要：仅 on-demand 按钮生成；默认 null（不自动总结）
  TextColumn get summary => text().nullable()();

  /// 裁决态：pending | kept | rejected（同 record_entry 状态机）
  TextColumn get status => text()
      .withDefault(const Constant('pending'))
      .check(status.isIn(const ['pending', 'kept', 'rejected']))();

  IntColumn get createdAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();
  IntColumn get updatedAt =>
      integer().withDefault(const CustomExpression<int>('unixepoch()'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {manuscriptId, url},
  ];
}
