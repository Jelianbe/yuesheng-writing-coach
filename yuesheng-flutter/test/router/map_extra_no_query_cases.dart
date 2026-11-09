// U6 用例数据（T-20261023-04）：12 个 Map extra 消费点的逐字期望值。
// 独立成 library 只为满足 R-019 文件 ≤300 行；内容由主测试文件机器切分而来，
// 与 app_router.dart 现场枚举一一对应（行号会漂移，勿引用）。

import 'package:flutter/widgets.dart';

import 'package:writingcoach/features/app_settings/outline_entity_detail_page.dart';
import 'package:writingcoach/features/app_settings/project_settings_page.dart';
import 'package:writingcoach/features/app_settings/setting_tag_overview_page.dart';
import 'package:writingcoach/features/character/character_detail_page.dart';
import 'package:writingcoach/features/character/character_page.dart';
import 'package:writingcoach/features/manuscript/manuscript_detail_page.dart';
import 'package:writingcoach/features/world/world_fact_detail_page.dart';
import 'package:writingcoach/features/world/world_fact_page.dart';
import 'package:writingcoach/features/writing/writing_page.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/widgets/append_chapters_page.dart';
import 'package:writingcoach/widgets/chapter_recycle_bin_page.dart';
import 'package:writingcoach/widgets/progress_detail_page.dart';

class MapExtraCase {
  const MapExtraCase(
    this.name,
    this.location,
    this.extra,
    this.pageType,
    this.read,
    this.expected, [
    this.emptyTitle,
    this.pathParams = const <String, String>{},
  ]);

  final String name;
  final String location;
  final Map<String, dynamic> extra;
  final Type pageType;
  final List<Object?> Function(Widget widget) read;
  final List<Object?> expected;
  final String? emptyTitle;
  final Map<String, String> pathParams;
}

// 12 条 Map extra 消费点，按 app_router.dart 现场枚举顺序（行号会漂移，勿引用）。
final List<MapExtraCase> mapExtraCases = <MapExtraCase>[
  MapExtraCase(
    'manuscript-detail',
    AppRoutes.manuscriptDetail,
    {'manuscriptId': 'ms-eq-01', 'title': '甲稿'},
    ManuscriptDetailPage,
    _md,
    ['ms-eq-01', '甲稿'],
    '作品详情',
  ),
  MapExtraCase(
    'writing/:chapterId',
    '/writing/ch-eq-02',
    {'manuscriptId': 'ms-eq-02', 'chapterTitle': '乙章', 'cursorOffset': 37},
    WritingPage,
    _wp,
    ['ch-eq-02', '乙章', 'ms-eq-02', 37],
    null,
    {'chapterId': 'ch-eq-02'},
  ),
  MapExtraCase(
    'append-chapters',
    AppRoutes.appendChapters,
    {'manuscriptId': 'ms-eq-03', 'title': '丙稿'},
    AppendChaptersPage,
    _ac,
    ['ms-eq-03', '丙稿'],
    '追加章节',
  ),
  MapExtraCase(
    'project-settings',
    AppRoutes.projectSettings,
    {'manuscriptId': 'ms-eq-04', 'title': '丁稿'},
    ProjectSettingsPage,
    _ps,
    ['ms-eq-04', '丁稿'],
    '项目设置',
  ),
  MapExtraCase(
    'progress-detail',
    AppRoutes.progressDetail,
    {'sessionId': 's-eq-05'},
    ProgressDetailPage,
    _pd,
    ['s-eq-05'],
    '学习进度',
  ),
  MapExtraCase(
    'chapter-recycle-bin',
    AppRoutes.chapterRecycleBin,
    {'manuscriptId': 'ms-eq-06', 'title': '己稿'},
    ChapterRecycleBinPage,
    _cr,
    ['ms-eq-06', '己稿'],
    '章节回收站',
  ),
  MapExtraCase(
    'characters',
    AppRoutes.characters,
    {'manuscriptId': 'ms-eq-07', 'title': '庚稿', 'since': 1700000000},
    CharacterPage,
    _ch,
    ['ms-eq-07', '庚稿', 1700000000],
    '角色',
  ),
  MapExtraCase(
    'worlds',
    AppRoutes.worlds,
    {'manuscriptId': 'ms-eq-08', 'title': '辛稿'},
    WorldFactPage,
    _wo,
    ['ms-eq-08', '辛稿'],
    '世界观',
  ),
  MapExtraCase(
    'setting-link-character-detail',
    AppRoutes.characterDetail,
    {'manuscriptId': 'ms-eq-09', 'id': 'chr-eq-09'},
    CharacterDetailPage,
    _cd,
    ['chr-eq-09', 'ms-eq-09'],
    '角色详情',
  ),
  MapExtraCase(
    'setting-link-world-detail',
    AppRoutes.worldDetail,
    {'manuscriptId': 'ms-eq-10', 'id': 'wld-eq-10'},
    WorldFactDetailPage,
    _wd,
    ['wld-eq-10', 'ms-eq-10'],
    '世界观详情',
  ),
  MapExtraCase(
    'setting-tag-overview',
    AppRoutes.settingTagOverview,
    {'manuscriptId': 'ms-eq-11'},
    SettingTagOverviewPage,
    _st,
    ['ms-eq-11'],
    '标签总览',
  ),
  MapExtraCase(
    'setting-outline-detail',
    AppRoutes.outlineDetail,
    {'id': 'ent-eq-12', 'manuscriptId': 'ms-eq-12'},
    OutlineEntityDetailPage,
    _od,
    ['ent-eq-12', 'ms-eq-12'],
    '大纲实体',
  ),
];

List<Object?> _md(Widget w) {
  final p = w as ManuscriptDetailPage;
  return <Object?>[p.args.manuscriptId, p.args.title];
}

List<Object?> _wp(Widget w) {
  final p = w as WritingPage;
  return <Object?>[
    p.chapterId,
    p.chapterTitle,
    p.manuscriptId,
    p.initialCursorOffset,
  ];
}

List<Object?> _ac(Widget w) {
  final p = w as AppendChaptersPage;
  return <Object?>[p.manuscriptId, p.manuscriptTitle];
}

List<Object?> _ps(Widget w) {
  final p = w as ProjectSettingsPage;
  return <Object?>[p.manuscriptId, p.initialTitle];
}

List<Object?> _pd(Widget w) {
  final p = w as ProgressDetailPage;
  return <Object?>[p.sessionId];
}

List<Object?> _cr(Widget w) {
  final p = w as ChapterRecycleBinPage;
  return <Object?>[p.manuscriptId, p.manuscriptTitle];
}

List<Object?> _ch(Widget w) {
  final p = w as CharacterPage;
  return <Object?>[p.manuscriptId, p.manuscriptTitle, p.sinceTimestamp];
}

List<Object?> _wo(Widget w) {
  final p = w as WorldFactPage;
  return <Object?>[p.manuscriptId, p.manuscriptTitle];
}

List<Object?> _cd(Widget w) {
  final p = w as CharacterDetailPage;
  return <Object?>[p.characterId, p.manuscriptId];
}

List<Object?> _wd(Widget w) {
  final p = w as WorldFactDetailPage;
  return <Object?>[p.worldId, p.manuscriptId];
}

List<Object?> _st(Widget w) {
  final p = w as SettingTagOverviewPage;
  return <Object?>[p.manuscriptId];
}

List<Object?> _od(Widget w) {
  final p = w as OutlineEntityDetailPage;
  return <Object?>[p.entityId, p.manuscriptId];
}
