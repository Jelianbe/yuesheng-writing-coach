/**
 * workspaces-index.ts — 触发所有 workspace 的自注册（ADR-002）
 *
 * 通过 import 触发每个 workspace 文件顶层 registerWorkspace(...) 调用。
 * 添加新 workspace 只需在下方加一行 import。
 */
import './CatalogWorkspace/index';
import './ProgressWorkspace/index';
import './LearningLogWorkspace/index';
import './WorksWorkspace/index';
import './TeachingNoteWorkspace/index';
import './SettingsWorkspace/index';
import './StageProgressWorkspace/index';
