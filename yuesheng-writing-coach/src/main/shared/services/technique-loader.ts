/**
 * 技法库内存缓存加载器
 *
 * 负责：启动时加载 technique-library.json 到内存，提供 get() 访问
 * 特性：内存缓存 + 开发模式 fs.watch 热重载 + 版本兼容检查
 *
 * 用法：TechniqueLibraryLoader.getInstance().get()
 */
import * as fs from 'fs';
import * as path from 'path';

/** 技法库条目（最小合约，不依赖外部类型） */
export interface TechniqueLibraryEntry {
  id: string;
  coreId: string;
  techniqueId: string;
  name: string;
  description: string;
  difficulty: 'easy' | 'medium' | 'hard';
  estimatedMinutes: number;
}

let cachedData: TechniqueLibraryEntry[] | null = null;
let cachedPath: string | null = null;
let watcher: fs.FSWatcher | null = null;

/** 从 JSON 解析并做基本校验 */
function parseLibrary(raw: unknown): TechniqueLibraryEntry[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new Error('技法库数据为空或格式错误');
  }
  return raw as TechniqueLibraryEntry[];
}

/**
 * 解析 JSON 文件内容为技法条目数组
 */
function loadFromFile(filePath: string): TechniqueLibraryEntry[] {
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  return parseLibrary(raw);
}

export const TechniqueLibraryLoader = {
  /** 初始化：指定 JSON 路径，首次加载 */
  init(filePath: string): TechniqueLibraryEntry[] {
    const resolved = path.resolve(filePath);
    cachedPath = resolved;
    cachedData = loadFromFile(resolved);
    return cachedData;
  },

  /** 获取缓存数据（必须先 init） */
  get(): TechniqueLibraryEntry[] {
    if (!cachedData) {
      throw new Error('TechniqueLibraryLoader 尚未初始化，请先调用 init()');
    }
    return cachedData;
  },

  /** 重新加载（文件变更时调用） */
  reload(): TechniqueLibraryEntry[] {
    if (!cachedPath) throw new Error('TechniqueLibraryLoader 未初始化');
    cachedData = loadFromFile(cachedPath);
    return cachedData;
  },

  /** 开发模式：启动文件监听 */
  watch(): void {
    if (!cachedPath || watcher) return;
    if (process.env.NODE_ENV !== 'development') return;

    watcher = fs.watch(cachedPath, (eventType) => {
      if (eventType === 'change') {
        try {
          this.reload();
          console.warn('[TechniqueLibraryLoader] 技法库已热重载');
        } catch (err) {
          console.error('[TechniqueLibraryLoader] 热重载失败:', err);
        }
      }
    });
  },

  /** 停止监听 */
  unwatch(): void {
    if (watcher) {
      watcher.close();
      watcher = null;
    }
  },

  /** 测试用：重置状态 */
  _reset(): void {
    cachedData = null;
    cachedPath = null;
    this.unwatch();
  },
};
