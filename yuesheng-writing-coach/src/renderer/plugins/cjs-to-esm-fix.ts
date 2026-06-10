/**
 * cjs-to-esm-fix — Vite 插件
 *
 * 根治方案：自动将 OxC 编译器产生的 CJS 格式 .js 文件转换为 ESM。
 *
 * 问题背景：
 *   Vite 8 使用 OxC (Rust TS 编译器)，会将 as const 对象编译为 CommonJS 格式
 *   （"use strict"; Object.defineProperty(exports, "__esModule", ...)）。
 *   但 Vite 的浏览器端是 ESM 环境，导致 import 失败：
 *     SyntaxError: The requested module does not provide an export named 'xxx'
 *
 * 解决方式：
 *   在 Vite 的 load 阶段拦截已知 workaround 文件，检测 CJS 模式并转换为 ESM。
 *   这样即使 tsc / OxC 多次覆盖这些 .js 文件，Vite 加载时仍能正常工作。
 *
 * 保护文件列表（src/shared/ 和 src/renderer/shared/ 下的运行时常量 workaround）：
 *   - constants.js        (IPC_CHANNELS, SyndromeId, ActionId 等)
 *   - mappings.js          (SYNDROME_NAMES, ACTION_NAMES, 映射表等)
 *   - trend-utils.js       (calcTrend 等趋势工具)
 *   - severity-utils.js    (severityToNumber 等严重度工具)
 *   - types.js             (apiSuccess/apiError, PERSONA_PRESETS)
 */

// @ts-ignore — Vite 插件运行在 Node.js 上下文，tsc 无法解析 vite 模块类型
// eslint-disable-next-line @typescript-eslint/no-require-imports
import type { Plugin } from 'vite';

// ===== 受保护的文件路径（相对于项目根目录）=====
const PROTECTED_FILES = new Set([
  'src/shared/constants.js',
  'src/shared/mappings.js',
  'src/shared/trend-utils.js',
  'src/shared/severity-utils.js',
  'src/renderer/shared/types.js',
]);

/**
 * 从 Vite 传入的模块 id 中提取相对路径
 * 输入: D:/ai-teacher/yuesheng-writing-coach/src/shared/constants.js
 * 输出: src/shared/constants.js
 */
function extractRelativePath(id: string): string {
  const normalized = id.replace(/\\/g, '/').split('?')[0].split('#')[0];
  // 尝试匹配 /src/ 路径段
  const match = normalized.match(/\/(src\/.+)$/);
  return match ? match[1] : '';
}

// ===== CJS 特征模式 =====
const CJS_ESM_DEFINE = /Object\.defineProperty\(exports,\s*"__esModule"/;

/**
 * 将 CJS 格式的 JS 源码转换为 ESM
 *
 * 处理的 CJS 模式：
 *   1) "use strict";                                    → 删除
 *   2) Object.defineProperty(exports,"__esModule",...)  → 删除
 *   3) exports.A = exports.B = ... = void 0;           → let A,B,...;
 *   4) exports.Name = { ... };                         → export const Name = { ... };
 *   5) exports.Name = value;                           → export const Name = value;
 *   6) exports.funcName = funcName;                    → 收集到 export {} 列表
 */
function cjsToEsm(source: string): string {
  // 快速跳过：已经是 ESM（包含 export 关键字且没有 CJS 特征）
  if (/^\s*export\s/.test(source) && !CJS_ESM_DEFINE.test(source)) {
    return source;
  }

  const lines = source.split('\n');
  const output: string[] = [];
  const funcExports: string[] = [];      // 需要追加 export {} 的名称
  const declaredVars: Set<string> = new Set(); // 已声明的变量（避免重复）

  for (const rawLine of lines) {
    const line = rawLine.trim();

    // 跳过 CJS 头部
    if (line === '"use strict"' || CJS_ESM_DEFINE.test(line)) {
      continue;
    }

    // 模式 3: 链式前置声明  exports.A = exports.B = ... = void 0;
    const chainMatch = line.match(/^exports\.([\w]+)\s*=\s*exports\./);
    if (chainMatch && line.includes('= void 0')) {
      // 提取所有被导出的变量名
      const names = line.match(/exports\.(\w+)/g)?.map(n => n.replace('exports.', '')) ?? [];
      for (const name of names) {
        if (!declaredVars.has(name)) {
          output.push(`let ${name};`);
          declaredVars.add(name);
        }
      }
      continue;
    }

    // 模式 4/5: exports.Name = value;
    const singleMatch = line.match(/^exports\.(\w+)\s*=\s*(.+);?\s*$/);
    if (singleMatch) {
      const [, name, value] = singleMatch;

      // 跳过已通过链式声明处理的变量（它们在后面会被赋值）
      if (declaredVars.has(name)) {
        // 直接赋值，保留原始行格式（不额外添加分号，避免破坏多行字面量）
        output.push(line.replace(/^exports\./, ''));
        continue;
      }

      // 判断值类型
      const trimmedValue = value.trim();
      if (/^[\{['"`]/.test(trimmedValue) || /^\d/.test(trimmedValue)) {
        // 对象/数组/字符串/数字字面量 → export const（保留原始行格式）
        output.push(line.replace(/^exports\./, 'export const '));
        declaredVars.add(name);
      } else {
        // 可能是函数引用或另一个变量 → 收集到导出列表
        funcExports.push(name);
        output.push(line.replace(/^exports\./, ''));
      }
      continue;
    }

    // 其他行原样保留（注释、sourceMap、函数声明等）
    output.push(rawLine);
  }

  // 追加导出声明（确保所有变量都可被外部 import）
  const exportedNames = new Set<string>();
  for (const line of output) {
    if (line.match(/^export\s+const\s+(\w+)/)?.[1]) exportedNames.add(RegExp.$1);
    if (line.match(/^export\s*{\s*(.+?)\s*}/)?.[1]) {
      RegExp.$1.split(',').forEach(n => exportedNames.add(n.trim()));
    }
  }
  const allExportNames = [...funcExports, ...declaredVars].filter(n => !exportedNames.has(n));

  if (allExportNames.length > 0) {
    // 移除末尾 sourceMap 注释再添加，保持位置正确
    const lastIdx = output.length - 1;
    const lastLine = output[lastIdx];
    if (lastLine?.trim().startsWith('//# sourceMappingURL=')) {
      output.splice(lastIdx, 0, `export { ${allExportNames.join(', ')} };`);
    } else {
      output.push(`export { ${allExportNames.join(', ')} };`);
    }
  }

  return output.join('\n');
}

/**
 * 创建 cjs-to-esm-fix 插件实例
 *
 * 策略：使用 enforce:'post' 在 OxC 编译之后拦截，
 * 检测到 CJS 输出时转换为 ESM。
 * 这是唯一可靠的方式，因为 OxC 的 pre 阶段会从磁盘重新读取文件。
 */
export function cjsToEsmFix(): Plugin {
  return {
    name: 'cjs-to-esm-fix',
    enforce: 'post', // 在 OxC 之后运行

    // 在 transform 阶段检测并转换
    transform(code: string, id: string): { code: string } | undefined {
      const relativePath = extractRelativePath(id);

      if (!PROTECTED_FILES.has(relativePath)) {
        return undefined;
      }

      // 已经是 ESM？不处理
      if (!CJS_ESM_DEFINE.test(code)) {
        return undefined;
      }

      const transformed = cjsToEsm(code);

      return { code: transformed };
    },
  };
}
