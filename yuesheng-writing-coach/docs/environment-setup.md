# 月笙写作教练项目 - 开发环境补全计划

## 一、当前环境状态检查

### 1.1 已配置组件
- ✅ **Node.js** (v20+) - 基础运行时
- ✅ **pnpm** - 包管理器
- ✅ **TypeScript** (v5.3+) - 类型系统
- ✅ **Vite** (v5+) - 构建工具
- ✅ **Electron** (v28+) - 桌面框架
- ✅ **React 18** - UI 框架
- ✅ **Tailwind CSS** - 样式框架
- ✅ **Zustand** - 状态管理
- ✅ **SQLite** - 数据库
- ✅ **electron-vite** - Electron 构建工具

### 1.2 依赖文件状态
```
d:\ai-teacher\yuesheng-writing-coach\
├── package.json (✅ 存在但需完善)
├── tsconfig.json (✅ 存在)
├── tailwind.config.js (❌ 缺失)
├── postcss.config.js (❌ 缺失)
├── electron.vite.config.ts (❌ 缺失)
└── .env.example (❌ 缺失)
```

## 二、缺失环境组件清单

### 2.1 构建配置文件
| 文件 | 用途 | 优先级 | 预估时间 |
|------|------|--------|----------|
| `electron.vite.config.ts` | Electron + Vite 配置 | P0 | 1小时 |
| `tailwind.config.js` | Tailwind CSS 配置 | P0 | 30分钟 |
| `postcss.config.js` | PostCSS 配置 | P0 | 15分钟 |

### 2.2 开发依赖包
| 包名 | 用途 | 优先级 | 预估时间 |
|------|------|--------|----------|
| `@vitejs/plugin-react` | React 支持 | P0 | 安装时间 |
| `@electron-toolkit/tsconfig` | Electron TS 配置 | P0 | 安装时间 |
| `@electron-toolkit/utils` | Electron 工具库 | P0 | 安装时间 |
| `cross-env` | 跨平台环境变量 | P0 | 安装时间 |

### 2.3 UI 组件库
| 包名 | 用途 | 优先级 | 预估时间 |
|------|------|--------|----------|
| `@radix-ui/react-*` | 原子化组件库 | P1 | 安装时间 |
| `lucide-react` | 图标库 | P1 | 安装时间 |
| `class-variance-authority` | 类名工具 | P1 | 安装时间 |
| `clsx` | 类名工具 | P1 | 安装时间 |
| `tailwind-merge` | 类名合并 | P1 | 安装时间 |

### 2.4 生产依赖
| 包名 | 用途 | 优先级 | 预估时间 |
|------|------|--------|----------|
| `react-markdown` | Markdown 渲染 | P1 | 安装时间 |
| `rehype-highlight` | 代码高亮 | P1 | 安装时间 |
| `date-fns` | 日期处理 | P1 | 安装时间 |
| `uuid` | ID 生成 | P1 | 安装时间 |
| `electron-store` | 本地存储 | P0 | 安装时间 |

## 三、环境补全计划

### 3.1 第一阶段：核心构建配置（P0 - 今日完成）
```bash
# 1. 安装开发依赖
pnpm add -D @vitejs/plugin-react @electron-toolkit/tsconfig @electron-toolkit/utils cross-env

# 2. 安装生产依赖
pnpm add electron-store

# 3. 创建配置文件
```

### 3.2 第二阶段：样式和 UI 组件（P1 - 明日完成）
```bash
# 1. 安装样式相关依赖
pnpm add -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# 2. 安装 UI 组件库
pnpm add @radix-ui/react-dialog @radix-ui/react-dropdown-menu @radix-ui/react-select @radix-ui/react-separator @radix-ui/react-tooltip @radix-ui/react-slot lucide-react class-variance-authority clsx tailwind-merge

# 3. 安装 Markdown 渲染
pnpm add react-markdown rehype-highlight date-fns uuid
pnpm add -D @types/uuid
```

### 3.3 第三阶段：类型定义（P1 - 本周内完成）
```bash
pnpm add -D @types/better-sqlite3
```

## 四、配置文件内容

### 4.1 electron.vite.config.ts
```typescript
import { resolve } from 'path';
import { defineConfig, externalizeDepsPlugin } from 'electron-vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    build: {
      outDir: 'dist/main',
    },
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    build: {
      outDir: 'dist/preload',
    },
  },
  renderer: {
    resolve: {
      alias: {
        '@': resolve('src/renderer'),
        '@main': resolve('src/main'),
        '@shared': resolve('src/shared'),
      },
    },
    plugins: [react()],
    build: {
      outDir: 'dist/renderer',
    },
  },
});
```

### 4.2 tailwind.config.js
```javascript
/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: ['class'],
  content: ['./src/renderer/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
      },
    },
  },
  plugins: [],
};
```

### 4.3 package.json（更新后）
```json
{
  "name": "yuesheng-writing-coach",
  "version": "1.0.0",
  "description": "月笙写作教练 - AI 驱动的写作辅导工具",
  "main": "./dist/main/index.js",
  "scripts": {
    "dev": "electron-vite dev",
    "build": "electron-vite build",
    "preview": "electron-vite preview",
    "package": "electron-builder --dir",
    "dist": "electron-builder",
    "typecheck": "tsc --noEmit"
  },
  "build": {
    "appId": "com.yuesheng.writing-coach",
    "productName": "月笙写作教练",
    "directories": {
      "output": "release"
    },
    "win": {
      "target": ["nsis"],
      "icon": "resources/icons/icon.ico"
    },
    "nsis": {
      "oneClick": false,
      "allowToChangeInstallationDirectory": true
    }
  }
}
```

## 五、验证步骤
1. `pnpm dev` - 启动开发模式
2. `pnpm typecheck` - 类型检查
3. `pnpm build` - 构建项目
4. 检查所有依赖是否正确安装

---
**计划制定日期**：2026-06-01  
**预计完成时间**：2026-06-02