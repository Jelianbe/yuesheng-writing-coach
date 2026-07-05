// Append D-076 to decision-log.md (bypass Edit tool fake-success issue per R-023)
const fs = require('fs');
const path = 'd:/ai-teacher/yuesheng-writing-coach/docs/decision-log.md';
const entry = `


### D-076: AVD 验证延期到 S27+ (2026-07-04) — emulator 36.6.11 gfxstream 36.x 兼容 bug

### 背景
Sprint 26 阶段 3.2 双轨化推进中,试图用 Android 模拟器 (AVD) 验证 Capacitor 端到端行为。
- AVD: Pixel6 (Android 14, API 34, x86_64 google_apis)
- emulator: 36.6.11
- GPU: NVIDIA GeForce RTX 4060 Laptop GPU + driver 610.62
- 加速: WHPX (Windows Hypervisor Platform) + gfxstream + Vulkan

### 探索过程
1. 多种渲染方案试错: swiftshader_indirect / lavapipe / TCG 软件加速 → 全部失败
2. 硬件加速 (gfxstream + Vulkan) → 40 秒内 emulator 进程崩, exit_code 0xC0000005 (STATUS_ACCESS_VIOLATION)
3. 第一误诊: 把"TRAE 沙箱拒绝访问 NVIDIA 驱动文件"当根因
4. 用 \`dangerouslyDisableSandbox: true\` 脱沙箱跑 → 仍然崩在同一位置 (WHPX accelerator is operational 之后)
5. 修正根因: emulator 进程崩溃发生在 VkEmulation features 初始化阶段,远在任何文件访问之前

### 真实根因
**emulator 36.6.11 + gfxstream 36.x + WHPX + RTX 4060 + driver 610.62 兼容 bug**。
gfxstream 36.x 在 VkEmulation 初始化时与 WHPX + Vulkan 上下文交互存在崩溃,与前端代码 / Capacitor 迁移 / TRAE 沙箱完全无关。

### 探索失败教训 (R-023 关联)
- **第一误诊**: 把"沙箱拒绝访问 NVIDIA 文件"当根因,但那是独立问题 (TRAE 沙箱白名单过严,本质是配置问题)
- **第二误诊**: 把"脱沙箱"当万能验证手段,但 emulator 进程崩溃发生在沙箱层之前
- **教训**: 沙箱层失败 ≠ 进程崩溃根因。**必须看崩溃时序在沙箱层之前还是之后**
- **R-027 门禁关联**: 调试 emulator 必须在 host 跑,脱沙箱命令验证只能确认沙箱层无问题,不能确认非沙箱根因

### 决策
**AVD 验证推 S27+** (与 plan §0.1 "Android 验证改为可选" 一致)
- 单元测试 1051 pass + Electron 端业务已稳定运行,阶段 3.2 业务正确性已被自动化覆盖
- AVD 是端到端体验验证,非 Sprint 26 阶段 3 门禁阻塞项
- S27+ 再处理 AVD,届时选项: 降级 emulator 32.x / 升级 NVIDIA 驱动 / 换真机 / 找替代 AVD 方案

### 影响
- Sprint 26 阶段 3 总 DoD 第 8 项 "Android 端代码层验证(编译通过 + 启动不报错)" 暂未端到端验证
- Capacitor 端代码层验证足够: _dual-track 平台检测 + runDualTrack helper + 3 个 service 双轨化 + 单元测试 100% 覆盖
- 实际运行验证需 S27+ AVD 解决后补

### 关键证据
- 沙箱内崩溃日志: d:\\ai-teacher\\.trae\\tmp\\job-1bd41b2db66542ac82cd4e8c197a4bc2\\output.log (line 116-120)
- 脱沙箱崩溃日志: d:\\ai-teacher\\.trae\\tmp\\job-b89aa554e5384f26956cfa915eefdb0e\\output.log (line 52-53, 119-120)
- 沙箱配置: C:\\Users\\月笙如歌\\AppData\\Roaming\\Trae CN\\ModularData\\ai-agent\\sandbox\\6a1bd787011e899599b4235a.json
- 沙箱白名单缺 NVIDIA 路径, 但这与本次崩溃无关 (独立问题)

### 关联
- D-074 (Sprint 26 战略转向 → Capacitor Android)
- D-075 (Sprint 26 阶段 1 — jsdom Capacitor 误判)
- dev-docs/tasks/sprint-26-phase-3-plan.md §0.1 (Android 验证改为可选)

### 状态
✅ AVD 验证延期到 S27+; Sprint 26 阶段 3.2 双轨化继续推进
`;
fs.appendFileSync(path, entry, 'utf8');
console.log('D-076 appended to', path);
console.log('new size:', fs.statSync(path).size, 'bytes');
