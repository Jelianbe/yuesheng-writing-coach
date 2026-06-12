---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: f2ac1166b9bdaea71c23aabee181e425_9c254c3165a011f18b225254006c9bbf
    ReservedCode1: W5qV746PVG+A0sTW9HsnUotFFKBRDKOLeYhGw045KNPbK0kLHUYBZNFmaueuRspfGnyFsuN9jnDyjoCx06lyUK/3e0WEMus1MXQ4JPYX6W8AKTaZtNPv4Z4MUvs5yleZIBL41vKMFplE/SzmVHSCYOM/NNgSKKXNgxrohq/BgElXGeY5y5QWY5MtS9Q=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: f2ac1166b9bdaea71c23aabee181e425_9c254c3165a011f18b225254006c9bbf
    ReservedCode2: W5qV746PVG+A0sTW9HsnUotFFKBRDKOLeYhGw045KNPbK0kLHUYBZNFmaueuRspfGnyFsuN9jnDyjoCx06lyUK/3e0WEMus1MXQ4JPYX6W8AKTaZtNPv4Z4MUvs5yleZIBL41vKMFplE/SzmVHSCYOM/NNgSKKXNgxrohq/BgElXGeY5y5QWY5MtS9Q=
---

# SYSTEM_HEALTH_CHECK_PROMPT V1.0

> 月笙写作教练项目 - 每日体检审查清单
> 版本: V1.0 | 日期: 2026-06-11

## 一、P0 致命问题审查

### 1.1 Import 正确性
- [ ] 相对路径 import 目标文件是否存在
- [ ] 路径别名 import（@main/@renderer/@shared/@preload）目标是否存在
- [ ] 误判排除：JSDoc 注释中的 import 示例、外部 npm 包 import
- [ ] 交叉引用检查：store ↔ component 之间是否存在循环依赖风险

### 1.2 函数签名一致性
- [ ] 导出函数签名是否与调用处一致
- [ ] IPC handler 函数签名是否匹配 electron ipcMain.handle 约束 (event, args) => result

### 1.3 IPC 通道完整性
- [ ] 每个 handler 文件是否注册了至少一个 IPC 通道
- [ ] 通道名称是否在 IPC_CHANNELS 常量中定义
- [ ] renderer 端 invoke 的通道名是否与 main 端 handle 一致
- [ ] **工厂模式豁免**：通过 createHandler() 工厂函数注册的视为已注册

### 1.4 DB 事务安全性
- [ ] better-sqlite3 操作是否包裹在事务中
- [ ] 批量写入是否使用 prepare + transaction 模式
- [ ] 错误路径是否正确回滚

## 二、大文件拆分评估

- [ ] 标记超过 300 行的文件
- [ ] Top 10 大文件逐个评估拆分可行性
- [ ] 拆分优先级: 类型声明 > Service > Handler > Component

## 三、类型安全审计

### 3.1 any 类型
- [ ] 全项目 any 使用总数及趋势
- [ ] any 集中文件 Top 10
- [ ] 每个 any 是否可替换为 unknown / 具体类型 / 泛型

### 3.2 @ts-ignore
- [ ] @ts-ignore 使用数量及位置
- [ ] 每个 @ts-ignore 是否有替代方案（如类型守卫、as unknown as T 链）

### 3.3 类型断言 (as)
- [ ] as 断言总数及分布
- [ ] 高风险断言模式：as any, as unknown as T 链

## 四、代码质量指标

### 4.1 调试残留
- [ ] console.log/warn/error 是否应转为统一日志服务
- [ ] 生产环境是否应移除 console 调用

### 4.2 待办标记
- [ ] TODO 数量及所在文件
- [ ] FIXME 数量及所在文件
- [ ] 长期未处理的 TODO（超过 30 天）

## 五、趋势对比

- [ ] 与前一日对比：文件数、总行数、P0 问题数
- [ ] 各项指标（any/@ts-ignore/as断言/console/TODO）的增减趋势
- [ ] 大文件数量变化
- [ ] 异常波动标记（单日 any 突增 > 10 等）

## 六、修复建议优先级

| 优先级 | 条件 | 行动 |
|--------|------|------|
| 🔴 P0 | broken import / 缺失 IPC 通道 / 无事务 DB 写 | 立即修复 |
| 🟡 P1 | 大文件超 800 行 / any > 20 / @ts-ignore > 5 | 本周内 |
| 🟢 P2 | 大文件 300-800 行 / console.log 残留 / TODO 堆积 | 迭代中 |

---

*本清单由 daily_health_scan.py 自动扫描结果驱动，人工审核确认。*
*（内容由AI生成，仅供参考）*
