# 月笙写作教练 - 项目概览 (Project Brief)

**版本**: V1.0  
**创建日期**: 2026-06-01  
**状态**: approved  

## 1. 项目定位

月笙写作教练是一个 AI 写作教练桌面应用，定位为"教练"而非"助手"：
- **不替用户写** — 只给示范，不替完成
- **不替用户决定** — 给选择，不给答案
- **帮用户看清问题，让用户自己解决**

## 2. 技术栈

| 层 | 技术 |
|---|------|
| 框架 | Electron 28+ |
| 语言 | TypeScript (strict) |
| 前端 | React + Vite + Tailwind CSS |
| 状态 | Zustand |
| 存储 | electron-store (配置) + better-sqlite3 (数据) |
| 模型 | DPV4（用户自备 API Key） |

## 3. MVP 范围（Phase 1）

| 功能 | 优先级 | 状态 |
|------|--------|------|
| API 配置界面 | P0 | ✅ 规范+计划已完成 |
| 聊天界面 | P0 | 待开发 |
| System Prompt 注入 | P0 | 待开发 |
| 会话管理 | P0 | 待开发 |
| 诊断书展示 | P0 | 待开发 |
| 态度档位控制 | P0 | 待开发 |

## 4. 核心架构

```
Main Process (Node.js)
├── API Proxy (流式输出)
├── Session Storage (SQLite)
├── Diagnosis Engine (规则+信号权重)
└── IPC Bridge

Renderer Process (React)
├── Chat UI
├── Diagnosis Panel
├── API Config Panel
└── Settings Panel
```

## 5. 开发原则

详见 [.specify/constitution.md](../.specify/constitution.md)

核心原则：
- 诊断引擎基于规则，不依赖 AI 生成
- 配置外置，禁止硬编码
- 每次改动前必须有回退路径
- 代码变更必须同步更新文档

## 6. 当前进度

- ✅ Prompt 体系 V3.0 完成
- ✅ 教学动作库 A001-A008 完成
- ✅ 病症识别手册 P001-P007 完成
- ✅ 训练任务库 T001-T014 完成
- ✅ 项目规则体系 17 条完成
- ✅ Spec Kit 工作流搭建完成
- 🔄 API 配置界面 - 实施中

## 7. 下一步

按开发计划顺序实施：
1. API 配置界面 ← 当前
2. 聊天界面 + 流式输出
3. 诊断引擎集成
4. 会话管理
5. 态度档位控制
