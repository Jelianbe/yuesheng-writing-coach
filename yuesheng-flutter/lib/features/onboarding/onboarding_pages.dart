// ─────────────────────────────────────────────────────────────
// onboarding_pages — 引导页数据清单（`OnboardingFlow` 的数据层）
//
// 从 `onboarding_flow.dart` 切出（`T-20261126-08` 债卡：原文件 312 行，
// 撞 R-019 文件级 300 行硬上限、容差 0 ⇒ 加一行注释即红）。
//
// 为什么单独成文件、而不是用 `part`：
//   ① 本仓门禁 10 视 `part` 为伪拆分形态（S1/S2/S3），且 part 家族会让拆分
//      失去「独立职责」的实质；
//   ② 这里是**数据清单**，与 `skill_registry` / `syndrome_registry` 的拆法
//      同型（`AGENTS.md §4` 第 8 条：拆数据清单合法，拆函数体才须走 ADR）。
//
// ⚠️ 私有名 `_OnboardingPage` / `_pages` 随之改为公开 `OnboardingPage` /
//    `onboardingPages` —— 库私有名跨文件不可见，且不用 `part` 就必须公开。
//    实测（2026-11-27）：改名前全仓 `grep` **无代码级引用**，仅 3 处注释提及
//    （`test/app_gate_test.dart:61`、`complete_intro_double_log_test.dart:177`、
//    `onboarding_flow_test.dart:10/158`），故无连带改动。
//
// ★ 内容边界：5 页文案与页序**一字未改**（卡面边界 §四.1 —— 内容层属 R-027 另一变量）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// 引导页数据（对齐 RN PAGES）
class OnboardingPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? description;
  final List<({String text, String desc, IconData icon})>? features;

  const OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.description,
    this.features,
  });
}

const List<OnboardingPage> onboardingPages = [
  OnboardingPage(
    icon: Icons.person,
    title: '我是月笙',
    subtitle: '你的专属写作教练',
    description: '陪你一起发现写作问题，拆解练习，持续成长',
  ),
  OnboardingPage(
    icon: Icons.auto_awesome,
    title: '我能帮你做什么',
    subtitle: '三大核心能力',
    features: [
      (text: '智能诊断', desc: '发现写作中的问题', icon: Icons.search),
      (text: '拆解练习', desc: '针对性提升技能', icon: Icons.build),
      (text: '追踪成长', desc: '记录进步轨迹', icon: Icons.trending_up),
    ],
  ),
  OnboardingPage(
    icon: Icons.rocket_launch,
    title: '开始使用',
    subtitle: '开启写作之旅',
    description: '导入你的作品，让我来帮你诊断和提升',
  ),
  OnboardingPage(
    icon: Icons.explore,
    title: '怎么开始',
    subtitle: '三步用起来',
    features: [
      (text: '选中文字', desc: '划词即可诊断', icon: Icons.gesture),
      (text: '导入作品', desc: '带来你的初稿', icon: Icons.upload_file),
      (text: '问月笙', desc: '随时聊写作', icon: Icons.chat_bubble_outline),
    ],
  ),
  OnboardingPage(
    icon: Icons.vpn_key,
    title: '配置 API',
    subtitle: '解锁完整功能',
    description:
        '本应用需接入你自己的 AI 服务商 API 才能做真实诊断与教学；'
        '未配置时可用免费测试模式（离线示例）体验。怎么获取：去服务商官网注册'
        '（DeepSeek 为 platform.deepseek.com）→ 在「设置 → API」填入 '
        'Key / Base URL / 模型。费用按用量计入你的服务商账户。',
  ),
];
