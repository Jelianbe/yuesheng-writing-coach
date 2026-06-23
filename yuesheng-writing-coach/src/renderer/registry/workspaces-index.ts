/**
 * workspaces-index.ts — 触发所有 workspace 的自注册（ADR-002）
 *
 * 通过 import 触发每个 workspace 文件顶层 registerWorkspace(...) 调用。
 * 添加新 workspace 只需在下方加一行 import。
 *
 * S16 修复：将 import 路径从 src/renderer/registry/* 修正为 src/renderer/components/right/workspaces/*
 * 真实 workspace 实现一直在 components/right/workspaces/ 下（Sprint 10 完成），
 * 注册表 index 引用错路径导致自注册从未触发，右侧栏空。
 */

import '../components/right/workspaces/CatalogWorkspace';
import '../components/right/workspaces/ProgressWorkspace';
import '../components/right/workspaces/LearningLogWorkspace';
import '../components/right/workspaces/WorksWorkspace';
import '../components/right/workspaces/TeachingNoteWorkspace';
import '../components/right/workspaces/SettingsWorkspace';
import '../components/right/workspaces/StageProgressWorkspace';
