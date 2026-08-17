# 维护模式声明（MAINTENANCE MODE）

> 生效日期：2026-08-17 · 决策依据：yuesheng-flutter 宪法草案 §10.5 / 决策 D10

**本工程（月笙写作教练 · Web / Electron+Capacitor 版）已进入维护模式。**

## 状态
- 🟡 **维护模式**：仅接受 **bug 修复** 与 **依赖 / 安全更新**。
- 🚫 **不再新增功能**、不再做架构演进。

## 为什么
产品的**唯一真源**已定为 **Flutter 版**（`D:\ai-teacher\yuesheng-flutter`，见其
`docs/yuesheng-flutter-宪法草案.md`）。Web 版是 2026-06 起长期发货的实现，成熟但
不再承载未来演进；新能力统一收敛到 Flutter，避免双轨功能漂移与重复建设。

## 开发者须知
- 新功能 / 新能力 / 迁移资产 → 去 **Flutter 工程** 实现。
- 本工程改动仅限：缺陷修复、依赖升级、安全补丁。
- 提交前仍须通过本工程自身 CI（`yuesheng-writing-coach/.github/workflows/ci.yml`）。
- Flutter 功能追平后，本工程是否退役由后续决策决定。

## 相关
- Flutter 真源与谱系：`D:\ai-teacher\yuesheng-flutter\docs\yuesheng-flutter-宪法草案.md` §十
- RN 版（已废弃）：`D:\teacher\yuesheng-android`（DEPRECATED.md）
