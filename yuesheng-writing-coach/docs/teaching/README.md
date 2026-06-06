# 教学资源目录

> 创建日期：2026-06-03  
> 用途：月笙写作教练教学资源的统一索引

```
docs/teaching/
├── README.md                        # 本文件
├── philosophy_V1.md                 # 设计哲学（→ docs/design/design-philosophy_V1.0.md）
├── method-library_V1.md             # 教学策略库（场景→信号→动作→预期效果）
├── technique-library/               # 技法库（拆书蒸馏产出的网文技法）
│   ├── index_V1.md                  # 技法索引
│   ├── technique-kaiqiao_V1.md      # 开篇技法
│   ├── technique-jiezou_V1.md       # 节奏技法
│   ├── technique-duihua_V1.md       # 对话技法
│   ├── technique-shijieguan_V1.md   # 世界观构建技法
│   └── technique-renwu_V1.md        # 人物塑造技法
├── cases/                           # 教学案例（→ docs/cases/）
│   ├── case-ayuan-rebirth-ch1.md
│   └── case-webnovel-chat-2026-06-03.md
└── archives/                        # 教学内容归档（分层/分症候总结）
    ├── summary-by-level_V1.md       # 按用户水平总结
    └── summary-by-syndrome_V1.md    # 按症候分类总结
```

## 四层结构说明

| 层 | 定位 | 文档 | 谁用 |
|----|------|------|------|
| 哲学 | 为什么这么教 | philosophy_V1.md | 设计者 |
| 策略 | 怎么教 | method-library_V1.md | AI / 教练 |
| 技法 | 教什么 | technique-library/ | AI / 学员 |
| 案例 | 教得怎么样 | cases/ + archives/ | 设计者复盘 |

## 关联文件（引用非移动）

| 文件 | 原始位置 | 关系 |
|------|---------|------|
| design-philosophy_V1.0.md | docs/design/ | 教学哲学 |
| action-library.md | resources/prompts/ | 教学动作执行层 |
| yuesheng-prompt-v3.md | resources/prompts/ | 教学行为定义 |
| SPEC_Ability_Map_V1.md | docs/specs/ | 症候→能力→训练映射 |
| SPEC_Intent_Consistency_V1.md | docs/specs/ | 意图-执行一致性规格 |
